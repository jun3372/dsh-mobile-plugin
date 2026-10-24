import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/dsh_session.dart';
import '../../../widgets/common.dart';

/// 会话行纯展示体（列表行与长按上下文菜单的清晰副本共用，保证两处像素一致）。
///
/// 手势（tap / long press）由调用方包裹，这里只负责 56 高的行内容。
class SessionRowTile extends StatelessWidget {
  final SessionSummary session;
  final bool pinned;

  const SessionRowTile({
    super.key,
    required this.session,
    required this.pinned,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final title = session.title ?? (session.blank ? '新任务' : '未命名任务');
    // 行节奏 56（SPEC §3 实测 168px/3x）。
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DshSpace.x6),
        child: Row(
          children: [
            StatusDot(running: session.running),
            const SizedBox(width: DshSpace.x4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.dshText.bodyLarge,
              ),
            ),
            if (pinned)
              Icon(
                Icons.push_pin_rounded,
                size: DshIcon.inline,
                color: p.secondaryText,
              ),
          ],
        ),
      ),
    );
  }
}
