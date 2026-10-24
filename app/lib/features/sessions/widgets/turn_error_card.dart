import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/transcript_node.dart';

/// 轮次错误 / 提示 / 压缩摘要节点。
class TurnNoticeCard extends StatelessWidget {
  final TranscriptNode node;

  const TurnNoticeCard({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final error = node.kind == TranscriptKind.error;
    final compaction = node.kind == TranscriptKind.compaction;
    if (node.text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: error ? p.dangerRed.withValues(alpha: 0.07) : p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.leading),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error
                ? Icons.error_outline
                : compaction
                ? Icons.compress_rounded
                : Icons.info_outline,
            size: 15,
            color: error ? p.dangerRed : p.secondaryText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              node.text,
              style: context.dshText.bodySmall?.copyWith(
                height: 1.45,
                color: error ? p.dangerRed : p.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
