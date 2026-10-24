import 'dart:async';

import '../session/projection_value_store.dart';
import 'dsh_mux_client.dart';
import 'mux_subscription.dart';

/// 服务器级 `session/control`：会话标题、running 等投影的实时来源。
///
/// 只负责维护投影水位并广播变化；具体 UI 通过 [store] 读取最新值。
class SessionControlHub {
  final DshMuxClient _client;
  final ProjectionValueStore store = ProjectionValueStore();
  final StreamController<String> _changes = StreamController<String>.broadcast(
    sync: true,
  );

  MuxSubscription? _subscription;
  StreamSubscription<MuxStreamEvent>? _events;
  bool _started = false;
  bool _disposed = false;

  SessionControlHub(this._client);

  /// 变化会话 id；空字符串表示整体基线替换。
  Stream<String> get changes => _changes.stream;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _subscription = _client.openStream(
      'session/control',
      args: const <String, Object?>{},
    );
    _events = _subscription!.events.listen(_onEvent);
  }

  void _onEvent(MuxStreamEvent event) {
    switch (event) {
      case MuxStreamOpened():
        // 基线紧跟其后；先保留旧值，收到 baseline 再整体替换。
        break;
      case MuxStreamItem():
        _onItem(event.value);
      case MuxStreamFailure():
        // 保留最后一次完整基线；断线重连后会用新基线替换。
        break;
      case MuxStreamEnded():
      case MuxStreamCarrierLost():
        break;
    }
  }

  void _onItem(Object? value) {
    if (value is! Map) return;
    final type = value['type'];
    if (type == 'baseline') {
      final payload = value['value'];
      final projections = payload is Map ? payload['projections'] : null;
      store.replaceBaseline(projections);
      if (!_changes.isClosed) _changes.add('');
      return;
    }
    if (type != 'projection') return;
    final sessionId = value['sessionId'];
    final key = value['key'];
    final seq = value['seq'];
    if (sessionId is! String || key is! String || seq is! num) return;
    if (store.applyProjection(
      sessionId: sessionId,
      key: key,
      value: value['value'],
      seq: seq.toInt(),
    )) {
      if (!_changes.isClosed) _changes.add(sessionId);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events?.cancel();
    _events = null;
    _subscription?.dispose();
    _subscription = null;
    store.clear();
    unawaited(_changes.close());
  }
}
