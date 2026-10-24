import 'dart:async';

import '../services/dsh_api.dart';
import 'dsh_mux_client.dart';
import 'mux_socket.dart';
import 'reconnect_policy.dart';
import 'remote_events.dart';
import 'session_control_hub.dart';
import 'workspace_hub.dart';

/// 每服务器一套 mux 组合：一条物理连接 + 三条服务器级长活流。
///
/// 页面级 `session/follow` 直接使用 [client] 打开，不在这里持有。
class MuxHub {
  final DshApi api;
  final DshMuxClient client;
  late final RemoteEventsHub events;
  late final SessionControlHub control;
  late final WorkspaceHub workspace;

  final StreamController<MuxConnectionState> _connection =
      StreamController<MuxConnectionState>.broadcast(sync: true);
  StreamSubscription<MuxConnectionState>? _stateSubscription;
  bool _started = false;
  bool _disposed = false;

  MuxHub({
    required Uri origin,
    required this.api,
    required Future<String?> Function() tokenProvider,
    MuxSocketFactory socketFactory = connectIoMuxSocket,
    ReconnectPolicy reconnectPolicy = const ReconnectPolicy(),
  }) : client = DshMuxClient(
         origin: origin,
         tokenProvider: tokenProvider,
         socketFactory: socketFactory,
         reconnectPolicy: reconnectPolicy,
       ) {
    events = RemoteEventsHub(client, api);
    control = SessionControlHub(client);
    workspace = WorkspaceHub(client);
    _stateSubscription = client.states.listen((state) {
      if (!_connection.isClosed) _connection.add(state);
    });
  }

  MuxConnectionState get connection => client.state;

  Stream<MuxConnectionState> get connectionStates => _connection.stream;

  /// 启动长活流并建立连接（幂等）。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    events.start();
    control.start();
    workspace.start();
    client.ensureConnected();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stateSubscription?.cancel();
    _stateSubscription = null;
    events.dispose();
    control.dispose();
    workspace.dispose();
    client.dispose();
    unawaited(_connection.close());
  }
}
