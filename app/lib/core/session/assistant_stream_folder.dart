import '../models/session_event.dart';
import '../models/transcript_node.dart';
import 'assistant_stream_assembler.dart';

/// 一个仍在进行的 assistant 尝试的本地状态。
class _LiveAttempt {
  final String attemptId;
  final int startedAfterSeq;
  final int turn;
  final int step;
  int nextIndex;

  _LiveAttempt({
    required this.attemptId,
    required this.startedAfterSeq,
    required this.turn,
    required this.step,
    required this.nextIndex,
  });
}

enum AssistantFrameResult { ignored, updated, rebaseline }

enum AssistantDurableResult { publish, staged }

/// 把 `session/follow` 的 assistant-stream 帧折叠为一条临时 assistant 节点。
///
/// 与 0.2.1 `ClientAssistantStream` 对齐：
/// - 持久 assistant 结算在尝试仍活跃时先暂存，等 `end` 帧核对 `outcome.seq`
///   后放行，避免临时节点与持久节点并存；
/// - `abandoned` 立即撤下临时节点；
/// - attemptId/index/outcome 违约统一返回 rebaseline，由上层重开 follow。
class AssistantStreamFolder {
  _LiveAttempt? _attempt;
  final Map<int, SessionWireEvent> _pending = {};
  final Set<int> _published = {};
  final List<SessionWireEvent> _released = [];
  final AssistantStreamAssembler _assembler = AssistantStreamAssembler();

  bool get isLive => _attempt != null || _pending.isNotEmpty;

  int? get activeTurn => _attempt?.turn;

  int? get activeStep => _attempt?.step;

  void clear() {
    _attempt = null;
    _pending.clear();
    _published.clear();
    _released.clear();
    _assembler.clear();
  }

  /// 用 follow snapshot 的 assistantStream baseline 重建进行中的输出。
  void resetWithBaseline(Object? baseline) {
    clear();
    if (baseline is! Map) return;
    final active = baseline['activeAttempt'];
    if (active is! Map) return;
    final attemptId = active['attemptId'];
    if (attemptId is! String) return;
    final attempt = _LiveAttempt(
      attemptId: attemptId,
      startedAfterSeq: (active['startedAfterSeq'] as num?)?.toInt() ?? 0,
      turn: (active['turn'] as num?)?.toInt() ?? 0,
      step: (active['step'] as num?)?.toInt() ?? 0,
      nextIndex: (active['nextIndex'] as num?)?.toInt() ?? 0,
    );
    final chunks = expandCompactAssistantStream(active['stream']);
    final take = attempt.nextIndex.clamp(0, chunks.length);
    for (var i = 0; i < take; i++) {
      _assembler.push(chunks[i]);
    }
    _attempt = attempt;
  }

  /// snapshot 窗口里已落地的结算不能再次被 `end` 帧放行。
  void seedPublished(Iterable<SessionWireEvent> events) {
    for (final event in events) {
      if (_isSettlement(event)) _published.add(event.seq);
    }
  }

  /// 收下一批已放行的持久结算；由上层写入转写。
  List<SessionWireEvent> drainReleased() {
    if (_released.isEmpty) return const [];
    final released = List<SessionWireEvent>.from(_released);
    _released.clear();
    return released;
  }

  /// 持久事件到达：活跃尝试的结算暂存，其余照常发布。
  AssistantDurableResult acceptDurable(SessionWireEvent event) {
    if (_isSettlement(event)) {
      if (_matchesAttempt(event)) {
        _pending[event.seq] = event;
        return AssistantDurableResult.staged;
      }
      _published.add(event.seq);
      return AssistantDurableResult.publish;
    }
    if (event.type == 'step/end') _releaseForStepEnd(event);
    return AssistantDurableResult.publish;
  }

  AssistantFrameResult acceptFrame(Object? raw) {
    if (raw is! Map) return AssistantFrameResult.ignored;
    switch (raw['type']) {
      case 'start':
        final attemptId = raw['attemptId'];
        if (attemptId is! String) return AssistantFrameResult.ignored;
        if (_attempt != null || _pending.isNotEmpty) {
          return AssistantFrameResult.rebaseline;
        }
        _assembler.clear();
        _attempt = _LiveAttempt(
          attemptId: attemptId,
          startedAfterSeq: (raw['startedAfterSeq'] as num?)?.toInt() ?? 0,
          turn: (raw['turn'] as num?)?.toInt() ?? 0,
          step: (raw['step'] as num?)?.toInt() ?? 0,
          nextIndex: 0,
        );
        return AssistantFrameResult.updated;
      case 'chunk':
        final attempt = _attempt;
        if (attempt == null || raw['attemptId'] != attempt.attemptId) {
          return AssistantFrameResult.ignored;
        }
        final index = (raw['index'] as num?)?.toInt();
        if (index != attempt.nextIndex) return AssistantFrameResult.rebaseline;
        _assembler.push(raw['chunk']);
        attempt.nextIndex += 1;
        return AssistantFrameResult.updated;
      case 'end':
        final attempt = _attempt;
        if (attempt == null || raw['attemptId'] != attempt.attemptId) {
          return AssistantFrameResult.ignored;
        }
        final index = (raw['index'] as num?)?.toInt();
        if (index != attempt.nextIndex) return AssistantFrameResult.rebaseline;
        final outcome = raw['outcome'];
        if (outcome is! Map) return AssistantFrameResult.rebaseline;
        _attempt = null;
        switch (outcome['kind']) {
          case 'abandoned':
            if (_pending.isNotEmpty) return AssistantFrameResult.rebaseline;
            _assembler.clear();
            return AssistantFrameResult.updated;
          case 'committed':
            final seq = (outcome['seq'] as num?)?.toInt();
            final eventType = outcome['eventType'];
            if (seq == null || eventType is! String) {
              return AssistantFrameResult.rebaseline;
            }
            if (_published.contains(seq)) {
              _assembler.clear();
              return AssistantFrameResult.updated;
            }
            final settlement = _pending.remove(seq);
            if (settlement == null || settlement.type != eventType) {
              _assembler.clear();
              return AssistantFrameResult.rebaseline;
            }
            _published.add(seq);
            _released.add(settlement);
            _assembler.clear();
            return AssistantFrameResult.updated;
          default:
            return AssistantFrameResult.rebaseline;
        }
      default:
        return AssistantFrameResult.ignored;
    }
  }

  bool _isSettlement(SessionWireEvent event) =>
      event.type == 'assistant/message' || event.type == 'assistant/attempt';

  bool _matchesAttempt(SessionWireEvent event) {
    final attempt = _attempt;
    if (attempt == null) return false;
    if (event.seq <= attempt.startedAfterSeq) return false;
    final data = event.data;
    if (data is! Map) return false;
    if ((data['turn'] as num?)?.toInt() != attempt.turn ||
        (data['step'] as num?)?.toInt() != attempt.step) {
      return false;
    }
    if (event.type == 'assistant/message' && event.surfaceOp != 'append') {
      return false;
    }
    return true;
  }

  void _releaseForStepEnd(SessionWireEvent event) {
    final data = event.data;
    if (data is! Map) return;
    final turn = (data['turn'] as num?)?.toInt();
    final step = (data['step'] as num?)?.toInt();
    if (turn == null || step == null) return;
    final ready = <int>[];
    for (final entry in _pending.entries) {
      final settlement = entry.value.data;
      if (settlement is! Map) continue;
      if ((settlement['turn'] as num?)?.toInt() == turn &&
          (settlement['step'] as num?)?.toInt() == step) {
        ready.add(entry.key);
      }
    }
    for (final seq in ready) {
      final settlement = _pending.remove(seq);
      if (settlement != null) _released.add(settlement);
    }
  }

  TranscriptNode? get liveNode {
    final attempt = _attempt;
    if (attempt == null) return null;
    return _assembler.liveNode(attempt.attemptId);
  }
}

/// 展开 0.2.1 compact assistant stream（text-chunks / reasoning-chunks /
/// tool-call-chunks / raw chunk），还原为原始 chunk 序列。
List<Object?> expandCompactAssistantStream(Object? stream) {
  if (stream is! List) return const [];
  final chunks = <Object?>[];
  for (final record in stream) {
    if (record is! Map) continue;
    switch (record['type']) {
      case 'text-chunks':
        _expandRun(
          record,
          chunks,
          (index, text) => {'type': 'text-delta', 'index': index, 'text': text},
        );
      case 'reasoning-chunks':
        _expandRun(
          record,
          chunks,
          (index, text) => {
            'type': 'reasoning-delta',
            'index': index,
            'text': text,
          },
        );
      case 'tool-call-chunks':
        final index = (record['index'] as num?)?.toInt() ?? 0;
        final id = record['id'] as String? ?? '';
        final name = record['name'] as String?;
        final args = record['args'];
        if (args is! List) break;
        for (var i = 0; i < args.length; i++) {
          chunks.add({
            'type': 'tool-call-delta',
            'index': index,
            'id': id,
            if (i == 0 && name != null) 'name': name,
            'argumentsDelta': args[i] is String ? args[i] : '',
          });
        }
      case 'chunk':
        chunks.add(record['chunk']);
    }
  }
  return chunks;
}

void _expandRun(
  Map record,
  List<Object?> chunks,
  Map<String, Object?> Function(int index, String text) build,
) {
  final index = (record['index'] as num?)?.toInt() ?? 0;
  final texts = record['texts'];
  if (texts is! List) return;
  for (final text in texts) {
    if (text is String && text.isNotEmpty) {
      chunks.add(build(index, text));
    }
  }
}
