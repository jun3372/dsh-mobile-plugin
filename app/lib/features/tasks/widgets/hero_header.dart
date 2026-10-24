import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// 新建会话页头部：logo 占位 +「探索未至之境」+「预览版」徽章。
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DshSpace.x5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icon/logo.png',
            height: 32,
            fit: BoxFit.contain,
            semanticLabel: 'DSH',
          ),
          const SizedBox(width: DshSpace.x2),
          Flexible(
            child: Text(
              '探索未至之境',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.dshText.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: p.foreground,
              ),
            ),
          ),
          const SizedBox(width: DshSpace.x2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DshSpace.x2,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: p.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DshRadius.pill),
            ),
            child: Text(
              '预览版',
              style: context.dshText.labelSmall?.copyWith(color: p.accentBlue),
            ),
          ),
        ],
      ),
    );
  }
}
