import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/transcript_node.dart';
import '../../../widgets/common.dart';
import 'tool_card.dart';

export 'tool_card.dart' show ToolSectionLabel, ToolCodeBlock;

/// 工具名 → 动词与图标（对齐 Web 端轨迹行的说法）。
(String, IconData) toolVerb(String? toolName) {
  final name = (toolName ?? '').toLowerCase();
  if (name.contains('bash') || name.contains('command') || name == 'sh') {
    return ('执行命令', Icons.terminal_outlined);
  }
  if (name.contains('edit') ||
      name.contains('write') ||
      name.contains('patch')) {
    return ('修改文件', Icons.edit_note_outlined);
  }
  if (name.contains('read')) {
    return ('读取文件', Icons.description_outlined);
  }
  if (name.contains('search') ||
      name.contains('grep') ||
      name.contains('glob')) {
    return ('检索内容', Icons.search_outlined);
  }
  return ('调用工具', Icons.build_outlined);
}

// 摘要/语言探测结果缓存：流式期间同一工具行每帧重建，避免重复 jsonDecode。
// 键为入参字符串；超过上限整体清空（简单防膨胀，命中率远够用）。
const int _memoCap = 512;
final Map<String, String> _argSummaryMemo = {};
final Map<String, String?> _langMemo = {};

/// 从工具参数 JSON 提取一行摘要：优先 command/path 等首个字符串字段，
/// 解析失败回退工具名本身。
String toolArgSummary(TranscriptNode node) {
  final raw = node.toolArguments;
  if (raw != null && raw.isNotEmpty) {
    final cached = _argSummaryMemo[raw];
    if (cached != null) return cached;
    try {
      final args = jsonDecode(raw);
      if (args is Map) {
        const keys = [
          'command',
          'cmd',
          'path',
          'file_path',
          'pattern',
          'query',
          'url',
          'content',
        ];
        for (final key in keys) {
          final value = args[key];
          if (value is String && value.trim().isNotEmpty) {
            final summary = value.trim().replaceAll('\n', ' ');
            if (_argSummaryMemo.length >= _memoCap) _argSummaryMemo.clear();
            _argSummaryMemo[raw] = summary;
            return summary;
          }
        }
      }
    } on FormatException {
      // 非 JSON 参数则回退。
    }
  }
  return node.toolName ?? '工具调用';
}

/// 轻量语言探测：工具参数/结果可能是 JSON、shell、XML、YAML 或纯文本，
/// 探测不出返回 null（走纯文本，不高亮）。
final RegExp _shellHeadRegExp = RegExp(
  r'^(?:\$|sudo |cd |ls |cat |head |tail |grep |find |rg |rm |mv |cp |mkdir |touch |chmod |git |flutter |dart |npm |pnpm |yarn |go |python3? |node |curl |wget |echo |which |df |ps )',
);
final RegExp _yamlKeyRegExp = RegExp(r'^[\w.\-/]+:(\s|$)', multiLine: true);
final RegExp _iniSectionRegExp = RegExp(r'^\[[\w.-]+\]$', multiLine: true);
final RegExp _iniPairRegExp = RegExp(r'^[\w.-]+=[^\n]*$', multiLine: true);

String? detectCodeLanguage(String text) {
  if (_langMemo.length >= _memoCap) _langMemo.clear();
  if (_langMemo.containsKey(text)) return _langMemo[text];
  final result = _detectCodeLanguageUncached(text);
  _langMemo[text] = result;
  return result;
}

String? _detectCodeLanguageUncached(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('{') || t.startsWith('[')) {
    try {
      jsonDecode(t);
      return 'json';
    } on FormatException {
      // 截断的 JSON 交给后续探测。
    }
  }
  if (t.startsWith('<') && (t.contains('</') || t.contains('/>'))) {
    return 'xml';
  }
  // shell：常见命令开头，或带管道/链式/重定向的命令行。
  if (_shellHeadRegExp.hasMatch(t) ||
      (!t.contains(':\n') &&
          !t.startsWith(' ') &&
          (t.contains(' | ') || t.contains(' && ') || t.contains(' 2>')))) {
    return 'bash';
  }
  // YAML：行首「key:」多行；INI：section 头或 key=value。
  if (_yamlKeyRegExp.hasMatch(t)) return 'yaml';
  if (_iniSectionRegExp.hasMatch(t) || _iniPairRegExp.hasMatch(t)) {
    return 'ini';
  }
  return null;
}

/// 会话流中的工具调用紧凑行：图标 + 动词 + 参数摘要 + chevron，
/// 点击弹出底部详情 sheet（Qoder 桌面端同款样式）。
class ToolCompactRow extends StatelessWidget {
  final TranscriptNode node;

  const ToolCompactRow({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final failed = node.toolFailed;
    final running = !node.toolFinished;
    final (verb, _) = toolVerb(node.toolName);
    final iconColor = failed
        ? p.dangerRed
        : running
        ? p.runningYellow
        : p.midText;
    final icon = failed
        ? Icons.error_outline
        : running
        ? Icons.build_circle_outlined
        : toolVerb(node.toolName).$2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => showDshSheet(
          context,
          heightFactor: 0.7,
          builder: (_) => ToolDetailSheet(node: node),
        ),
        child: Row(
          children: [
            Icon(icon, size: DshIcon.tool, color: iconColor),
            const SizedBox(width: DshSpace.x2),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: '$verb ',
                  style: context.dshText.bodySmall?.copyWith(
                    fontSize: 14,
                    color: p.midText,
                  ),
                  children: [
                    TextSpan(
                      text: toolArgSummary(node),
                      style: context.dshText.bodySmall?.copyWith(
                        fontSize: 14,
                        color: p.secondaryText,
                      ),
                    ),
                    if (running)
                      TextSpan(
                        text: ' …',
                        style: context.dshText.bodySmall?.copyWith(
                          fontSize: 14,
                          color: p.runningYellow,
                        ),
                      ),
                    if (failed)
                      TextSpan(
                        text: ' · 失败',
                        style: context.dshText.bodySmall?.copyWith(
                          fontSize: 14,
                          color: p.dangerRed,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: DshSpace.x1),
            Icon(
              Icons.chevron_right_rounded,
              size: DshIcon.tool,
              color: p.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }
}

/// 工具调用详情 sheet：状态行 + 参数/结果代码块。
class ToolDetailSheet extends StatelessWidget {
  final TranscriptNode node;

  const ToolDetailSheet({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final failed = node.toolFailed;
    final running = !node.toolFinished;
    final (verb, icon) = toolVerb(node.toolName);
    final iconColor = failed
        ? p.dangerRed
        : running
        ? p.runningYellow
        : p.midText;
    final statusText = running
        ? '$verb · 执行中…'
        : failed
        ? '$verb · 执行失败'
        : '$verb · 已完成';
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DshSpace.x5,
          DshSpace.x3,
          DshSpace.x5,
          DshSpace.x5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: DshIcon.action, color: iconColor),
                const SizedBox(width: DshSpace.x2),
                Expanded(
                  child: Text(
                    statusText,
                    style: context.dshText.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: failed ? p.dangerRed : p.foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DshSpace.x1),
            Padding(
              padding: const EdgeInsets.only(left: DshSpace.x6),
              child: Text(
                node.toolName ?? '工具调用',
                style: context.dshText.labelSmall?.copyWith(
                  color: p.tertiaryText,
                ),
              ),
            ),
            if ((node.toolArguments ?? '').isNotEmpty) ...[
              const SizedBox(height: DshSpace.x4),
              ToolSectionLabel('参数'),
              ToolCodeBlock(
                node.toolArguments!,
                language: detectCodeLanguage(node.toolArguments!),
              ),
            ],
            if ((node.toolResult ?? '').isNotEmpty) ...[
              const SizedBox(height: DshSpace.x3),
              ToolSectionLabel(failed ? '错误' : '结果'),
              if (failed)
                ToolCodeBlock(node.toolResult!, error: failed)
              else
                ToolCodeBlock(
                  node.toolResult!,
                  language: detectCodeLanguage(node.toolResult!),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
