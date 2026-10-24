import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/transcript_node.dart';
import '../session_providers.dart';

/// 会话页底部状态栏：轮数 · 工具次数 · token 占用（对齐 Web 端会话详情页）。
/// 数据不足时整行隐藏，不显示占位。
class SessionStatusBar extends StatelessWidget {
  final SessionViewState view;

  const SessionStatusBar({super.key, required this.view});

  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      final k = tokens / 1000;
      return k >= 100 ? '${k.round()}K' : '${k.toStringAsFixed(1)}K';
    }
    return '$tokens';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final toolCount = view.nodes
        .where((node) => node.kind == TranscriptKind.tool)
        .length;
    final tokens = view.contextPressure?.usedTokens;
    final ratio = view.contextPressure?.ratio;
    final hasTurn = view.turns > 0;
    if (!hasTurn && toolCount == 0 && tokens == null) {
      return const SizedBox.shrink();
    }
    final parts = <String>[
      if (hasTurn) '${view.turns} 轮',
      if (toolCount > 0) '$toolCount 次工具',
      if (tokens != null) '${_formatTokens(tokens)} tokens',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              parts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.dshText.labelSmall?.copyWith(
                color: p.tertiaryText,
              ),
            ),
          ),
          if (ratio != null) ...[
            const SizedBox(width: 8),
            Text(
              '${(ratio * 100).round()}%',
              style: context.dshText.labelSmall?.copyWith(
                color: ratio > 0.85 ? p.dangerRed : p.tertiaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
