import 'dart:async';
import 'dart:convert';

import '../services/api_client.dart';
import 'mux_frame.dart';
import 'mux_socket.dart';
import 'mux_subscription.dart';
import 'reconnect_policy.dart';

enum MuxConnectionState { idle, connecting, connected, waiting, closed }

/// 每服务器一条物理 WebSocket，多路复用任意数量逻辑流。
///
/// - streamId 由客户端生成且永不复用；
/// - 连接断开后保留订阅，重连成功自动用新 streamId 重开；
/// - 不打印 token / 帧内容。
class DshMuxClient {
  final Uri origin;
  final Future<String?> Function() tokenProvider;
  final MuxSocketFactory socketFactory;
  final ReconnectPolicy reconnectPolicy;

  final StreamController<MuxConnectionState> _states =
      StreamController<MuxConnectionState>.broadcast(sync: true);
  final Set<MuxSubscription> _subscriptions = <MuxSubscription>{};

  MuxConnectionState _state = MuxConnectionState.idle;
  MuxSocket? _socket;
  StreamSubscription<Object?>? _messageSubscription;
  Timer? _retryTimer;
  Future<void>? _connecting;
  int _attempt = 0;
  int _ignoredFrames = 0;
  bool _disposed = false;

  DshMuxClient({
    required this.origin,
    required this.tokenProvider,
    this.socketFactory = connectIoMuxSocket,
    this.reconnectPolicy = const ReconnectPolicy(),
  });

  MuxConnectionState get state => _state;

  Stream<MuxConnectionState> get states => _states.stream;

  int get ignoredFrames => _ignoredFrames;

  /// 启动连接（幂等）。
  void ensureConnected() {
    if (_disposed || _state == MuxConnectionState.connected) return;
    if (_retryTimer != null || _connecting != null) return;
    unawaited(_connect());
  }

  /// 立即重试（跳过退避等待），用于用户主动恢复。
  void reconnectNow() {
    if (_disposed) return;
    if (_state == MuxConnectionState.connected || _connecting != null) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempt = 0;
    unawaited(_connect());
  }

  /// 打开一条逻辑流；连接未就绪时先登记，连上后自动 open。
  MuxSubscription openStream(
    String endpoint, {
    Map<String, Object?> args = const {},
    bool autoReopen = true,
  }) {
    final subscription = MuxSubscription(
      endpoint: endpoint,
      args: args,
      autoReopen: autoReopen,
      onCancel: _cancelSubscription,
      onRestart: _restartSubscription,
    );
    _subscriptions.add(subscription);
    if (_disposed) {
      subscription.dispose();
      return subscription;
    }
    if (_state == MuxConnectionState.connected && _socket != null) {
      _sendOpen(subscription);
    } else {
      subscription.phase = MuxSubscriptionPhase.waiting;
      ensureConnected();
    }
    return subscription;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    for (final subscription in [..._subscriptions]) {
      subscription.dispose();
    }
    _subscriptions.clear();
    final socket = _socket;
    _socket = null;
    _messageSubscription?.cancel();
    _messageSubscription = null;
    if (socket != null) unawaited(socket.close(1000, 'disposed'));
    _setState(MuxConnectionState.closed);
    unawaited(_states.close());
  }

  Future<void> _connect() async {
    if (_disposed || _connecting != null) return;
    final task = _runConnect();
    _connecting = task;
    try {
      await task;
    } finally {
      if (identical(_connecting, task)) _connecting = null;
    }
  }

  Future<void> _runConnect() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _setState(MuxConnectionState.connecting);
    MuxSocket? socket;
    try {
      final token = await tokenProvider();
      if (_disposed) return;
      if (token == null || token.isEmpty) {
        throw StateError('缺少访问 token');
      }
      final uri = _muxUri();
      socket = await socketFactory(uri, token);
      if (_disposed) {
        await socket.close(1000, 'disposed');
        return;
      }
      _socket = socket;
      _attempt = 0;
      _messageSubscription = socket.messages.listen(
        (message) => _onMessage(socket!, message),
        onError: (_) => _handleLoss(socket!),
        onDone: () => _handleLoss(socket!),
        cancelOnError: true,
      );
      _setState(MuxConnectionState.connected);
      for (final subscription in [..._subscriptions]) {
        if (subscription.isDisposed) continue;
        // 已结束/已失败的流不重开：重开会让服务端复活早已结束的等待
        // （如 attachWait），并把事件派发给上层已关闭的 controller。
        if (!subscription.autoReopen) continue;
        if (subscription.phase == MuxSubscriptionPhase.ended ||
            subscription.phase == MuxSubscriptionPhase.failed) {
          continue;
        }
        _sendOpen(subscription);
      }
    } catch (_) {
      if (_disposed) return;
      if (socket != null) {
        unawaited(socket.close(1000, 'connect failed'));
      }
      _socket = null;
      _setState(MuxConnectionState.waiting);
      _scheduleRetry();
    }
  }

  Uri _muxUri() {
    final scheme = origin.scheme == 'https' ? 'wss' : 'ws';
    return origin.replace(
      scheme: scheme,
      path: '/api/remote.mux',
      query: null,
      fragment: null,
    );
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) return;
    _attempt += 1;
    final delay = reconnectPolicy.delayFor(_attempt);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_disposed) unawaited(_connect());
    });
  }

  void _handleLoss(MuxSocket socket) {
    if (_disposed || !identical(_socket, socket)) return;
    _socket = null;
    _messageSubscription?.cancel();
    _messageSubscription = null;
    unawaited(socket.close(1000, 'closed'));
    _setState(MuxConnectionState.waiting);
    for (final subscription in [..._subscriptions]) {
      if (subscription.isDisposed) continue;
      subscription.markWaiting();
    }
    _scheduleRetry();
  }

  void _onMessage(MuxSocket socket, Object? message) {
    if (_disposed || !identical(_socket, socket)) return;
    final frame = decodeMuxServerFrame(message);
    if (frame == null) {
      _ignoredFrames += 1;
      return;
    }
    MuxSubscription? target;
    for (final subscription in _subscriptions) {
      if (subscription.streamId == frame.streamId) {
        target = subscription;
        break;
      }
    }
    if (target == null) return;
    switch (frame) {
      case MuxItemFrame():
        target.deliverItem(frame.value);
      case MuxEndFrame():
        target.deliverEnd();
      case MuxErrorFrame():
        target.deliverFailure(frame.error);
    }
  }

  void _sendOpen(MuxSubscription subscription) {
    final socket = _socket;
    if (_disposed || socket == null || _state != MuxConnectionState.connected) {
      subscription.phase = MuxSubscriptionPhase.waiting;
      return;
    }
    if (subscription.isDisposed) return;
    final streamId = newRpcId();
    try {
      socket.sendText(
        jsonEncode(
          encodeMuxOpen(
            streamId: streamId,
            endpoint: subscription.endpoint,
            payload: {'args': subscription.args},
          ),
        ),
      );
      subscription.bind(streamId);
    } catch (_) {
      _handleLoss(socket);
    }
  }

  void _cancelSubscription(MuxSubscription subscription) {
    _subscriptions.remove(subscription);
    final streamId = subscription.streamId;
    final socket = _socket;
    if (streamId == null || socket == null || _disposed) return;
    try {
      socket.sendText(jsonEncode(encodeMuxCancel(streamId)));
    } catch (_) {
      // 连接已断，取消帧无意义。
    }
  }

  void _restartSubscription(MuxSubscription subscription) {
    if (_disposed || subscription.isDisposed) return;
    final oldStreamId = subscription.streamId;
    final socket = _socket;
    if (oldStreamId != null && socket != null) {
      try {
        socket.sendText(jsonEncode(encodeMuxCancel(oldStreamId)));
      } catch (_) {
        // 连接已断，静默等待重连。
      }
    }
    subscription.prepareRestart();
    if (_state == MuxConnectionState.connected) {
      _sendOpen(subscription);
    }
  }

  void _setState(MuxConnectionState state) {
    if (_state == state) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
