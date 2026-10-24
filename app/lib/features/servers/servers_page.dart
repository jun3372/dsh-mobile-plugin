import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';
import 'scan_page.dart';
import 'servers_providers.dart';

/// 服务端管理：列表 / 点按切换 / 滑动删除 / 添加。
class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.dsh;
    final servers = ref.watch(serversProvider);
    final currentId = ref.watch(currentServerIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('服务端管理')),
      body: servers.isEmpty
          ? const EmptyState(icon: Icons.dns_outlined, message: '尚未绑定任何服务端')
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: DshSpace.x2),
              itemCount: servers.length,
              separatorBuilder: (_, _) =>
                  const Divider(indent: DshSpace.x4, endIndent: DshSpace.x4),
              itemBuilder: (context, index) {
                final server = servers[index];
                final isCurrent = server.id == currentId;
                return Dismissible(
                  key: ValueKey(server.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: p.dangerRed,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: DshSpace.x6),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                  ),
                  confirmDismiss: (_) => _confirmUnbind(context, server.name),
                  onDismissed: (_) =>
                      ref.read(serversProvider.notifier).remove(server.id),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: DshSpace.x5,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: p.canvas,
                        borderRadius: BorderRadius.circular(DshRadius.leading),
                      ),
                      child: Icon(
                        server.mode == 'lan' ? Icons.wifi : Icons.public,
                        size: DshIcon.action,
                        color: p.foreground,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            server.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.dshText.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DshSpace.x2,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: p.foreground,
                              borderRadius: BorderRadius.circular(
                                DshRadius.pill,
                              ),
                            ),
                            child: Text(
                              '当前',
                              style: context.dshText.labelSmall?.copyWith(
                                color: p.onForeground,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${server.origin.host}:${server.origin.port} · ${server.mode == 'lan' ? '局域网' : '公网'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isCurrent
                        ? Icon(Icons.check_circle, color: p.foreground)
                        : Icon(Icons.chevron_right, color: p.tertiaryText),
                    onTap: isCurrent
                        ? null
                        : () {
                            ref
                                .read(currentServerIdProvider.notifier)
                                .setCurrent(server.id);
                            ref.read(serversProvider.notifier).touch(server.id);
                            Navigator.of(context).pop();
                          },
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DshSpace.x5,
            DshSpace.x2,
            DshSpace.x5,
            DshSpace.x4,
          ),
          child: FilledButton.icon(
            icon: const Icon(
              Icons.qr_code_scanner_rounded,
              size: DshIcon.action,
            ),
            label: const Text('扫码添加服务端'),
            onPressed: () =>
                Navigator.of(context).push(dshRoute(const ScanPage())),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmUnbind(BuildContext context, String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解除绑定'),
        content: Text('确定要解绑「$name」吗？绑定记录将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '解绑',
              style: TextStyle(color: dialogContext.dsh.dangerRed),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
