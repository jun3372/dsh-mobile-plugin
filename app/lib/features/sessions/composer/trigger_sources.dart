/// `/` 与 `@` 的候选来源：把宿主 RPC 结果规约成菜单行。
///
/// 与 Web 的分工一致：
/// - `/` 分组 = 宿主 `commands/list` 的命令 + 两个纯 UI 装饰项
///   （`/model`、`/permission` 在 Web 里也不发给宿主，而是打开选择器）；
///   技能走 `skills/list`，插入字面 `/name ` 文本；
/// - `@` 分组 = `fileReferences/list`（文件/目录）与
///   `sessionReferenceResolver/candidates`（会话）两组候选。
library;

import '../../../../core/models/composer_models.dart';
import '../../../../core/services/dsh_api.dart';
import 'composer_document.dart';

/// 一条菜单候选。
class TriggerItem {
  final String title;
  final String? subtitle;

  /// 选定后写回草稿的插入文本；为 null 时走 [onPick] 动作而不改文本。
  final String? insertion;

  /// 目录行：Web 用 Tab 下钻，App 用点选后保持菜单打开并继续查询。
  final bool drill;

  /// 纯 UI 动作（打开模型/权限选择器等）。
  final void Function()? onPick;

  /// 行首图标（Material IconData 以 int 存储以免 composer 层依赖 UI 包）。
  final int iconCode;

  const TriggerItem({
    required this.title,
    this.subtitle,
    this.insertion,
    this.drill = false,
    this.onPick,
    this.iconCode = 0,
  });
}

/// 一个候选分组。
class TriggerGroup {
  final String title;
  final List<TriggerItem> items;

  const TriggerGroup({required this.title, required this.items});

  bool get isEmpty => items.isEmpty;
}

/// 来源接口：给定触发 token 的 query 返回候选。
abstract class TriggerSource {
  String get groupTitle;

  bool accepts(ComposerTriggerKind kind);

  Future<List<TriggerItem>> candidates(String query);
}

/// 宿主命令（`commands/list`）。结果按会话缓存，命令表基本静态。
class CommandSource extends TriggerSource {
  final DshApi _api;
  final String _sessionId;

  /// Web 侧装饰项：不发命令，而是打开对应选择器。
  final void Function()? onPickModel;
  final void Function()? onPickPermission;
  final void Function()? onPickPlan;

  List<CommandDescriptor>? _cache;

  CommandSource({
    required DshApi api,
    required String sessionId,
    this.onPickModel,
    this.onPickPermission,
    this.onPickPlan,
  }) : _api = api,
       _sessionId = sessionId;

  @override
  String get groupTitle => '指令';

  @override
  bool accepts(ComposerTriggerKind kind) => kind == ComposerTriggerKind.slash;

  @override
  Future<List<TriggerItem>> candidates(String query) async {
    final commands = _cache ??= await _api.commands(sessionId: _sessionId);
    final items = <TriggerItem>[
      for (final command in commands)
        TriggerItem(
          title: command.slash,
          subtitle: command.inputHint == null
              ? command.description
              : '${command.description}（${command.inputHint}）',
          // 命令 token 保留在草稿里，光标后留一个空格便于继续输入参数。
          insertion: '${command.slash} ',
        ),
      if (onPickModel != null)
        TriggerItem(
          title: '/model',
          subtitle: '选择模型与推理力度',
          onPick: onPickModel,
        ),
      if (onPickPermission != null)
        TriggerItem(
          title: '/permission',
          subtitle: '切换权限预设',
          onPick: onPickPermission,
        ),
      if (onPickPlan != null)
        TriggerItem(title: '/plan', subtitle: '切换计划模式', onPick: onPickPlan),
    ];
    return rankByQuery(query, items, name: (item) => item.title);
  }

  void invalidate() => _cache = null;
}

/// 技能（`skills/list`）：与 Web 一致插入字面 `/name ` 文本。
class SkillSource extends TriggerSource {
  final DshApi _api;
  final String _sessionId;
  List<SkillEntry>? _cache;

  SkillSource({required DshApi api, required String sessionId})
    : _api = api,
      _sessionId = sessionId;

  @override
  String get groupTitle => '技能';

  @override
  bool accepts(ComposerTriggerKind kind) => kind == ComposerTriggerKind.slash;

  @override
  Future<List<TriggerItem>> candidates(String query) async {
    final skills = _cache ??= await _api.skills(sessionId: _sessionId);
    final items = [
      for (final skill in skills)
        if (skill.modelInvocable)
          TriggerItem(
            title: '/${skill.name}',
            subtitle: skill.whenToUse ?? skill.description,
            insertion: '/${skill.name} ',
          ),
    ];
    return rankByQuery(query, items, name: (item) => item.title);
  }

  void invalidate() => _cache = null;
}

/// 文件/目录引用（`fileReferences/list`）。
class FileRefSource extends TriggerSource {
  final DshApi _api;
  final String _sessionId;

  FileRefSource({required DshApi api, required String sessionId})
    : _api = api,
      _sessionId = sessionId;

  @override
  String get groupTitle => '文件';

  @override
  bool accepts(ComposerTriggerKind kind) => kind == ComposerTriggerKind.at;

  @override
  Future<List<TriggerItem>> candidates(String query) async {
    final candidates = await _api.fileReferenceCandidates(
      sessionId: _sessionId,
      query: query,
    );
    return rankByQuery(
      query,
      [
        for (final candidate in candidates)
          if (formatFileMention(
                candidate.path,
                isDirectory: candidate.isDirectory,
              )
              case final insertion?)
            TriggerItem(
              title: candidate.name,
              subtitle: candidate.path,
              insertion: insertion,
              drill: candidate.isDirectory,
            ),
      ],
      name: (item) => item.title,
      label: (item) => item.subtitle ?? '',
    );
  }
}

/// 会话引用（`sessionReferenceResolver/candidates`）。
class SessionRefSource extends TriggerSource {
  final DshApi _api;
  final String _sessionId;

  SessionRefSource({required DshApi api, required String sessionId})
    : _api = api,
      _sessionId = sessionId;

  @override
  String get groupTitle => '对话';

  @override
  bool accepts(ComposerTriggerKind kind) => ComposerTriggerKind.at == kind;

  @override
  Future<List<TriggerItem>> candidates(String query) async {
    final candidates = await _api.sessionReferenceCandidates(
      sessionId: _sessionId,
      query: query,
    );
    return rankByQuery(
      query,
      [
        for (final candidate in candidates)
          TriggerItem(
            title: candidate.displayTitle ?? candidate.label,
            subtitle: candidate.cwd,
            insertion: '${formatSessionMention(candidate.mention)} ',
          ),
      ],
      name: (item) => item.title,
      label: (item) => item.subtitle ?? '',
    );
  }
}
