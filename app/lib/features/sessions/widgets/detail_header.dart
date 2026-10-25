import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../widgets/common.dart';

/// 二级页面（工作区文件 / 文件预览）的统一头部：
/// 左侧圆形返回钮，中间单行标题 + 图标副标题，右侧可选动作。
class DetailHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData subtitleIcon;
  final VoidCallback onBack;
  final Widget? action;

  const DetailHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleIcon = Icons.folder_outlined,
    required this.onBack,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      // 与首页/会话页头部统一：左 20 对齐页边距，上下 8、右 12。
      padding: DshHeaderMetrics.padding,
      child: Row(
        children: [
          CircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回',
            onTap: onBack,
          ),
          const SizedBox(width: DshSpace.x4),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.titleLarge?.copyWith(
                    fontSize: DshHeaderMetrics.barTitle,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(subtitleIcon, size: 13, color: p.secondaryText),
                      const SizedBox(width: DshSpace.x1),
                      Flexible(
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.dshText.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: DshSpace.x2), action!],
        ],
      ),
    );
  }
}
