import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// mux 物理连接抽象（便于单测注入假 WebSocket）。
abstract interface class MuxSocket {
  /// 文本帧（已解码为 JSON 友好的对象）；非法 JSON 以 String 原样发出。
  Stream<Object?> get messages;

  Future<void> get done;

  void sendText(String text);

  Future<void> close([int code = 1000, String reason = '']);
}

typedef MuxSocketFactory =
    Future<MuxSocket> Function(Uri uri, String bearerToken);

const _connectTimeout = Duration(seconds: 10);

/// 用 dart:io 建立 `/api/remote.mux`；ping/pong 与重连由连接层负责。
Future<MuxSocket> connectIoMuxSocket(Uri uri, String bearerToken) async {
  final socket = await WebSocket.connect(
    uri.toString(),
    headers: {'authorization': 'Bearer $bearerToken'},
  ).timeout(_connectTimeout);
  socket.pingInterval = const Duration(seconds: 20);
  return IoMuxSocket(socket);
}

class IoMuxSocket implements MuxSocket {
  final WebSocket _socket;
  final StreamController<Object?> _messages =
      StreamController<Object?>.broadcast();

  IoMuxSocket(this._socket) {
    _socket.listen(
      (data) {
        if (data is String) {
          try {
            _messages.add(jsonDecode(data));
          } on FormatException {
            _messages.add(data);
          }
        } else if (data is List<int>) {
          try {
            _messages.add(jsonDecode(utf8.decode(data)));
          } on FormatException {
            // 二进制帧不属于 mux 协议，忽略。
          }
        }
      },
      onError: _messages.addError,
      onDone: _messages.close,
    );
  }

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> get done => _socket.done;

  @override
  void sendText(String text) => _socket.add(text);

  @override
  Future<void> close([int code = 1000, String reason = '']) async {
    await _socket.close(code, reason);
  }
}
