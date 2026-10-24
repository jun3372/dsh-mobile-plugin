import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/models/dsh_session.dart';
import '../../widgets/common.dart';
import '../sessions/session_page.dart';
import 'tasks_providers.dart';

/// 已归档会话列表（id 集合来自归档操作的宿主返回，本地持久化）。
class ArchivedPage extends ConsumerWidget {
  const ArchivedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedIds = ref.watch(archivedIdsProvider);
    final sessions = (ref.watch(tasksProvider).value ?? const [])
        .where((s) => archivedIds.contains(s.sessionId))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('已归档')),
      body: sessions.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              message: '暂无归档会话',
            )
          : ListView.separated(
              itemCount: sessions.length,
              separatorBuilder: (_, _) =>
                  const Divider(indent: DshSpace.x4, endIndent: DshSpace.x4),
              itemBuilder: (context, index) =>
                  _buildRow(context, ref, sessions[index]),
            ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    WidgetRef ref,
    SessionSummary session,
  ) {
    final p = context.dsh;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: DshSpace.x5),
      leading: Icon(
        Icons.inventory_2_outlined,
        size: 20,
        color: p.secondaryText,
      ),
      title: Text(
        session.title ?? (session.blank ? '新任务' : '未命名任务'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: session.folderName == null
          ? null
          : Text(
              session.folderName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: TextButton(
        onPressed: () => _unarchive(context, ref, session.sessionId),
        child: const Text('取消归档'),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SessionPage(summary: session)),
      ),
    );
  }

  Future<void> _unarchive(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
  ) async {
    try {
      await ref.read(archivedIdsProvider.notifier).unarchive(sessionId);
    } on AppException catch (e) {
      if (!context.mounted) return;
      showDshError(context, e.userMessage);
    }
  }
}
