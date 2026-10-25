import '../models/session_event.dart';
import '../models/transcript_node.dart';

/// 把 0.2.1 持久事件流折叠为会话转写（按 seq 去重）。
///
/// 只渲染用户可见的节点；注入上下文、模型选择、request 头等日志型事件
/// 一律忽略。工具调用与结果按 callId 合并为一张卡片。
///
/// 性能：流式追加（seq 单调递增）走增量路径，只处理新事件并定点更新
/// 对应节点；乱序/翻页（prepend）才回退到全量重建，避免长会话下
/// 每条事件都触发 O(n) 重建。
class TranscriptBuilder {
  final Map<int, SessionWireEvent> _events = {};
  final Set<String> _seenRpcIds = {};

  // 增量路径与全量重建共享的状态。
  final Map<String, int> _toolIndexByCallId = {};
  final Map<String, String> _compactionSummaries = {};

  List<TranscriptNode> _nodes = [];
  int _minSeq = -1;
  int _maxSeq = -1;

  List<TranscriptNode> get nodes => List.unmodifiable(_nodes);
  Set<String> get seenRpcIds => _seenRpcIds;

  int get baseSeq => _events.isEmpty ? -1 : _minSeq;

  void replace(List<SessionWireEvent> events) {
    _events
      ..clear()
      ..addEntries(events.map((event) => MapEntry(event.seq, event)));
    _rebuild();
  }

  void append(SessionWireEvent event) {
    if (_events.containsKey(event.seq)) return;
    // seq 单调递增时增量处理；乱序（罕见）回退全量重建保证结果一致。
    if (_events.isNotEmpty && event.seq <= _maxSeq) {
      _events[event.seq] = event;
      _rebuild();
      return;
    }
    _events[event.seq] = event;
    if (_events.length == 1) _minSeq = event.seq;
    _maxSeq = event.seq;
    _applyEvent(event, _nodes);
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
    _toolIndexByCallId.clear();
    _compactionSummaries.clear();
    _nodes = [];
    _minSeq = -1;
    _maxSeq = -1;
  }

  void _rebuild() {
    final seqs = _events.keys.toList()..sort();
    final nodes = <TranscriptNode>[];
    _toolIndexByCallId.clear();
    _compactionSummaries.clear();
    for (final seq in seqs) {
      _applyEvent(_events[seq]!, nodes);
    }
    _minSeq = seqs.isEmpty ? -1 : seqs.first;
    _maxSeq = seqs.isEmpty ? -1 : seqs.last;
    _nodes = nodes;
  }

  /// 处理单条事件并更新 [nodes]（全量重建传新列表，增量传 `_nodes`）。
  void _applyEvent(SessionWireEvent event, List<TranscriptNode> nodes) {
    final seq = event.seq;
    final data = event.data;
    switch (event.type) {
      case 'user/message':
        if (data is! Map) break;
        final source = data['source'];
        if (event.surfaceOp == 'replace') {
          // 压缩替换消息本身不展示，改在日志位置放一条摘要标记。
          final checkpointId = _compactCheckpointId(source);
          if (checkpointId != null) {
            final summary = _compactionSummaries[checkpointId];
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
        _toolIndexByCallId[callId] = nodes.length;
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
        final index = callId is String ? _toolIndexByCallId[callId] : null;
        if (index != null && index < nodes.length) {
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
          _compactionSummaries[compactionId] = summarizeContent(
            data['summary'],
          ).text;
        }
      default:
        break;
    }
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
