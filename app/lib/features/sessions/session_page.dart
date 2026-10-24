import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/models/composer_models.dart';
import '../../core/models/dsh_session.dart';
import '../../core/models/queued_message.dart';
import '../../core/services/dsh_api.dart';
import '../../core/session/session_replica.dart'
    show PlanReview, SessionQuestionPrompt;
import '../../widgets/common.dart';
import '../../widgets/model_picker_sheet.dart';
import '../servers/servers_providers.dart';
import '../tasks/tasks_providers.dart';
import 'composer/attachment_sources.dart';
import 'composer/attachment_store.dart';
import 'composer/composer_bar.dart';
import 'composer/composer_controller.dart';
import 'composer/composer_draft_store.dart';
import 'composer/trigger_sources.dart';
import 'session_providers.dart';
import 'widgets/approval_card.dart';
import 'widgets/chat_pane.dart';
import 'widgets/queue_dock.dart';
import 'widgets/session_details_sheet.dart';
import 'widgets/session_header.dart';
import 'widgets/session_status_bar.dart';
import 'widgets/trace_pane.dart';
import 'workspace_files_page.dart';

/// 会话详情页：头部 + 对话面板 + 底部输入条。
class SessionPage extends ConsumerStatefulWidget {
  final SessionSummary summary;

  const SessionPage({super.key, required this.summary});

  @override
  ConsumerState<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends ConsumerState<SessionPage> {
  final _sources = AttachmentSources();

  /// 输入区子系统：随宿主 api 就绪后创建，切换服务端时重建。
  ComposerController? _composer;
  DshApi? _composerApi;
  CommandSource? _commandSource;

  @override
  void dispose() {
    _composer?.dispose();
    _composer = null;
    super.dispose();
  }

  SessionKey get _key => (
    sessionId: widget.summary.sessionId,
    serverId: ref.read(currentServerIdProvider),
    initialRunning: widget.summary.running,
    initialBlank: widget.summary.blank,
    initialTitle: widget.summary.title,
  );

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(sessionProvider(_key)).value;
    final server = ref.watch(currentServerProvider);
    final p = context.dsh;
    // 键盘是否弹起：驱动底部固定区（状态栏）让位，避免 composer 溢出。
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      // SPEC §4：会话页画布为 canvas。
      backgroundColor: p.canvas,
      // 聊天页标准做法：不让键盘压缩 body（否则底部固定区之和会溢出 body），
      // 改由输入区自身用 viewInsets.bottom 抬到键盘上方。
      resizeToAvoidBottomInset: false,
      // 底部安全区由输入区自行消化（只保留一半），让输入条更贴底。
      body: SafeArea(
        bottom: false,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              SessionHeader(
                title: view?.title ?? widget.summary.title,
                serverName: server?.name ?? server?.origin.host,
                onBack: () => Navigator.of(context).pop(),
                onFolder: _openWorkspaceFiles,
                onMore: _showSessionMenu,
                onTitleTap: _showSessionDetails,
              ),
              TabBar(
                tabs: const [
                  Tab(text: '对话', height: 26),
                  Tab(text: '轨迹', height: 26),
                ],
                labelColor: p.foreground,
                unselectedLabelColor: p.secondaryText,
                indicatorColor: p.foreground,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: p.divider,
                labelStyle: context.dshText.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: context.dshText.bodyMedium,
                tabAlignment: TabAlignment.start,
                isScrollable: true,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ChatPane(sessionKey: _key),
                    TracePane(sessionKey: _key),
                  ],
                ),
              ),
              // 键盘弹起时隐藏底部状态栏：输入态不需要「轮数·工具·tokens」，
              // 且省出的高度吸收 composer + 键盘对 Column 的溢出（此前溢出 16px）。
              if (view != null && !keyboardOpen) SessionStatusBar(view: view),
              _buildInputArea(view),
            ],
          ),
        ),
      ),
    );
  }

  /// ⋯菜单：置顶 / 重命名 / 分叉 / 归档（popover 贴 ⋯ 按钮右下角弹出）。
  void _showSessionMenu(BuildContext anchorContext) {
    final sessionId = _key.sessionId;
    final pinned = ref.read(pinnedIdsProvider).contains(sessionId);
    final archived = ref.read(archivedIdsProvider).contains(sessionId);
    showDshPopoverMenu(
      anchorContext,
      sections: [
        DshPopoverSection(
          options: [
            DshPopoverOption(
              label: pinned ? '取消置顶' : '置顶',
              icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              onTap: () => _togglePinned(sessionId, pinned: pinned),
            ),
            DshPopoverOption(
              label: '重命名',
              icon: Icons.drive_file_rename_outline,
              onTap: _showRenameDialog,
            ),
            DshPopoverOption(
              label: '分叉新会话',
              icon: Icons.call_split_rounded,
              onTap: _fork,
            ),
            DshPopoverOption(
              label: archived ? '取消归档' : '归档',
              icon: Icons.inventory_2_outlined,
              onTap: () => _toggleArchived(sessionId, archived: archived),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _togglePinned(String sessionId, {required bool pinned}) async {
    final notifier = ref.read(pinnedIdsProvider.notifier);
    try {
      if (pinned) {
        await notifier.unpin(sessionId);
      } else {
        await notifier.pin(sessionId);
      }
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  Future<void> _toggleArchived(
    String sessionId, {
    required bool archived,
  }) async {
    if (!archived) {
      // 归档是不可见的破坏性变更，先确认。
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('归档会话'),
          content: const Text('归档后将回到首页，可在归档管理中找回。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('归档'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final notifier = ref.read(archivedIdsProvider.notifier);
    try {
      if (archived) {
        await notifier.unarchive(sessionId);
      } else {
        await notifier.archive(sessionId);
        if (!mounted) return;
        // 归档后当前会话不再属于活跃列表，退回首页。
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  /// 点击头部标题：从底部弹出当前会话详情（任务 ID / 元数据）。
  void _showSessionDetails() {
    final view = ref.read(sessionProvider(_key)).value;
    final server = ref.read(currentServerProvider);
    final cwd = view?.cwd ?? widget.summary.cwd;
    showSessionDetailsSheet(
      context,
      details: SessionDetails(
        sessionId: _key.sessionId,
        title: view?.title ?? widget.summary.title,
        projectName: folderNameOf(cwd),
        model: view?.selectedModel,
        environment: server?.origin.host,
        createdAt: widget.summary.createdAt,
        updatedAt: widget.summary.updatedAt,
      ),
    );
  }

  /// 打开工作区文件页：按目录浏览当前项目下的文件与文件夹。
  void _openWorkspaceFiles() {
    final cwd = ref.read(sessionProvider(_key)).value?.cwd;
    Navigator.of(context).push(
      dshSlideRoute<void>(
        WorkspaceFilesPage(sessionId: _key.sessionId, cwd: cwd),
      ),
    );
  }

  void _showRenameDialog() {
    final current = ref.read(sessionProvider(_key)).value?.title ?? '';
    final controller = TextEditingController(text: current);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '会话名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isEmpty) return;
              Navigator.of(dialogContext).pop();
              try {
                await ref.read(sessionProvider(_key).notifier).rename(title);
              } on AppException catch (e) {
                if (mounted) _showError(e.userMessage);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _fork() async {
    try {
      final newId = await ref.read(sessionProvider(_key).notifier).fork();
      if (!mounted) return;
      final title = ref.read(sessionProvider(_key)).value?.title;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionPage(
            summary: SessionSummary(
              sessionId: newId,
              title: title == null ? null : '$title（分叉）',
            ),
          ),
        ),
      );
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  Future<void> _showModelPicker() async {
    final api = ref.read(dshApiProvider);
    if (api == null || !mounted) return;
    final current = ref.read(sessionProvider(_key)).value;
    final picked = await showModelSelectionSheet(
      context,
      api: api,
      selectedProvider: current?.selectedProvider,
      selectedModel: current?.selectedModel,
    );
    if (picked == null || !mounted) return;
    final (provider, model, effort, label) = picked;
    try {
      await ref
          .read(sessionProvider(_key).notifier)
          .selectModel(
            provider: provider,
            model: model,
            reasoningEffort: effort,
          );
      if (mounted) _composer?.showNotice('已切换到 $label');
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  /// 底部输入区：排队面板 + 输入条（宿主未就绪时只显示排队面板）。
  /// 待确认的计划评审（计划未开始）：输入条不渲染，输入区位只放应答动作条
  /// （建议修改/允许一次），计划正文卡在对话流渲染（PlanReviewContentCard）。
  /// 外层 SafeArea 不占底部，这里只保留一半手势条高度，输入条更贴底。
  Widget _buildInputArea(SessionViewState? view) {
    final composer = _ensureComposer(view);
    final planReview = view?.pendingPlanReview;
    return Padding(
      padding: EdgeInsets.only(
        // 键盘弹起时整体抬到键盘上方（body 未被压缩，这里吃 viewInsets）。
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom * 0.5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (view != null)
            QueueDock(
              queue: view.queue,
              canSteer: view.running,
              onAction: _onQueueAction,
            ),
          if (planReview case final pending?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: PlanReviewActionBar(
                key: ValueKey('plan-review-bar-${pending.prompt.key}'),
                review: pending.review,
                onApprove: () =>
                    _answerPlanReview(pending.prompt, pending.review),
                onFeedback: (text) => _answerPlanReview(
                  pending.prompt,
                  pending.review,
                  feedback: text,
                ),
              ),
            )
          else if (view != null && composer != null)
            ComposerBar(
              controller: composer,
              view: view,
              sources: _sources,
              actions: _composerActions(),
              onError: _showError,
            ),
        ],
      ),
    );
  }

  /// 计划评审卡应答：「确认开始计划」= 选中 approve 标签，Agent 按计划开工；
  /// 「建议修改→提交反馈」= 选中 decline 标签 + custom（宿主让 Agent 留在
  /// 计划模式并回传反馈）。应答成功后投影刷新，输入条自动恢复渲染。
  Future<void> _answerPlanReview(
    SessionQuestionPrompt prompt,
    PlanReview review, {
    String? feedback,
  }) async {
    final option = feedback == null
        ? review.approve
        : (review.decline ?? review.approve);
    try {
      await ref.read(sessionProvider(_key).notifier).answerQuestion(prompt, [
        QuestionAnswer(
          questionId: review.question.id,
          selected: [option.label],
          custom: feedback,
        ),
      ]);
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  /// 输入区控制器随宿主 api 就绪/切换而创建或重建。
  ComposerController? _ensureComposer(SessionViewState? view) {
    final api = ref.read(dshApiProvider);
    if (api == null || view == null) {
      _disposeComposer();
      return null;
    }
    if (_composer != null && identical(_composerApi, api)) return _composer;
    _disposeComposer();
    _composerApi = api;
    final notifier = ref.read(sessionProvider(_key).notifier);
    final drafts = ComposerDraftStore(ref.read(sharedPreferencesProvider));
    final commandSource = CommandSource(
      api: api,
      sessionId: _key.sessionId,
      onPickModel: _showModelPicker,
      onPickPermission: _showPermissionPicker,
      onPickPlan: _togglePlanMode,
    );
    _commandSource = commandSource;
    final controller = ComposerController(
      sessionId: _key.sessionId,
      sources: [
        commandSource,
        SkillSource(api: api, sessionId: _key.sessionId),
        FileRefSource(api: api, sessionId: _key.sessionId),
        SessionRefSource(api: api, sessionId: _key.sessionId),
      ],
      attachments: AttachmentStore(
        api: api,
        sessionId: _key.sessionId,
        limits: view.imageLimits,
      ),
      drafts: drafts,
      ports: ComposerPorts(
        send: (text, attachments, mode) =>
            notifier.send(text, attachments: attachments, mode: mode),
        executeCommand: (line, attachments) =>
            notifier.executeCommand(line, attachments),
      ),
    );
    // 菜单里的纯 UI 动作（打开模型/权限/计划）由页面处理。
    controller.onPickAction = (pick) => pick.onPick?.call();
    unawaited(controller.loadDraft());
    _composer = controller;
    return controller;
  }

  void _disposeComposer() {
    _composer?.dispose();
    _composer = null;
    _composerApi = null;
    _commandSource = null;
  }

  ComposerActions _composerActions() => ComposerActions(
    showModelPicker: _showModelPicker,
    showPermissionPicker: _showPermissionPicker,
    togglePlan: _togglePlanMode,
    showGoalEditor: _showGoalEditor,
    cancelTurn: _cancel,
    hostCommands: _hostCommands,
  );

  /// 「+」菜单的指令分组：直接取宿主命令表，去掉已有固定入口的三项。
  Future<List<TriggerItem>> _hostCommands() async {
    final source = _commandSource;
    if (source == null) return const [];
    try {
      final items = await source.candidates('');
      const fixed = {'/model', '/permission', '/plan'};
      return items.where((item) => !fixed.contains(item.title)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 权限预设：目录来自 `permissionPresets/catalog`，落笔走 `/permission <value>`。
  Future<void> _showPermissionPicker() async {
    final api = ref.read(dshApiProvider);
    if (api == null || !mounted) return;
    final current = ref.read(sessionProvider(_key)).value?.permissionValue;
    final option = await showPermissionSelectionSheet(
      context,
      api: api,
      current: current,
    );
    if (option == null || !mounted) return;
    _runComposerLine('/permission ${option.value}');
  }

  /// 计划模式：Web 同样只用 `/plan`、`/plan off` 落笔。
  void _togglePlanMode() {
    final active = ref.read(sessionProvider(_key)).value?.plan?.active ?? false;
    _runComposerLine(active ? '/plan off' : '/plan');
  }

  Future<void> _runComposerLine(String line) async {
    try {
      final result = await ref
          .read(sessionProvider(_key).notifier)
          .executeCommand(line);
      if (!mounted) return;
      if (!result.matched) {
        _showError('宿主未支持 $line');
      } else if (!result.ok) {
        _showError(result.text.isEmpty ? '$line 执行失败' : result.text);
      }
      // 成功不再回显 result.text：对齐 Web popupSelect.onSelect——
      // 只按 ok/matched 判失败，成功静默，状态由投影刷新体现在盾牌/模式钮上。
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  /// 目标编辑：无目标时新建，有目标时按 CAS 引用改正文。
  void _showGoalEditor() {
    final goal = ref.read(sessionProvider(_key)).value?.goal;
    final controller = TextEditingController(text: goal?.objective ?? '');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(goal == null ? '设定目标' : '编辑目标'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '目标描述'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final objective = controller.text.trim();
              if (objective.isEmpty) return;
              Navigator.of(dialogContext).pop();
              final notifier = ref.read(sessionProvider(_key).notifier);
              try {
                if (goal == null) {
                  await notifier.createGoal(objective);
                } else {
                  await notifier.editGoal(
                    GoalRef(id: goal.id, revision: goal.revision),
                    objective: objective,
                  );
                }
              } on AppException catch (e) {
                if (mounted) _showError(e.userMessage);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel() async {
    try {
      await ref.read(sessionProvider(_key).notifier).cancelTurn();
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  Future<void> _onQueueAction(
    QueuedMessage item,
    QueueItemAction action,
  ) async {
    final notifier = ref.read(sessionProvider(_key).notifier);
    try {
      switch (action) {
        case QueueItemAction.recall:
          // 撤回编辑：移出队列并把文本回填输入框；图片消息无法恢复
          // 附件，按纯撤回处理（仅移出队列）。
          await notifier.removeQueueItem(item.itemId);
          if (item.text.isNotEmpty) await _composer?.recallToInput(item.text);
        case QueueItemAction.steer:
          // ⚡ 立即发送：先打断当前回合，再把该消息立刻发出（新回合）。
          await notifier.steerImmediately(item);
      }
    } on AppException catch (e) {
      if (mounted) _showError(e.userMessage);
    }
  }

  void _showError(String message) => showDshError(context, message);
}
