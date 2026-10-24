import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/queued_message.dart';
import '../../../widgets/common.dart';

/// 输入框上方的待处理消息队列（宿主 inbox 投影）。
class QueueDock extends StatelessWidget {
  final List<QueuedMessage> queue;
  final Future<void> Function(QueuedMessage item, QueueItemAction action)?
  onAction;

  const QueueDock({super.key, required this.queue, this.onAction});

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) return const SizedBox.shrink();
    final p = context.dsh;
    final actionable = onAction != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule_send_outlined,
                size: 14,
                color: p.secondaryText,
              ),
              const SizedBox(width: 6),
              Text(
                '待处理 ${queue.length}',
                style: context.dshText.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: queue.length,
              itemBuilder: (context, index) {
                final item = queue[index];
                final nextStep = item.target == 'next-step';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.dotGray,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: actionable && !item.isLocal
                              ? () => onAction!(item, QueueItemAction.edit)
                              : null,
                          onLongPress: actionable && !item.isLocal
                              ? () => _showItemActions(context, item)
                              : null,
                          child: Text(
                            item.text.isEmpty
                                ? (item.imageCount > 0
                                      ? '图片 × ${item.imageCount}'
                                      : '空消息')
                                : item.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.dshText.bodySmall?.copyWith(
                              fontSize: 13,
                              height: 1.35,
                              color: item.isLocal
                                  ? p.tertiaryText
                                  : p.foreground,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.isLocal ? '发送中…' : (nextStep ? '下一步' : '下一轮'),
                        style: context.dshText.labelSmall?.copyWith(
                          color: p.tertiaryText,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showItemActions(BuildContext context, QueuedMessage item) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DshSheetTitle(title: item.text.isEmpty ? '图片消息' : item.text),
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 22),
              title: const Text('编辑'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onAction?.call(item, QueueItemAction.edit);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bolt_rounded, size: 22),
              title: const Text('立即发送'),
              subtitle: const Text('不等当前步骤结束，插队执行'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onAction?.call(item, QueueItemAction.steer);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, size: 22),
              title: const Text('撤回'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onAction?.call(item, QueueItemAction.remove);
              },
            ),
            const SizedBox(height: DshSpace.x2),
          ],
        ),
      ),
    );
  }
}

/// 队列项操作。
enum QueueItemAction { edit, steer, remove }
