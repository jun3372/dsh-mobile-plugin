import '../models/transcript_node.dart';

/// 把一个 assistant 尝试的增量 chunk 折叠成可展示文本。
///
/// 实现 0.2.1 `BlockAssembler` 的展示子集：text/reasoning 拼接，tool-call 只
/// 用于保持块结构（工具调用由 durable tool/call 事件单独渲染），usage/finish
/// 不参与展示。
class AssistantStreamAssembler {
  final Map<int, _AssembledBlock> _blocks = {};
  final List<int> _order = [];

  void clear() {
    _blocks.clear();
    _order.clear();
  }

  void push(Object? raw) {
    if (raw is! Map) return;
    final type = raw['type'];
    final index = (raw['index'] as num?)?.toInt();
    if (index == null) return;
    switch (type) {
      case 'block-start':
        _ensure(index, raw['blockType'] as String?);
      case 'text-delta':
        final block = _ensure(index, 'text');
        final text = raw['text'];
        if (text is String) block.text.write(text);
      case 'reasoning-delta':
        final block = _ensure(index, 'reasoning');
        final text = raw['text'];
        if (text is String) block.text.write(text);
      case 'tool-call-delta':
        final block = _ensure(index, 'tool-call');
        block.toolCallId ??= raw['id'] as String?;
        block.toolName ??= raw['name'] as String?;
        final delta = raw['argumentsDelta'];
        if (delta is String) block.arguments.write(delta);
      case 'block-end':
        final block = raw['block'];
        final kind = block is Map ? block['type'] as String? : null;
        final target = _ensure(index, kind);
        if (block is Map) {
          if (kind == 'text' || kind == 'reasoning') {
            final text = block['text'];
            if (text is String && text.isNotEmpty) {
              target.text
                ..clear()
                ..write(text);
            }
          } else if (kind == 'tool-call') {
            target.toolCallId ??= block['id'] as String?;
            target.toolName ??= block['name'] as String?;
            final args = block['arguments'];
            if (args is String && args.isNotEmpty) {
              target.arguments
                ..clear()
                ..write(args);
            }
          }
        }
        target.closed = true;
      default:
        break;
    }
  }

  _AssembledBlock _ensure(int index, String? type) {
    final existing = _blocks[index];
    if (existing != null) {
      if (existing.type == null && type != null) existing.type = type;
      return existing;
    }
    final block = _AssembledBlock(type);
    _blocks[index] = block;
    _order.add(index);
    return block;
  }

  bool get hasContent {
    for (final index in _order) {
      final block = _blocks[index]!;
      if ((block.type == 'text' || block.type == 'reasoning') &&
          block.text.toString().trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  String get text => _join('text');
  String get reasoning => _join('reasoning');

  String _join(String type) {
    final parts = <String>[];
    for (final index in _order) {
      final block = _blocks[index]!;
      if (block.type != type) continue;
      final value = block.text.toString();
      if (value.trim().isEmpty) continue;
      parts.add(value);
    }
    return parts.join('\n\n');
  }

  /// 当前折叠结果对应的展示节点；无可见内容时返回 null。
  TranscriptNode? liveNode(String attemptId) {
    if (!hasContent) return null;
    return TranscriptNode(
      id: 'live-$attemptId',
      kind: TranscriptKind.assistant,
      seq: 1 << 52,
      text: text,
      reasoning: reasoning.isEmpty ? null : reasoning,
      live: true,
    );
  }
}

class _AssembledBlock {
  String? type;
  final StringBuffer text = StringBuffer();
  final StringBuffer arguments = StringBuffer();
  String? toolCallId;
  String? toolName;
  bool closed = false;

  _AssembledBlock(this.type);
}
