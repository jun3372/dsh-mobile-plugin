import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/models/composer_models.dart';
import '../../core/models/dsh_session.dart';
import '../../core/models/server_profile.dart';
import '../../core/mux/workspace_hub.dart';
import '../../core/services/api_client.dart';
import '../../widgets/common.dart';
import '../../widgets/model_picker_sheet.dart';
import '../servers/servers_providers.dart';
import '../sessions/session_page.dart';
import 'tasks_providers.dart';
import 'widgets/hero_header.dart';
import 'widgets/new_task_input_card.dart';

/// 任务模式（对齐 Web 端「标准模式」选择器；宿主暂无对应概念，仅本地态）。
enum TaskMode {
  standard('标准模式', '处理代码、文件和资料，适合大多数任务。'),
  ptc('PTC 模式', '包含标准模式的所有能力，更适合批量调用工具，并对结果进行筛选、整理、去重、统计或汇总的任务。'),
  minimal('极简模式', 'Agent 使用终端和图片读取工具，并支持上下文压缩，适合测试和对比其基础表现。'),
  creative('创造模式', '用对话定制 DSH：让 Agent 编写插件，添加新功能或界面；也能组合工具和提示词，创建自己的模式。');

  final String label;
  final String description;

  const TaskMode(this.label, this.description);
}

/// 新建会话页（对齐 Web 端：大标题 + 选择器胶囊 + 白卡输入）。
class NewTaskPage extends ConsumerStatefulWidget {
  const NewTaskPage({super.key});

  @override
  ConsumerState<NewTaskPage> createState() => _NewTaskPageState();
}

class _NewTaskPageState extends ConsumerState<NewTaskPage> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  bool _sending = false;
  String? _selectedWorkspace;
  bool _workspaceChosen = false;
  TaskMode _mode = TaskMode.standard;
  PermissionPresetOption? _permission;
  ModelSelection? _model;
  bool _planMode = false;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _inputController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final server = ref.watch(currentServerProvider);
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
                tooltip: '返回',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            const Spacer(),
            const Center(child: HeroHeader()),
            const Spacer(),
            _buildSelectors(workspaces, workspace),
            _buildInputCard(server),
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

  /// 模式选择（截图对齐：四项带描述，仅本地态）。
  Future<void> _pickMode() async {
    await showDshSheet<void>(
      context,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DshSheetTitle(title: '会话模式'),
            for (final mode in TaskMode.values)
              ListTile(
                title: Text(mode.label),
                subtitle: Text(
                  mode.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: mode == _mode
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _mode = mode);
                },
              ),
            const SizedBox(height: DshSpace.x2),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard(ServerProfile? server) {
    return NewTaskInputCard(
      controller: _inputController,
      focus: _inputFocus,
      sending: _sending,
      onSend: () => _send(server),
      onPickAdd: _showAddSheet,
      onPickPermission: _pickPermission,
      onPickModel: _pickModel,
      onTogglePlan: () => setState(() => _planMode = !_planMode),
      planActive: _planMode,
      permissionLabel: _permission?.name ?? '',
      modelLabel: _model?.$4 ?? 'auto',
    );
  }

  /// 「+」菜单（对齐 Web 端：添加 + 指令两个分组）。
  /// 无会话上下文的项（文件/目标/反馈/压缩/下载日志）为占位入口。
  Future<void> _showAddSheet() async {
    await showDshSheet<void>(
      context,
      heightFactor: 0.75,
      builder: (sheetContext) {
        void stub(String message) {
          Navigator.of(sheetContext).pop();
          showDshSnack(context, message);
        }

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DshSheetTitle(title: '添加'),
              _SheetTile(
                icon: Icons.attach_file_outlined,
                title: '文件',
                keyword: 'file',
                onTap: () => stub('发送后在会话中添加文件'),
              ),
              _SheetTile(
                icon: Icons.flag_outlined,
                title: '目标',
                keyword: 'goal',
                subtitle: '设置或查看长期任务目标',
                onTap: () => stub('目标能力开发中'),
              ),
              _SheetTile(
                icon: Icons.assignment_outlined,
                title: '计划',
                keyword: 'plan',
                subtitle: '进入或退出计划模式',
                trailing: _planMode ? const Icon(Icons.check, size: 20) : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _planMode = !_planMode);
                },
              ),
              _SheetTile(
                icon: Icons.send_outlined,
                title: '反馈',
                keyword: 'feedback',
                subtitle: '发送关于当前会话的反馈',
                onTap: () => stub('反馈渠道开发中'),
              ),
              const Divider(height: DshSpace.x4),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DshSpace.x5,
                  DshSpace.x1,
                  DshSpace.x5,
                  DshSpace.x1,
                ),
                child: Text(
                  '指令',
                  style: context.dshText.labelSmall?.copyWith(
                    color: context.dsh.tertiaryText,
                  ),
                ),
              ),
              _SheetTile(
                icon: Icons.compress_outlined,
                title: '压缩',
                keyword: 'compact',
                subtitle: '压缩以上对话内容',
                onTap: () => stub('发送后在会话中使用 /compact'),
              ),
              _SheetTile(
                icon: Icons.shield_outlined,
                title: '权限',
                keyword: 'permission',
                subtitle: '切换权限预设（沙箱模式与审查）',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickPermission();
                },
              ),
              _SheetTile(
                icon: Icons.tune,
                title: '模型',
                keyword: 'model',
                subtitle: '选择本会话使用的模型',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickModel();
                },
              ),
              _SheetTile(
                icon: Icons.download_outlined,
                title: '下载日志',
                keyword: 'export',
                subtitle: '将当前会话内容导出为 ZIP',
                onTap: () => stub('发送后在会话中导出'),
              ),
              const SizedBox(height: DshSpace.x2),
            ],
          ),
        );
      },
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

  Future<void> _send(ServerProfile? server) async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    final api = ref.read(dshApiProvider);
    if (api == null) {
      showDshSnack(context, '请先绑定服务端');
      return;
    }
    final cwd = _effectiveWorkspace(ref.read(workspacesProvider));
    setState(() => _sending = true);
    try {
      final sessionId = await api.createSession(cwd: cwd);
      // 发送前落本页延迟生效的选择：模型 / 权限 / 计划模式。
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
      await api.prompt(sessionId: sessionId, requestId: newRpcId(), text: text);
      if (!mounted) return;
      ref.invalidate(tasksProvider);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionPage(
            summary: SessionSummary(
              sessionId: sessionId,
              title: text,
              updatedAt: DateTime.now(),
              running: true,
              blank: false,
              cwd: cwd,
            ),
          ),
        ),
      );
    } on AppException catch (e) {
      if (mounted) showDshError(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// 工作区选择结果；[path] 为 null 表示显式选择默认工作区，
/// [created] 为 true 表示需要先向宿主注册该目录。
class _WorkspaceChoice {
  final String? path;
  final bool created;

  const _WorkspaceChoice(this.path, {this.created = false});
}

/// 「+」面板条目：图标 + 标题 + 灰色英文关键词（+ 可选描述）。
class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String keyword;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SheetTile({
    required this.icon,
    required this.title,
    required this.keyword,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return ListTile(
      leading: Icon(icon, size: 20, color: p.foreground),
      title: Row(
        children: [
          Text(
            title,
            style: context.dshText.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: DshSpace.x2),
          Text(
            keyword,
            style: context.dshText.bodySmall?.copyWith(
              fontSize: 13,
              color: p.tertiaryText,
            ),
          ),
        ],
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.dshText.bodySmall?.copyWith(
                fontSize: 13,
                color: p.secondaryText,
              ),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
