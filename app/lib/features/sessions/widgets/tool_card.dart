import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/transcript_node.dart';

/// 工具调用卡片：名称 + 参数/结果可展开。
class ToolCard extends StatelessWidget {
  final TranscriptNode node;

  const ToolCard({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final failed = node.toolFailed;
    final running = !node.toolFinished;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: p.chipGray,
        borderRadius: BorderRadius.circular(DshRadius.codeBlock),
        border: Border.all(
          color: failed ? p.dangerRed.withValues(alpha: 0.35) : p.divider,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(
            failed
                ? Icons.error_outline
                : running
                ? Icons.build_circle_outlined
                : Icons.check_circle_outline,
            size: 18,
            color: failed
                ? p.dangerRed
                : running
                ? p.runningYellow
                : p.secondaryText,
          ),
          title: Text(
            node.toolName ?? '工具调用',
            style: context.dshText.bodySmall?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: p.foreground,
            ),
          ),
          subtitle: Text(
            running
                ? '执行中…'
                : failed
                ? '执行失败'
                : '已完成',
            style: context.dshText.bodySmall?.copyWith(
              color: failed ? p.dangerRed : p.secondaryText,
            ),
          ),
          children: [
            if ((node.toolArguments ?? '').isNotEmpty) ...[
              _SectionLabel('参数'),
              _CodeBlock(node.toolArguments!),
            ],
            if ((node.toolResult ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              _SectionLabel(failed ? '错误' : '结果'),
              _CodeBlock(node.toolResult!, error: failed),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: context.dshText.labelSmall?.copyWith(
            color: context.dsh.tertiaryText,
          ),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String text;
  final bool error;

  const _CodeBlock(this.text, {this.error = false});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: error ? p.dangerRed.withValues(alpha: 0.06) : p.background,
        borderRadius: BorderRadius.circular(DshRadius.thumb),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: error ? p.dangerRed : p.foreground,
            fontFamilyFallback: const ['Menlo', 'monospace'],
          ),
        ),
      ),
    );
  }
}
