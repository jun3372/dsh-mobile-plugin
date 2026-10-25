/// 触发菜单视图：分组候选浮在输入卡上方，点行选定。
///
/// 视觉沿用 Web 的分组标题 + 图标 + 标题 + 说明右排结构；触摸设备上
/// 移除/下钻按钮常显（Web 的 hover 语义在手机端不成立）。
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'trigger_menu_controller.dart';
import 'trigger_sources.dart';

class TriggerMenuView extends StatelessWidget {
  final TriggerMenuController controller;

  const TriggerMenuView({super.key, required this.controller});

  static const _maxHeight = 264.0;

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isOpen) return const SizedBox.shrink();
        final groups = controller.groups;
        if (groups.isEmpty) {
          if (!controller.loading) return const SizedBox.shrink();
          return _Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: p.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '载入候选…',
                    style: context.dshText.bodySmall?.copyWith(
                      color: p.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        var flatIndex = -1;
        return _Card(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                    child: Text(
                      group.title,
                      style: context.dshText.labelSmall?.copyWith(
                        color: p.tertiaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final item in group.items)
                    Builder(
                      builder: (context) {
                        flatIndex++;
                        final highlighted = flatIndex == controller.highlight;
                        return _TriggerRow(
                          item: item,
                          highlighted: highlighted,
                          onTap: () => controller.pick(item),
                          onHover: () => controller.setHighlight(flatIndex),
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(DshRadius.menu),
          border: Border.all(color: p.divider),
          boxShadow: [
            BoxShadow(
              color: p.shadow,
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class _TriggerRow extends StatelessWidget {
  final TriggerItem item;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _TriggerRow({
    required this.item,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: highlighted ? p.chipGray : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.drill
                    ? Icons.folder_outlined
                    : (item.insertion == null
                          ? Icons.tune
                          : Icons.bolt_outlined),
                size: 16,
                color: p.secondaryText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.dshText.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.subtitle case final subtitle?) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.dshText.bodySmall?.copyWith(
                          color: p.secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.drill)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: p.tertiaryText,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
