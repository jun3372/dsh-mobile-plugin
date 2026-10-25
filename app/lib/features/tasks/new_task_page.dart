import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/models/agent_mode.dart';
import '../../core/models/composer_models.dart';
import '../../core/models/dsh_session.dart';
import '../../core/mux/workspace_hub.dart';
import '../../core/services/api_client.dart';
import '../../core/services/dsh_api.dart';
import '../../widgets/agent_mode_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/model_picker_sheet.dart';
import '../servers/servers_providers.dart';
import '../sessions/session_page.dart';
import 'tasks_providers.dart';
import 'widgets/hero_header.dart';
import '../../widgets/composer/attachment_sources.dart';
import '../../widgets/composer/attachment_store.dart';
import '../../widgets/composer/composer_bar.dart';
import '../../widgets/composer/composer_controller.dart';
import '../../widgets/composer/trigger_sources.dart';

/// 新建会话页（对齐 Web 端：大标题 + 选择器胶囊 + 白卡输入）。
class NewTaskPage extends ConsumerStatefulWidget {
  const NewTaskPage({super.key});

  @override
  ConsumerState<NewTaskPage> createState() => _NewTaskPageState();
}

class _NewTaskPageState extends ConsumerState<NewTaskPage> {
  /// 建会话前的占位 id：仅用于构造 composer 签名，不发给宿主。
  static const _pendingSessionId = 'new';

  String? _selectedWorkspace;
  bool _workspaceChosen = false;
  AgentMode _mode = AgentMode.standard;
  PermissionPresetOption? _permission;
  ModelSelection? _model;
  bool _planMode = false;

  /// 附件存储与输入条控制器随宿主 api 就绪而创建（无会话时文件上传排队）。
  AttachmentStore? _attachments;

  ComposerController? _composer;

  DshApi? _composerApi;

  /// 会话创建去重：附件触发与点发送可能并发触发建会话。
  Future<String>? _ensuringSession;

  /// 首个创建的会话 id（附件触发预建后，发送时复用，不再新建）。
  String? _createdSessionId;

  /// 已落到会话上的 preset，避免重复切换。
  String? _appliedPreset;

  @override
  void dispose() {
    _composer?.dispose();
    _composer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final workspaces = ref.watch(workspacesProvider);
    final workspace = _effectiveWorkspace(workspaces);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      // SPEC §4：新建任务页画布为 canvas。
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(DshSpace.x3),
              child: CircleButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: DshIcon.header,
                size: DshHeaderMetrics.button,
                tooltip: '返回',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            const Spacer(),
            const Center(child: HeroHeader()),
            const Spacer(),
            _buildSelectors(workspaces, workspace),
            const SizedBox(height: DshSpace.x1),
            _buildComposerArea(workspaces, workspace),
          ],
        ),
      ),
    );
  }

  String _workspaceLabel(WorkspaceRow row) =>
      row.title.isNotEmpty ? row.title : (folderNameOf(row.path) ?? row.path);

  String? _effectiveWorkspace(List<WorkspaceRow> workspaces) {
    if (_workspaceChosen) {
      final selected = _selectedWorkspace;
      return selected != null && workspaces.any((row) => row.path == selected)
          ? selected
          : null;
    }
    return workspaces.isEmpty ? null : workspaces.first.path;
  }

  /// 输入卡上方的选择器胶囊行：工作区 + 模式。
  Widget _buildSelectors(List<WorkspaceRow> workspaces, String? workspace) {
    final p = context.dsh;
    final label = workspace == null
        ? '默认工作区'
        : workspaces
                  .where((row) => row.path == workspace)
                  .map(_workspaceLabel)
                  .firstOrNull ??
              folderNameOf(workspace) ??
              workspace;
    Widget chip({
      required IconData icon,
      required String text,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DshRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DshSpace.x3,
            vertical: DshSpace.x1 + 2,
          ),
          decoration: BoxDecoration(
            color: p.chipGray,
            borderRadius: BorderRadius.circular(DshRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: p.secondaryText),
              const SizedBox(width: DshSpace.x1 + 2),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.bodySmall?.copyWith(
                    fontSize: 14,
                    color: p.midText,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: p.secondaryText,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(DshSpace.x4, 0, DshSpace.x4, 0),
      child: Wrap(
        spacing: DshSpace.x2,
        runSpacing: DshSpace.x2,
        children: [
          chip(
            icon: Icons.folder_outlined,
            text: label,
            onTap: () => _pickWorkspace(workspaces),
          ),
          chip(icon: Icons.hub_outlined, text: _mode.label, onTap: _pickMode),
        ],
      ),
    );
  }

  /// 模式选择：四项共享 Agent 预设选择器。
  Future<void> _pickMode() async {
    final picked = await showAgentModeSheet(
      context,
      currentPresetId: _mode.presetId,
    );
    if (picked == null || !mounted) return;
    setState(() => _mode = picked);
  }

  /// 底部输入区：公用 ComposerBar（工作区/模式走页面胶囊行）。
  Widget _buildComposerArea(List<WorkspaceRow> workspaces, String? workspace) {
    final composer = _ensureComposer();
    if (composer == null) return const SizedBox.shrink();
    return ComposerBar(
      controller: composer,
      view: ComposerViewData(
        ready: true,
        running: false,
        offline: false,
        planActive: _planMode,
        cwd: workspace,
        selectedModel: _model?.$4,
      ),
      sources: _sources ??= AttachmentSources(),
      actions: _composerActions(),
      onError: (message) => showDshSnack(context, message),
    );
  }

  AttachmentSources? _sources;

  /// 输入条控制器随宿主 api 就绪/切换而创建或重建。
  ComposerController? _ensureComposer() {
    final api = ref.read(dshApiProvider);
    if (api == null) {
      _composer?.dispose();
      _composer = null;
      _attachments = null;
      _composerApi = null;
      return null;
    }
    if (_composer != null && identical(_composerApi, api)) return _composer;
    _composer?.dispose();
    _composerApi = api;
    final attachments = AttachmentStore(api: api, sessionId: _pendingSessionId);
    final controller = ComposerController(
      sessionId: _pendingSessionId,
      // 会话尚未创建：文件/会话引用两组 @ 候选不可用，只挂 / 指令源
      // （commands/list 失败有兜底，装饰项 /model /permission /plan 仍在）。
      sources: [
        CommandSource(
          api: api,
          sessionId: _pendingSessionId,
          onPickModel: _pickModel,
          onPickPermission: _pickPermission,
          onPickPlan: () => setState(() => _planMode = !_planMode),
        ),
      ],
      attachments: attachments,
      // 建会话前不落草稿（没有可归属的 sessionId）。
      drafts: null,
      ports: ComposerPorts(
        send: _sendPort,
        executeCommand: _executeCommandPort,
      ),
    );
    // 菜单里的纯 UI 动作（打开模型/权限/计划）由页面处理。
    controller.onPickAction = (pick) => pick.onPick?.call();
    // 文件附件需要有效会话才能上传：选择文件后立即预建会话并开泵上传。
    attachments.addListener(_onAttachmentsChanged);
    _attachments = attachments;
    _composer = controller;
    return controller;
  }

  /// 文件附件到达且尚无会话：预建会话（延迟选择一并落笔）再上传。
  Future<void> _onAttachmentsChanged() async {
    final store = _attachments;
    if (store == null || store.hasSession) return;
    if (!store.items.any((item) => !item.isImage)) return;
    final api = ref.read(dshApiProvider);
    if (api == null) return;
    try {
      final sessionId = await _ensureSession(api);
      store.attachSession(sessionId);
    } on AppException catch (e) {
      if (mounted) showDshError(context, e.userMessage);
    }
  }

  ComposerActions _composerActions() => ComposerActions(
    showModelPicker: _pickModel,
    showPermissionPicker: _pickPermission,
    togglePlan: () => setState(() => _planMode = !_planMode),
    showGoalEditor: () => showDshSnack(context, '目标能力开发中'),
    // 新建页 running 恒为 false，停止钮不会出现。
    cancelTurn: () {},
    hostCommands: () async {
      final api = ref.read(dshApiProvider);
      if (api == null) return const [];
      try {
        return await api
            .commands(sessionId: _createdSessionId ?? _pendingSessionId)
            .then(
              (items) => [
                for (final command in items)
                  if (command.slash != '/plan')
                    TriggerItem(
                      title: command.slash,
                      subtitle: command.description,
                    ),
              ],
            );
      } catch (_) {
        return const [];
      }
    },
  );

  /// 创建会话并落本页延迟生效的选择（模型 / 权限 / 计划模式），幂等。
  Future<String> _ensureSession(DshApi api) {
    return _ensuringSession ??= _doEnsureSession(
      api,
    ).whenComplete(() => _ensuringSession = null);
  }

  Future<String> _doEnsureSession(DshApi api) async {
    final existing = _createdSessionId;
    if (existing != null) {
      await _applyMode(api, existing);
      return existing;
    }
    final rows = ref.read(workspacesProvider);
    final cwd = _effectiveWorkspace(rows);
    // 宿主只在带 workspaceId 建会话时把会话挂进工作区；仅传 cwd 的会话
    // 会一直停留在「未分组」，所以优先按选中行的 workspaceId 创建。
    final workspaceId = rows
        .where((row) => row.path == cwd)
        .map((row) => row.workspaceId)
        .firstOrNull;
    final sessionId = await api.createSession(
      workspaceId: workspaceId,
      cwd: workspaceId == null ? cwd : null,
    );
    _createdSessionId = sessionId;
    // preset 先落：切换会重挂 Agent 插件，权限/计划命令依赖新组装。
    await _applyMode(api, sessionId);
    final model = _model;
    if (model != null) {
      final (provider, modelId, effort, _) = model;
      await api.selectModel(
        sessionId: sessionId,
        provider: provider,
        model: modelId,
        reasoningEffort: effort,
      );
    }
    final permission = _permission;
    if (permission != null) {
      await api.executeCommand(
        sessionId: sessionId,
        line: '/permission ${permission.value}',
      );
    }
    if (_planMode) {
      await api.executeCommand(sessionId: sessionId, line: '/plan');
    }
    return sessionId;
  }

  Future<void> _applyMode(DshApi api, String sessionId) async {
    final presetId = _mode.presetId;
    if (_appliedPreset == presetId) return;
    await api.selectAgentPreset(sessionId: sessionId, presetId: presetId);
    _appliedPreset = presetId;
  }

  /// ComposerPorts.send：建会话 → prompt → 跳转会话详情页。
  Future<void> _sendPort(
    String text,
    List<PromptAttachment> attachments,
    String mode,
  ) async {
    final api = ref.read(dshApiProvider);
    if (api == null) {
      // 抛错走 ComposerController 的统一失败路径：回填文本并提示。
      throw ServerException('请先绑定服务端');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    final sessionId = await _ensureSession(api);
    await api.prompt(
      sessionId: sessionId,
      requestId: newRpcId(),
      text: trimmed,
      attachments: attachments,
    );
    if (!mounted) return;
    ref.invalidate(tasksProvider);
    final cwd = _effectiveWorkspace(ref.read(workspacesProvider));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SessionPage(
          summary: SessionSummary(
            sessionId: sessionId,
            title: trimmed,
            updatedAt: DateTime.now(),
            running: true,
            blank: false,
            cwd: cwd,
          ),
        ),
      ),
    );
  }

  /// ComposerPorts.executeCommand：会话尚未创建时先建会话再执行；
  /// 不导航，失败由 ComposerController 统一回填草稿并提示。
  Future<CommandExecution> _executeCommandPort(
    String line,
    List<PromptAttachment> attachments,
  ) async {
    final api = ref.read(dshApiProvider);
    if (api == null) return const CommandExecution(matched: false, ok: false);
    final sessionId = await _ensureSession(api);
    return api.executeCommand(
      sessionId: sessionId,
      line: line,
      attachments: attachments,
    );
  }

  /// 权限预设：目录来自 `permissionPresets/catalog`，发送时落 `/permission <value>`。
  Future<void> _pickPermission() async {
    final api = ref.read(dshApiProvider);
    if (api == null) {
      showDshSnack(context, '请先绑定服务端');
      return;
    }
    final option = await showPermissionSelectionSheet(
      context,
      api: api,
      current: _permission?.value,
    );
    if (option == null || !mounted) return;
    setState(() => _permission = option);
  }

  /// 模型选择：发送时经 selectModel 生效；未选择时用宿主默认（auto）。
  Future<void> _pickModel() async {
    final api = ref.read(dshApiProvider);
    if (api == null) {
      showDshSnack(context, '请先绑定服务端');
      return;
    }
    final picked = await showModelSelectionSheet(
      context,
      api: api,
      selectedProvider: _model?.$1,
      selectedModel: _model?.$2,
    );
    if (picked == null || !mounted) return;
    setState(() => _model = picked);
  }

  Future<void> _pickWorkspace(List<WorkspaceRow> workspaces) async {
    final choice = await showDshSheet<_WorkspaceChoice>(
      context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          const DshSheetTitle(title: '工作区'),
          ListTile(
            leading: const Icon(Icons.home_outlined, size: 20),
            title: const Text('默认工作区'),
            subtitle: const Text('不指定 cwd，由宿主决定'),
            onTap: () =>
                Navigator.of(sheetContext).pop(const _WorkspaceChoice(null)),
          ),
          for (final row in workspaces)
            ListTile(
              leading: const Icon(Icons.folder_outlined, size: 20),
              title: Text(
                _workspaceLabel(row),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                row.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_WorkspaceChoice(row.path)),
            ),
          const Divider(indent: DshSpace.x4, endIndent: DshSpace.x4),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined, size: 20),
            title: const Text('新建工作区…'),
            subtitle: const Text('把电脑上的一个目录注册为工作区'),
            onTap: () async {
              final path = await _askWorkspacePath(sheetContext);
              if (path == null || !sheetContext.mounted) return;
              Navigator.of(
                sheetContext,
              ).pop(_WorkspaceChoice(path, created: true));
            },
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.path != null && !choice.created) {
      setState(() {
        _workspaceChosen = true;
        _selectedWorkspace = choice.path;
      });
      return;
    }
    // 新建：注册目录后直接选中。
    try {
      final row = await ref
          .read(workspacesProvider.notifier)
          .create(choice.path!);
      if (!mounted) return;
      setState(() {
        _workspaceChosen = true;
        _selectedWorkspace = row.path;
      });
    } on AppException catch (e) {
      if (mounted) showDshError(context, e.userMessage);
    }
  }

  Future<String?> _askWorkspacePath(BuildContext sheetContext) async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建工作区'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '电脑上的目录绝对路径',
            hintText: '例如 /Users/me/projects/demo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return null;
    return path;
  }
}

/// 工作区选择结果；[path] 为 null 表示显式选择默认工作区，
/// [created] 为 true 表示需要先向宿主注册该目录。
class _WorkspaceChoice {
  final String? path;
  final bool created;

  const _WorkspaceChoice(this.path, {this.created = false});
}
