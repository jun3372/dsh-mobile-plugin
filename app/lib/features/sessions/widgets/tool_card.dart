import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/transcript_node.dart';
import 'code_highlight.dart';

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
              ToolSectionLabel('参数'),
              ToolCodeBlock(node.toolArguments!),
            ],
            if ((node.toolResult ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              ToolSectionLabel(failed ? '错误' : '结果'),
              ToolCodeBlock(node.toolResult!, error: failed),
            ],
          ],
        ),
      ),
    );
  }
}

class ToolSectionLabel extends StatelessWidget {
  final String text;

  const ToolSectionLabel(this.text, {super.key});

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

class ToolCodeBlock extends StatelessWidget {
  final String text;
  final bool error;

  /// 传入 re_highlight 语言名（如 'json'）时做语法高亮，解析失败退回纯文本。
  final String? language;

  const ToolCodeBlock(
    this.text, {
    super.key,
    this.error = false,
    this.language,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final base = TextStyle(
      fontSize: 12,
      height: 1.4,
      color: error ? p.dangerRed : p.foreground,
      fontFamilyFallback: const ['Menlo', 'monospace'],
    );
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: error ? p.dangerRed.withValues(alpha: 0.06) : p.background,
        borderRadius: BorderRadius.circular(DshRadius.thumb),
      ),
      child: SingleChildScrollView(
        child: SelectableText.rich(
          _highlightedSpan(context, base) ?? TextSpan(text: text, style: base),
        ),
      ),
    );
  }

  /// 语法高亮：highlightLines 按行返回，这里拼回整段 TextSpan。
  TextSpan? _highlightedSpan(BuildContext context, TextStyle base) {
    if (language == null) return null;
    final p = context.dsh;
    final lines = DshCodeHighlight.highlightLines(
      source: text,
      language: language,
      base: base,
      theme: dshCodeTheme(p, Theme.of(context).brightness),
    );
    if (lines == null) return null;
    final children = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      children.addAll(lines[i]);
      if (i < lines.length - 1) children.add(const TextSpan(text: '\n'));
    }
    return TextSpan(children: children);
  }
}
