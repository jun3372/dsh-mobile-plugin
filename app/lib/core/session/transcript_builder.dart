import '../models/session_event.dart';
import '../models/transcript_node.dart';

/// 把 0.2.1 持久事件流折叠为会话转写（纯函数式重建，按 seq 去重）。
///
/// 只渲染用户可见的节点；注入上下文、模型选择、request 头等日志型事件
/// 一律忽略。工具调用与结果按 callId 合并为一张卡片。
class TranscriptBuilder {
  final Map<int, SessionWireEvent> _events = {};
  final Set<String> _seenRpcIds = {};

  List<TranscriptNode> _nodes = const [];

  List<TranscriptNode> get nodes => _nodes;
  Set<String> get seenRpcIds => _seenRpcIds;

  int get baseSeq {
    if (_events.isEmpty) return -1;
    var min = -1;
    for (final seq in _events.keys) {
      if (min < 0 || seq < min) min = seq;
    }
    return min;
  }

  void replace(List<SessionWireEvent> events) {
    _events
      ..clear()
      ..addEntries(events.map((event) => MapEntry(event.seq, event)));
    _rebuild();
  }

  void append(SessionWireEvent event) {
    if (_events.containsKey(event.seq)) return;
    _events[event.seq] = event;
    _rebuild();
  }

  void prepend(List<SessionWireEvent> events) {
    var changed = false;
    for (final event in events) {
      if (_events.containsKey(event.seq)) continue;
      _events[event.seq] = event;
      changed = true;
    }
    if (changed) _rebuild();
  }

  void clear() {
    _events.clear();
    _seenRpcIds.clear();
    _nodes = const [];
  }

  void _rebuild() {
    final seqs = _events.keys.toList()..sort();
    final nodes = <TranscriptNode>[];
    final toolIndexByCallId = <String, int>{};
    final compactionSummaries = <String, String>{};

    for (final seq in seqs) {
      final event = _events[seq]!;
      final data = event.data;
      switch (event.type) {
        case 'user/message':
          if (data is! Map) break;
          final source = data['source'];
          if (event.surfaceOp == 'replace') {
            // 压缩替换消息本身不展示，改在日志位置放一条摘要标记。
            final checkpointId = _compactCheckpointId(source);
            if (checkpointId != null) {
              final summary = compactionSummaries[checkpointId];
              nodes.add(
                TranscriptNode(
                  id: 'compaction-$seq',
                  kind: TranscriptKind.compaction,
                  seq: seq,
                  timeMs: event.time > 0 ? event.time : null,
                  text: summary?.isNotEmpty == true ? summary! : '上下文已压缩',
                ),
              );
            }
            break;
          }
          final rpcId = promptRpcIdOf(source);
          if (rpcId != null) _seenRpcIds.add(rpcId);
          if (source is! Map || source['kind'] != 'user') break;
          final summary = summarizeContent(data['content']);
          if (summary.text.isEmpty && summary.imageCount == 0) break;
          nodes.add(
            TranscriptNode(
              id: 'user-$seq',
              kind: TranscriptKind.user,
              seq: seq,
              timeMs: event.time > 0 ? event.time : null,
              text: summary.text,
              imageCount: summary.imageCount,
              images: summary.images,
            ),
          );
        case 'assistant/message':
          if (data is! Map) break;
          final message = data['message'];
          if (message is! Map) break;
          final summary = summarizeContent(message['content']);
          if (summary.text.isEmpty &&
              (summary.reasoning == null) &&
              summary.imageCount == 0) {
            break;
          }
          nodes.add(
            TranscriptNode(
              id: 'assistant-$seq',
              kind: TranscriptKind.assistant,
              seq: seq,
              timeMs: event.time > 0 ? event.time : null,
              text: summary.text,
              reasoning: summary.reasoning,
              imageCount: summary.imageCount,
              images: summary.images,
            ),
          );
        case 'tool/call':
          if (data is! Map) break;
          final callId = data['callId'];
          final name = data['name'];
          if (callId is! String || name is! String) break;
          toolIndexByCallId[callId] = nodes.length;
          nodes.add(
            TranscriptNode(
              id: 'tool-$callId',
              kind: TranscriptKind.tool,
              seq: seq,
              timeMs: event.time > 0 ? event.time : null,
              toolName: name,
              toolCallId: callId,
              toolArguments: data['arguments'] as String?,
            ),
          );
        case 'tool/result':
          if (data is! Map) break;
          final message = data['message'];
          final callId = message is Map ? message['toolCallId'] : null;
          final error = data['error'];
          final errorReason = error is Map ? error['reason'] as String? : null;
          final content = message is Map
              ? summarizeContent(message['content'])
              : (text: '', reasoning: null, imageCount: 0, images: const []);
          final failed = message is Map && message['isError'] == true;
          final resultText = errorReason ?? content.text;
          final index = callId is String ? toolIndexByCallId[callId] : null;
          if (index != null) {
            nodes[index] = nodes[index].copyWith(
              toolResult: resultText,
              toolFailed: failed,
              toolFinished: true,
            );
          } else {
            nodes.add(
              TranscriptNode(
                id: 'tool-result-$seq',
                kind: TranscriptKind.tool,
                seq: seq,
                timeMs: event.time > 0 ? event.time : null,
                toolName: '工具结果',
                toolCallId: callId is String ? callId : null,
                toolResult: resultText,
                toolFailed: failed,
                toolFinished: true,
              ),
            );
          }
        case 'turn/end':
          if (data is! Map) break;
          final reason = data['reason'];
          if (reason is! Map) break;
          final kind = reason['kind'];
          if (kind == 'error') {
            final error = reason['error'];
            final message = error is Map
                ? (error['message'] as String? ?? error['code'] as String?)
                : null;
            nodes.add(
              TranscriptNode(
                id: 'error-$seq',
                kind: TranscriptKind.error,
                seq: seq,
                timeMs: event.time > 0 ? event.time : null,
                text: message?.isNotEmpty == true ? message! : '本轮执行失败',
              ),
            );
          } else if (kind == 'max-tokens') {
            nodes.add(
              TranscriptNode(
                id: 'max-$seq',
                kind: TranscriptKind.notice,
                seq: seq,
                timeMs: event.time > 0 ? event.time : null,
                text: '达到输出长度上限，本轮已结束',
              ),
            );
          } else if (kind == 'interrupted') {
            nodes.add(
              TranscriptNode(
                id: 'interrupted-$seq',
                kind: TranscriptKind.error,
                seq: seq,
                timeMs: event.time > 0 ? event.time : null,
                text: 'DSH 进程在本轮完成前退出',
              ),
            );
          }
        case 'compaction/summary':
          if (data is! Map) break;
          final compactionId = data['compactionId'];
          if (compactionId is String) {
            compactionSummaries[compactionId] = summarizeContent(
              data['summary'],
            ).text;
          }
        default:
          break;
      }
    }

    _nodes = List.unmodifiable(nodes);
  }

  /// 0.2.1 压缩检查点：`source = {kind:'plugin', plugin:'compact', compactionId}`。
  String? _compactCheckpointId(Object? source) {
    if (source is! Map) return null;
    if (source['kind'] != 'plugin' || source['plugin'] != 'compact') {
      return null;
    }
    final compactionId = source['compactionId'];
    return compactionId is String && compactionId.isNotEmpty
        ? compactionId
        : null;
  }
}
