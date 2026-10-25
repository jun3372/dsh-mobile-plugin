import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/models/dsh_session.dart';
import '../../core/mux/workspace_hub.dart';
import '../../widgets/common.dart';
import '../servers/servers_page.dart';
import '../servers/servers_providers.dart';
import '../sessions/session_page.dart';
import 'archived_page.dart';
import 'new_task_page.dart';
import 'tasks_providers.dart';
import 'widgets/session_context_menu.dart';
import 'widgets/session_row_tile.dart';

/// 首页任务列表（仿 Qoder CN：大标题+服务器切换、筛选 chips、分组列表、⋯ popover、FAB）。
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final _collapsedFolders = <String>{};
  String? _selectedFolder;

  @override
  void dispose() {
    // 浮层挂在 root navigator 上，页面销毁时若不收起会残留。
    SessionContextMenu.dismissIfOpen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(currentServerProvider);
    final tasks = ref.watch(tasksProvider);
    final prefs = ref.watch(taskPrefsProvider);
    final connection = ref.watch(connectionCheckProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(server?.name ?? 'DSH', connection),
            _buildFilterChips(tasks, prefs),
            if (connection.value == false) _buildOfflineBanner(),
            Expanded(child: _buildList(tasks, prefs)),
          ],
        ),
      ),
      floatingActionButton: _NewTaskFab(onTap: _openNewTask),
    );
  }

  Widget _buildHeader(String serverName, AsyncValue<bool> connection) {
    return Padding(
      padding: DshHeaderMetrics.padding,
      child: Row(
        children: [
          // 与新建会话页头部一致：使用 DSH 鲸鱼 logo（透明底）替代占位「D」。
          Image.asset(
            'assets/icon/logo.png',
            width: DshHeaderMetrics.logo,
            height: DshHeaderMetrics.logo,
            fit: BoxFit.contain,
            semanticLabel: 'DSH',
          ),
          const SizedBox(width: DshSpace.x2),
          Expanded(
            child: GestureDetector(
              onTap: _showServerSwitcher,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      serverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.dshText.displaySmall?.copyWith(
                        fontSize: DshHeaderMetrics.title,
                      ),
                    ),
                  ),
                  const SizedBox(width: DshSpace.x1),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: DshHeaderMetrics.dropdownIcon,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: DshSpace.x2),
          // Builder 提供锚点上下文，popover 贴 ⋯ 按钮右下角弹出。
          Builder(
            builder: (buttonContext) => CircleButton(
              icon: Icons.more_horiz,
              tooltip: '更多',
              onTap: () => _showMoreMenu(buttonContext),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(
    AsyncValue<List<SessionSummary>> tasks,
    TaskPrefs prefs,
  ) {
    final folders = <String>{};
    if (tasks.value != null) {
      for (final session in visibleSessions(
        tasks.value!,
        archivedIds: ref.watch(archivedIdsProvider),
        pinnedIds: ref.watch(pinnedIdsProvider),
      )) {
        final name = session.folderName;
        if (name != null) folders.add(name);
      }
    }
    // 容器高 46 = chip 视觉 34 + 上下 4 触控缓冲 + 4 外边距。
    return SizedBox(
      height: DshChip.rowHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DshSpace.x5,
          vertical: DshSpace.x1,
        ),
        children: [
          _FilterChip(
            label: '全部',
            selected: _selectedFolder == null,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedFolder = null);
            },
          ),
          for (final folder in folders)
            _FilterChip(
              label: folder,
              icon: Icons.folder_outlined,
              selected: _selectedFolder == folder,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(
                  () => _selectedFolder = _selectedFolder == folder
                      ? null
                      : folder,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    final p = context.dsh;
    return Material(
      color: p.runningYellow.withValues(alpha: 0.14),
      child: InkWell(
        onTap: () => ref.invalidate(connectionCheckProvider),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DshSpace.x5,
            vertical: DshSpace.x3,
          ),
          child: Row(
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: DshIcon.chip,
                color: p.runningYellow,
              ),
              const SizedBox(width: DshSpace.x2),
              Expanded(
                child: Text(
                  '服务端连接不可用，点按重试',
                  style: context.dshText.bodySmall?.copyWith(
                    fontSize: 13,
                    color: p.runningYellow,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(AsyncValue<List<SessionSummary>> tasks, TaskPrefs prefs) {
    return NotificationListener<ScrollStartNotification>(
      // 列表一开始滚动，锚定在行上的上下文菜单就失去意义，直接收起。
      onNotification: (_) {
        SessionContextMenu.dismissIfOpen();
        return false;
      },
      child: tasks.when(
        skipLoadingOnReload: true,
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () {
            ref.invalidate(connectionCheckProvider);
            ref.invalidate(tasksProvider);
          },
        ),
        data: (sessions) {
          final archived = ref.watch(archivedIdsProvider);
          final pinned = ref.watch(pinnedIdsProvider);
          final workspaces = ref.watch(workspacesProvider);
          final visible = filterSessionsByFolder(
            visibleSessions(sessions, archivedIds: archived, pinnedIds: pinned),
            _selectedFolder,
          );
          final groups = groupTasks(visible, prefs, workspaces: workspaces);
          final rows = <Object>[
            for (final group in _visibleGroups(groups)) ...[
              group,
              ...group.sessions,
            ],
          ];
          if (rows.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(
                    height: 320,
                    child: EmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      message: '暂无任务',
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                return row is TaskGroup
                    ? _buildGroupRow(row)
                    : _buildTaskRow(row as SessionSummary);
              },
            ),
          );
        },
      ),
    );
  }

  /// 下拉刷新：重查连接与任务列表。
  Future<void> _refresh() async {
    ref.invalidate(connectionCheckProvider);
    ref.invalidate(tasksProvider);
    try {
      await ref.read(tasksProvider.future);
    } catch (_) {
      // 错误由列表状态展示，这里只负责结束下拉动画。
    }
  }

  /// 应用折叠态后的分组视图。
  List<TaskGroup> _visibleGroups(List<TaskGroup> groups) {
    return [
      for (final group in groups)
        TaskGroup(
          group.title,
          _collapsedFolders.contains(group.title)
              ? const <SessionSummary>[]
              : group.sessions,
        ),
    ];
  }

  Widget _buildGroupRow(TaskGroup group) {
    final p = context.dsh;
    final expanded = !_collapsedFolders.contains(group.title);
    return InkWell(
      onTap: () => setState(() {
        expanded
            ? _collapsedFolders.add(group.title)
            : _collapsedFolders.remove(group.title);
      }),
      onLongPress: () => _showWorkspaceActions(group.title),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DshSpace.x6,
          DshSpace.x4,
          DshSpace.x5,
          DshSpace.x1,
        ),
        child: Row(
          children: [
            // 参考稿分组标题恒为次级灰（实测 #9D9D9D），展开/折叠只改箭头方向。
            Icon(
              Icons.folder_outlined,
              size: DshIcon.chip,
              color: p.secondaryText,
            ),
            const SizedBox(width: DshSpace.x2),
            Expanded(
              child: Text(
                group.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.dshText.bodySmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.secondaryText,
                ),
              ),
            ),

            // chevron 右向为折叠，旋转 90° 表示展开。
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: DshMotion.fast,
              curve: DshMotion.curve,
              child: Icon(
                Icons.chevron_right,
                size: DshIcon.tool,
                color: p.tertiaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 长按工作区分组行：重命名 / 上移 / 在电脑上打开 / 删除。
  void _showWorkspaceActions(String folder) {
    final workspaces = ref.read(workspacesProvider.notifier);
    final row = workspaces.findByFolder(folder);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: row == null
            ? Padding(
                padding: const EdgeInsets.all(DshSpace.x5),
                child: Text(
                  '工作区信息尚未同步，请稍后重试',
                  style: context.dshText.bodyMedium?.copyWith(
                    color: context.dsh.secondaryText,
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DshSheetTitle(
                    title: row.title.isEmpty ? folder : row.title,
                    subtitle: row.path,
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.drive_file_rename_outline,
                      size: DshIcon.nav,
                    ),
                    title: const Text('重命名'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showWorkspaceRenameDialog(row);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.arrow_upward_rounded,
                      size: DshIcon.nav,
                    ),
                    title: const Text('上移'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _moveWorkspaceUp(row);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.computer_outlined,
                      size: DshIcon.nav,
                    ),
                    title: const Text('在电脑上打开'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openOnDesktop(row.path);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.folder_delete_outlined,
                      size: DshIcon.nav,
                      color: context.dsh.dangerRed,
                    ),
                    title: Text(
                      '删除工作区',
                      style: context.dshText.bodyLarge?.copyWith(
                        color: context.dsh.dangerRed,
                      ),
                    ),
                    subtitle: const Text('只移除注册，不删除电脑上的文件和会话'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmDeleteWorkspace(row);
                    },
                  ),
                  const SizedBox(height: DshSpace.x2),
                ],
              ),
      ),
    );
  }

  void _showWorkspaceRenameDialog(WorkspaceRow row) {
    final controller = TextEditingController(text: row.title);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名工作区'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '工作区名称'),
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
                await ref
                    .read(workspacesProvider.notifier)
                    .rename(row.workspaceId, title);
              } on AppException catch (e) {
                if (mounted) showDshError(context, e.userMessage);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _moveWorkspaceUp(WorkspaceRow row) async {
    final before = ref
        .read(workspacesProvider.notifier)
        .workspaceBefore(row.workspaceId);
    if (before == null) {
      showDshError(context, '已经在最前面了');
      return;
    }
    try {
      await ref
          .read(workspacesProvider.notifier)
          .moveBefore(row.workspaceId, before);
    } on AppException catch (e) {
      if (mounted) showDshError(context, e.userMessage);
    }
  }

  Future<void> _openOnDesktop(String path) async {
    final api = ref.read(dshApiProvider);
    if (api == null) return;
    try {
      if (!await api.canOpenWorkspacePath()) {
        if (!mounted) return;
        showDshError(context, '该 DSH 部署不支持远程打开路径');
        return;
      }
      await api.openWorkspacePath(path, reveal: true);
      if (mounted) showDshSnack(context, '已在电脑上打开');
    } on AppException catch (e) {
      if (mounted) showDshError(context, e.userMessage);
    }
  }

  void _confirmDeleteWorkspace(WorkspaceRow row) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除工作区'),
        content: Text(
          '确定删除「${row.title.isEmpty ? folderNameOf(row.path) ?? row.path : row.title}」吗？'
          '电脑上的文件和其中的会话都会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.dsh.dangerRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await ref
                    .read(workspacesProvider.notifier)
                    .delete(row.workspaceId);
                if (_selectedFolder != null &&
                    folderNameOf(row.path) == _selectedFolder) {
                  setState(() => _selectedFolder = null);
                }
              } on AppException catch (e) {
                if (mounted) showDshError(context, e.userMessage);
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskRow(SessionSummary session) {
    final pinned = ref.watch(pinnedIdsProvider).contains(session.sessionId);
    // Builder 提供行的锚点上下文，长按时据此取全局矩形。
    return Builder(
      builder: (rowContext) => InkWell(
        onTap: () => _openSession(session),
        onLongPress: () => _openRowMenu(rowContext, session),
        child: SessionRowTile(session: session, pinned: pinned),
      ),
    );
  }

  /// 长按会话行：整页高斯模糊，该行保持清晰并在其下方浮出操作菜单。
  Future<void> _openRowMenu(
    BuildContext rowContext,
    SessionSummary session,
  ) async {
    final box = rowContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    HapticFeedback.selectionClick();
    final pinned = ref.read(pinnedIdsProvider).contains(session.sessionId);
    await showSessionContextMenu(
      rowContext,
      anchorRect: box.localToGlobal(Offset.zero) & box.size,
      preview: SessionRowTile(session: session, pinned: pinned),
      actions: _sessionActions(session, pinned),
    );
  }

  /// 菜单动作一律只用宿主已有的能力：置顶（本地偏好）、重命名、工作区内上移、归档。
  List<SessionMenuAction> _sessionActions(SessionSummary session, bool pinned) {
    return [
      SessionMenuAction(
        label: pinned ? '取消置顶' : '置顶',
        icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
        onTap: () async {
          try {
            final notifier = ref.read(pinnedIdsProvider.notifier);
            pinned
                ? await notifier.unpin(session.sessionId)
                : await notifier.pin(session.sessionId);
          } on AppException catch (e) {
            if (mounted) showDshError(context, e.userMessage);
          }
        },
      ),
      SessionMenuAction(
        label: '重命名',
        icon: Icons.drive_file_rename_outline,
        onTap: () => _showRenameDialog(session),
      ),
      if (_sessionMoveUpTarget(session) case final target?)
        SessionMenuAction(
          label: '在工作区中上移',
          icon: Icons.arrow_upward_rounded,
          onTap: () async {
            try {
              await ref
                  .read(workspacesProvider.notifier)
                  .moveSessionBefore(
                    workspaceId: target.workspaceId,
                    sessionId: session.sessionId,
                    beforeSessionId: target.beforeSessionId,
                  );
            } on AppException catch (e) {
              if (mounted) showDshError(context, e.userMessage);
            }
          },
        ),
      SessionMenuAction(
        label: '归档',
        icon: Icons.inventory_2_outlined,
        onTap: () async {
          try {
            await ref
                .read(archivedIdsProvider.notifier)
                .archive(session.sessionId);
            ref.invalidate(tasksProvider);
          } on AppException catch (e) {
            if (mounted) showDshError(context, e.userMessage);
          }
        },
      ),
    ];
  }

  /// 会话不在工作区首位时返回上移目标，否则 null（菜单不展示该项）。
  ({String workspaceId, String beforeSessionId})? _sessionMoveUpTarget(
    SessionSummary session,
  ) {
    final workspaces = ref.read(workspacesProvider);
    final row = workspaces
        .where((item) => item.sessionIds.contains(session.sessionId))
        .firstOrNull;
    if (row == null) return null;
    final before = ref
        .read(workspacesProvider.notifier)
        .sessionBefore(row.workspaceId, session.sessionId);
    if (before == null) return null;
    return (workspaceId: row.workspaceId, beforeSessionId: before);
  }

  void _showRenameDialog(SessionSummary session) {
    final controller = TextEditingController(text: session.title ?? '');
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
                await ref
                    .read(dshApiProvider)
                    ?.rename(session.sessionId, title);
                ref.invalidate(tasksProvider);
              } on AppException catch (e) {
                if (mounted) showDshError(context, e.userMessage);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _openNewTask() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const NewTaskPage()));
  }

  void _openSession(SessionSummary session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SessionPage(summary: session)),
    );
  }

  void _showServerSwitcher() {
    final currentId = ref.read(currentServerIdProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final list = sheetRef.watch(serversProvider);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DshSheetTitle(title: '切换服务端'),
                for (final server in list)
                  ListTile(
                    leading: Icon(
                      server.mode == 'lan' ? Icons.wifi : Icons.public,
                      size: DshIcon.nav,
                    ),
                    title: Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: server.id == currentId
                        ? const Icon(Icons.check, size: DshIcon.action)
                        : null,
                    onTap: server.id == currentId
                        ? null
                        : () {
                            sheetRef
                                .read(currentServerIdProvider.notifier)
                                .setCurrent(server.id);
                            sheetRef
                                .read(serversProvider.notifier)
                                .touch(server.id);
                            Navigator.of(sheetContext).pop();
                          },
                  ),
                const Divider(indent: DshSpace.x4, endIndent: DshSpace.x4),
                ListTile(
                  leading: const Icon(Icons.tune, size: DshIcon.nav),
                  title: const Text('服务端管理'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ServersPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// ⋯ 菜单：右上 popover（SPEC §4 结构规则 3）。
  void _showMoreMenu(BuildContext anchorContext) {
    final prefs = ref.read(taskPrefsProvider);
    showDshPopoverMenu(
      anchorContext,
      sections: [
        DshPopoverSection(
          caption: '分组方式',
          options: [
            for (final mode in TaskGroupMode.values)
              DshPopoverOption(
                label: switch (mode) {
                  TaskGroupMode.date => '日期',
                  TaskGroupMode.workspace => '工作区',
                  TaskGroupMode.status => '状态',
                },
                selected: prefs.groupMode == mode,
                onTap: () =>
                    ref.read(taskPrefsProvider.notifier).setGroupMode(mode),
              ),
          ],
        ),
        DshPopoverSection(
          caption: '筛选',
          options: [
            DshPopoverOption(
              label: '仅展示进行中的任务',
              selected: prefs.onlyRunning,
              onTap: () =>
                  ref.read(taskPrefsProvider.notifier).toggleOnlyRunning(),
            ),
          ],
        ),
        DshPopoverSection(
          options: [
            DshPopoverOption(
              label: '已归档',
              icon: Icons.inventory_2_outlined,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ArchivedPage()),
              ),
            ),
            DshPopoverOption(
              label: '服务端管理',
              icon: Icons.tune,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ServersPage()),
              ),
            ),
            DshPopoverOption(
              label: '设置',
              icon: Icons.settings_outlined,
              onTap: () => showDshSnack(context, '设置项开发中'),
            ),
          ],
        ),
      ],
    );
  }
}

/// FAB（SPEC §3：64 直径、图标 26、轻触感）。
class _NewTaskFab extends StatelessWidget {
  final VoidCallback onTap;

  const _NewTaskFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Tooltip(
      message: '新建任务',
      child: Semantics(
        button: true,
        label: '新建任务',
        child: Material(
          color: p.foreground,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: p.shadow,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: SizedBox(
              width: DshButton.fab,
              height: DshButton.fab,
              child: Icon(
                Icons.add,
                size: DshButton.fabIcon,
                color: p.onForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    // 视觉高 34 + 上下 4 触控缓冲 = 42 触控目标；右侧间距分隔相邻工作区。
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, DshSpace.x2, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DshRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: DshMotion.fast,
            curve: DshMotion.curve,
            padding: const EdgeInsets.symmetric(
              horizontal: DshSpace.x4,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: selected ? p.foreground : p.chipGray,
              borderRadius: BorderRadius.circular(DshRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: DshIcon.chip,
                    color: selected ? p.onForeground : p.secondaryText,
                  ),
                  const SizedBox(width: DshSpace.x1 + 2),
                ],
                Text(
                  label,
                  style: context.dshText.bodySmall?.copyWith(
                    fontSize: 14,
                    color: selected ? p.onForeground : p.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
