import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/models/dsh_session.dart';
import '../../core/models/workspace_file.dart';
import '../../widgets/common.dart';
import '../servers/servers_providers.dart';
import 'widgets/detail_header.dart';
import 'workspace_file_preview_page.dart';

/// 工作区文件页：逐级浏览 DSH 服务端当前项目下的文件与文件夹。
///
/// 每层目录是一个新路由，返回键天然回到上一层；[path] 为工作区相对路径，
/// 根目录为空串（由宿主按会话 header 的 cwd 解析）。
class WorkspaceFilesPage extends ConsumerStatefulWidget {
  final String sessionId;
  final String? cwd;
  final String path;

  const WorkspaceFilesPage({
    super.key,
    required this.sessionId,
    this.cwd,
    this.path = '',
  });

  @override
  ConsumerState<WorkspaceFilesPage> createState() => _WorkspaceFilesPageState();
}

class _WorkspaceFilesPageState extends ConsumerState<WorkspaceFilesPage> {
  WorkspaceDirectoryListing? _listing;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(dshApiProvider);
      if (api == null) {
        throw const ServerException('服务端未连接', code: 'not_ready');
      }
      final listing = await api.listWorkspaceDirectory(
        sessionId: widget.sessionId,
        // 宿主拒绝空路径：根目录用 `.`，返回的 path 仍是空串（工作区相对）。
        path: widget.path.isEmpty ? '.' : widget.path,
      );
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _loading = false;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ServerException(_friendlyMessage(e), code: e.code);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String get _title {
    final segments = widget.path.split('/').where((s) => s.isNotEmpty);
    if (segments.isNotEmpty) return segments.last;
    return folderNameOf(widget.cwd) ?? '工作区文件';
  }

  String get _subtitle {
    final cwd = widget.cwd;
    if (widget.path.isEmpty) {
      return cwd == null || cwd.isEmpty ? '工作区根目录' : cwd;
    }
    return cwd == null || cwd.isEmpty ? widget.path : '$cwd/${widget.path}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Scaffold(
      backgroundColor: p.canvas,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: _title,
              subtitle: _subtitle,
              onBack: () => Navigator.of(context).pop(),
              action: CircleButton(
                icon: Icons.refresh_rounded,
                tooltip: '刷新',
                onTap: _loading ? null : _load,
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _listing == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) return ErrorView(error: error, onRetry: _load);
    final listing = _listing;
    if (listing == null) return const SizedBox.shrink();
    final entries = _sorted(listing.entries);
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open_outlined,
        message: '这个文件夹是空的',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: DshSpace.x6),
      itemCount: entries.length + (listing.truncated ? 1 : 0),
      separatorBuilder: (_, _) =>
          const Divider(indent: DshSpace.x5, endIndent: DshSpace.x5),
      itemBuilder: (context, index) {
        if (index >= entries.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.x5,
              DshSpace.x3,
              DshSpace.x5,
              0,
            ),
            child: Text(
              '条目过多，仅显示前 ${entries.length} 项',
              style: context.dshText.bodySmall,
            ),
          );
        }
        return _entryRow(entries[index]);
      },
    );
  }

  Widget _entryRow(WorkspaceEntry entry) {
    final p = context.dsh;
    final directory = entry.isDirectory;
    final image =
        !directory &&
        entry.type == WorkspaceEntryType.file &&
        isPreviewableImage(entry.name);
    final icon = switch (entry.type) {
      WorkspaceEntryType.directory => Icons.folder_outlined,
      WorkspaceEntryType.file =>
        image ? Icons.image_outlined : Icons.description_outlined,
      WorkspaceEntryType.other => Icons.help_outline_rounded,
    };
    final size = entry.size;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: DshSpace.x5),
      leading: Icon(
        icon,
        size: 22,
        color: directory ? p.midText : p.secondaryText,
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: size == null ? null : Text(_formatSize(size)),
      trailing: entry.type == WorkspaceEntryType.other
          ? null
          : Icon(Icons.chevron_right_rounded, size: 20, color: p.tertiaryText),
      onTap: switch (entry.type) {
        WorkspaceEntryType.directory => () => _openDirectory(entry),
        WorkspaceEntryType.file => () => _openFile(entry),
        WorkspaceEntryType.other => null,
      },
    );
  }

  void _openDirectory(WorkspaceEntry entry) {
    final path = widget.path.isEmpty
        ? entry.name
        : '${widget.path}/${entry.name}';
    Navigator.of(context).push(
      dshSlideRoute<void>(
        WorkspaceFilesPage(
          sessionId: widget.sessionId,
          cwd: widget.cwd,
          path: path,
        ),
      ),
    );
  }

  void _openFile(WorkspaceEntry entry) {
    final path = widget.path.isEmpty
        ? entry.name
        : '${widget.path}/${entry.name}';
    Navigator.of(context).push(
      dshSlideRoute<void>(
        WorkspaceFilePreviewPage(
          sessionId: widget.sessionId,
          cwd: widget.cwd,
          path: path,
          name: entry.name,
        ),
      ),
    );
  }

  /// 文件夹优先，其余按名称不区分大小写排序。
  List<WorkspaceEntry> _sorted(List<WorkspaceEntry> entries) {
    int rank(WorkspaceEntry entry) => switch (entry.type) {
      WorkspaceEntryType.directory => 0,
      WorkspaceEntryType.file => 1,
      WorkspaceEntryType.other => 2,
    };
    final sorted = [...entries];
    sorted.sort((a, b) {
      final byType = rank(a).compareTo(rank(b));
      if (byType != 0) return byType;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
  }

  String _friendlyMessage(AppException error) => switch (error.code) {
    'workspace-file/not-found' => '目录不存在',
    'workspace-file/outside-workspace' => '目录不在当前工作区内',
    'workspace-file/not-directory' => '该路径不是文件夹',
    _ => error.userMessage,
  };
}
