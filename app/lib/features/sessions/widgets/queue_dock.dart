import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/queued_message.dart';

/// 输入框上方的待处理消息队列（宿主 inbox 投影）。
class QueueDock extends StatelessWidget {
  final List<QueuedMessage> queue;
  final Future<void> Function(QueuedMessage item, QueueItemAction action)?
  onAction;

  /// 会话是否正在运行（宿主仅接受对运行中会话的 next-turn 消息插话）。
  final bool canSteer;

  const QueueDock({
    super.key,
    required this.queue,
    required this.canSteer,
    this.onAction,
  });

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
                            color: item.isLocal ? p.tertiaryText : p.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 右侧两个图标操作：撤回编辑 / 立即发送（插话）。
                      // 宿主仅接受运行中会话的 next-turn 消息插话，不满足时不显示。
                      if (actionable && !item.isLocal) ...[
                        _QueueItemIcon(
                          icon: Icons.undo_outlined,
                          tooltip: '撤回编辑',
                          color: p.secondaryText,
                          onTap: () => onAction!(item, QueueItemAction.recall),
                        ),
                        if (canSteer && item.target != 'next-step')
                          _QueueItemIcon(
                            icon: Icons.bolt_rounded,
                            tooltip: '立即发送',
                            color: p.accentBlue,
                            onTap: () => onAction!(item, QueueItemAction.steer),
                          ),
                      ],
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
}

/// 队列条目右侧的操作图标（撤回编辑 / 立即发送）。
class _QueueItemIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _QueueItemIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(DshRadius.thumb),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: DshIcon.chip, color: color),
        ),
      ),
    );
  }
}

/// 队列项操作：撤回编辑（移出队列回填输入框）/ 立即发送（插队执行）。
enum QueueItemAction { recall, steer }
