/// 输入区控制器：文档状态、触发菜单联动、IME 保护、占位文案与提交生命周期。
///
/// 语义对齐 dsh Web 的 `dsh-client-ui-composer`：
/// - 运行中空草稿时主按钮变成「发出全部排队消息」；
/// - 运行中有内容时按用户选择的补位方式（排队/打断）发送，选择跨会话记住
///   （补位方式切换 UI 已移除，mode 保留持久化值供发送语义使用）；
/// - 草稿以 `/命令` 开头时走 `commands/execute`，而不是当成普通 prompt；
/// - 发送失败按原顺序还原文本与附件，成功后清空并落盘；
/// - 中文输入法组合态期间抑制 `/` `@` 检测，提交字母后再评估。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/errors.dart';
import '../../../core/models/composer_models.dart';
import '../../../core/services/dsh_api.dart';
import 'attachment_store.dart';
import 'composer_draft_store.dart';
import 'composer_document.dart';
import 'trigger_menu_controller.dart';
import 'trigger_sources.dart';

/// 占位文案的状态优先级（与 Web 的 input placeholder 分支一致）。
enum ComposerPlaceholderState {
  ready,
  workspace,
  plan,
  steerQueue,
  parentOffline,
  unavailable,
}

/// 控制器需要的会话侧快照，由页面每次构建时同步进来。
class ComposerEnvironment {
  final bool ready;
  final bool running;
  final bool offline;
  final bool planMode;
  final String? workspaceName;

  /// 队列里是否有可插队的消息（决定空输入时主按钮是否可用）。
  final bool hasQueued;

  const ComposerEnvironment({
    this.ready = false,
    this.running = false,
    this.offline = false,
    this.planMode = false,
    this.workspaceName,
    this.hasQueued = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ComposerEnvironment &&
      other.ready == ready &&
      other.running == running &&
      other.offline == offline &&
      other.planMode == planMode &&
      other.workspaceName == workspaceName &&
      other.hasQueued == hasQueued;

  @override
  int get hashCode =>
      Object.hash(ready, running, offline, planMode, workspaceName, hasQueued);
}

/// 提交出口：由页面用会话 Notifier 的 tear-off 注入，composer 子系统不依赖 riverpod。
class ComposerPorts {
  final Future<void> Function(
    String text,
    List<PromptAttachment> attachments,
    String mode,
  )
  send;

  /// 宿主命令执行；返回 matched=false 表示宿主未识别该指令。
  final Future<CommandExecution> Function(
    String line,
    List<PromptAttachment> attachments,
  )
  executeCommand;

  /// 把当前排队消息全部立即插队发出。
  final Future<void> Function() steerQueued;

  const ComposerPorts({
    required this.send,
    required this.executeCommand,
    required this.steerQueued,
  });
}

class ComposerController extends ChangeNotifier {
  final String sessionId;
  final AttachmentStore attachments;
  final ComposerDraftStore? drafts;
  final ComposerPorts ports;
  final List<TriggerSource> sources;
  final TextEditingController text;

  /// 纯 UI 动作候选（打开模型/权限选择器等）交给页面处理。
  void Function(TriggerPick pick)? onPickAction;

  late final TriggerMenuController menu = TriggerMenuController(
    sources: sources,
    onDraftEdited: _applyDraftEdit,
    onActionPick: (pick) => onPickAction?.call(pick),
  );

  ComposerEnvironment environment = const ComposerEnvironment();

  /// 一次性提示（上传阻断、指令结果、发送失败）。
  String? notice;

  bool sending = false;

  /// 运行中的补位方式：queue（下一轮）/ steer（立即打断）。
  String mode = 'queue';

  static const _autosaveDelay = Duration(milliseconds: 400);

  Timer? _autosave;

  ComposerController({
    required this.sessionId,
    required this.sources,
    required this.attachments,
    required this.ports,
    this.drafts,
    TextEditingController? textController,
  }) : text = textController ?? TextEditingController() {
    mode = drafts?.readSendMode() ?? 'queue';
    text.addListener(_onTextChanged);
    attachments.addListener(_onAttachmentsChanged);
    // 菜单自身的开关/高亮变化也向上冒泡，输入条只需监听控制器。
    menu.addListener(notifyListeners);
  }

  // ---------------------------------------------------------------- 派生状态

  String get draftText => text.value.text;

  bool get hasContent => draftText.trim().isNotEmpty || !attachments.isEmpty;

  bool get isComposing => text.value.composing.isValid;

  int get caret => text.value.selection.baseOffset.clamp(0, draftText.length);

  bool get menuOpen => menu.isOpen;

  bool get canSend =>
      environment.ready &&
      !sending &&
      hasContent &&
      attachments.sendBlocker == null;

  /// 主按钮是否切换为「发出全部排队消息」。
  bool get showSteerAll => environment.running && !hasContent;

  String? get sendBlocker => attachments.sendBlocker;

  TriggerGuard get guard {
    if (!environment.ready || environment.offline) return TriggerGuard.frozen;
    // 光标仍停在 /token 上说明命令正在输入，此时不能按「已认领」抑制 /。
    final active = detectComposerTrigger(
      draftText,
      caret,
      guard: TriggerGuard.plain,
    );
    if (active?.kind == ComposerTriggerKind.slash) return TriggerGuard.plain;
    return hasClaimedCommand(draftText)
        ? TriggerGuard.claimed
        : TriggerGuard.plain;
  }

  ComposerPlaceholderState get placeholderState {
    if (!environment.ready) return ComposerPlaceholderState.unavailable;
    if (environment.offline) return ComposerPlaceholderState.parentOffline;
    if (environment.planMode) return ComposerPlaceholderState.plan;
    if (showSteerAll) return ComposerPlaceholderState.steerQueue;
    if (environment.workspaceName != null &&
        environment.workspaceName!.isNotEmpty) {
      return ComposerPlaceholderState.workspace;
    }
    return ComposerPlaceholderState.ready;
  }

  String get placeholderText {
    final workspace = environment.workspaceName;
    return switch (placeholderState) {
      ComposerPlaceholderState.unavailable => '正在恢复会话…',
      ComposerPlaceholderState.parentOffline => '连接已断开，重连后可继续发送',
      ComposerPlaceholderState.plan => '规划模式：描述目标或提出问题',
      ComposerPlaceholderState.steerQueue => '输入补充说明，或发出全部排队消息',
      ComposerPlaceholderState.workspace =>
        // 带工作区名时不再塞触发符提示，避免占位文案换行撑高输入卡。
        '在 ${(workspace ?? '').split('/').last} 中描述任务',
      ComposerPlaceholderState.ready => '描述你的任务 · / 指令 · @ 引用文件',
    };
  }

  // ---------------------------------------------------------------- 状态同步

  void syncEnvironment(ComposerEnvironment next) {
    if (next == environment) return;
    final wasFrozen = environment.offline || !environment.ready;
    environment = next;
    final isFrozen = next.offline || !next.ready;
    if (wasFrozen != isFrozen) _evaluateTrigger();
    notifyListeners();
  }

  void dismissNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  void showNotice(String message) {
    notice = message;
    notifyListeners();
  }

  void setMode(String next) {
    if (next == mode) return;
    mode = next;
    drafts?.writeSendMode(mode);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 文本联动

  void _onTextChanged() {
    if (!_suppressEvaluation) _evaluateTrigger();
    _scheduleAutosave();
    notifyListeners();
  }

  /// 候选插入自身不重新评估触发符：菜单在 pick 里已经决定好开/关，
  /// 否则刚插入 `/compact ` 就会因为光标仍停在 token 上而立刻重开。
  bool _suppressEvaluation = false;

  void _onAttachmentsChanged() => notifyListeners();

  void _evaluateTrigger() {
    if (isComposing) {
      // 组合态期间不落菜单，避免把拼音字母当成查询刷屏。
      menu.guard = TriggerGuard.frozen;
      menu.onDraftChanged(draftText, caret);
      return;
    }
    menu.guard = guard;
    menu.onDraftChanged(draftText, caret);
  }

  /// 候选落地：写回草稿并把光标放到插入末尾。
  void _applyDraftEdit(String value, int caretOffset) {
    final offset = caretOffset.clamp(0, value.length);
    _suppressEvaluation = true;
    try {
      text.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: offset),
        composing: TextRange.empty,
      );
    } finally {
      _suppressEvaluation = false;
    }
  }

  void closeMenu() => menu.dismiss();

  // ---------------------------------------------------------------- 草稿持久化

  void _scheduleAutosave() {
    _autosave?.cancel();
    if (drafts == null) return;
    _autosave = Timer(_autosaveDelay, saveDraft);
  }

  void saveDraft() {
    final store = drafts;
    if (store == null) return;
    store.write(
      sessionId,
      text: draftText,
      imagePaths: [
        for (final item in attachments.items)
          if (item.isImage) item.path,
      ],
      filePaths: [
        for (final item in attachments.items)
          if (!item.isImage) item.path,
      ],
    );
  }

  /// 进入会话时恢复草稿；文件按原路径重新入队上传。
  Future<void> loadDraft() async {
    final store = drafts;
    if (store == null) return;
    final stored = store.read(sessionId);
    if (stored == null || stored.isEmpty) return;
    if (stored.text.isNotEmpty) {
      text.value = TextEditingValue(
        text: stored.text,
        selection: TextSelection.collapsed(offset: stored.text.length),
      );
    }
    if (stored.imagePaths.isNotEmpty) {
      await attachments.addImages(stored.imagePaths);
    }
    if (stored.filePaths.isNotEmpty) {
      await attachments.addFiles(stored.filePaths);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- 提交流程

  /// 提交当前草稿：命令走 commands/execute，其余走 prompt。
  Future<void> submit() async {
    if (sending || !environment.ready) return;
    final blocker = attachments.sendBlocker;
    if (blocker != null) {
      showNotice(blocker);
      return;
    }
    final line = draftText.trim();
    if (line.isEmpty && attachments.isEmpty) return;
    final built = attachments.buildAttachments() ?? const <PromptAttachment>[];
    final snapshotText = draftText;
    final snapshotAttachments = attachments.items;
    final isCommand = hasClaimedCommand(line);

    _autosave?.cancel();
    text.value = const TextEditingValue();
    attachments.clear();
    drafts?.clear(sessionId);
    sending = true;
    notice = null;
    notifyListeners();

    try {
      if (isCommand) {
        final result = await ports.executeCommand(line, built);
        if (!result.matched) {
          _restore(snapshotText, snapshotAttachments);
          showNotice('未识别的指令：$line');
        } else if (!result.ok) {
          _restore(snapshotText, snapshotAttachments);
          showNotice(result.text.isEmpty ? '指令执行失败' : result.text);
        } else if (result.text.isNotEmpty) {
          showNotice(result.text);
        }
      } else {
        await ports.send(line, built, environment.running ? mode : 'queue');
      }
    } on AppException catch (error) {
      _restore(snapshotText, snapshotAttachments);
      showNotice(error.userMessage);
    } catch (_) {
      _restore(snapshotText, snapshotAttachments);
      showNotice('发送失败，请重试');
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  /// 运行中且输入为空：把排队消息全部立即发出。
  Future<void> steerAll() async {
    if (sending) return;
    sending = true;
    notifyListeners();
    try {
      await ports.steerQueued();
    } on AppException catch (error) {
      showNotice(error.userMessage);
    } catch (_) {
      showNotice('插队失败，请重试');
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  /// 从「+」菜单直接执行一条宿主指令（不带草稿与附件）。
  Future<void> runCommand(String line) async {
    if (sending) return;
    sending = true;
    notice = null;
    notifyListeners();
    try {
      final result = await ports.executeCommand(line, const []);
      if (!result.matched) {
        showNotice('未识别的指令：$line');
      } else if (!result.ok) {
        showNotice(result.text.isEmpty ? '指令执行失败' : result.text);
      } else if (result.text.isNotEmpty) {
        showNotice(result.text);
      }
    } on AppException catch (error) {
      showNotice(error.userMessage);
    } catch (_) {
      showNotice('指令执行失败');
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  void _restore(String value, List<DraftAttachment> items) {
    if (value.isNotEmpty) {
      text.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    attachments.restore(items);
    saveDraft();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _autosave = null;
    text.removeListener(_onTextChanged);
    attachments.removeListener(_onAttachmentsChanged);
    menu.removeListener(notifyListeners);
    saveDraft();
    menu.dispose();
    text.dispose();
    super.dispose();
  }
}
