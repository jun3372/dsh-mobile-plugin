/// 每个会话的投影水位：`asOfSeq` + 逐键 seq。
///
/// 服务器级 `session/control` 的基线不带逐键 seq，因此基线值以 asOfSeq 为
/// 初始水位；之后只接受更高 seq 的同键替换。值只做浅拷贝引用，禁止修改。
class ProjectionValueStore {
  final Map<String, ProjectionSessionState> _sessions = {};

  Iterable<String> get sessionIds => _sessions.keys;

  ProjectionSessionState? stateOf(String sessionId) => _sessions[sessionId];

  Map<String, Object?>? valuesOf(String sessionId) =>
      _sessions[sessionId]?.values;

  int asOfSeqOf(String sessionId) => _sessions[sessionId]?.asOfSeq ?? 0;

  void clear() => _sessions.clear();

  /// 用 control baseline 整体替换（重连后新基线覆盖旧值）。
  void replaceBaseline(Object? projections) {
    _sessions.clear();
    if (projections is! Map) return;
    projections.forEach((sessionId, value) {
      if (sessionId is! String || value is! Map) return;
      final asOfSeq = (value['asOfSeq'] as num?)?.toInt() ?? 0;
      final rawValues = value['values'];
      final values = <String, Object?>{
        if (rawValues is Map)
          for (final entry in rawValues.entries)
            if (entry.key is String) entry.key as String: entry.value,
      };
      _sessions[sessionId] = ProjectionSessionState(
        asOfSeq: asOfSeq,
        values: values,
        keySeqs: {for (final key in values.keys) key: asOfSeq},
      );
    });
  }

  /// 应用一条 `projection` 增量；返回是否生效。
  bool applyProjection({
    required String sessionId,
    required String key,
    required Object? value,
    required int seq,
  }) {
    final existing = _sessions[sessionId];
    if (existing == null) {
      _sessions[sessionId] = ProjectionSessionState(
        asOfSeq: seq,
        values: {key: value},
        keySeqs: {key: seq},
      );
      return true;
    }
    final previousSeq = existing.keySeqs[key];
    if (previousSeq != null && seq <= previousSeq) return false;
    existing.keySeqs[key] = seq;
    if (seq > existing.asOfSeq) existing.asOfSeq = seq;
    existing.values[key] = value;
    return true;
  }
}

class ProjectionSessionState {
  int asOfSeq;
  final Map<String, Object?> values;
  final Map<String, int> keySeqs;

  ProjectionSessionState({
    required this.asOfSeq,
    required this.values,
    required this.keySeqs,
  });
}
