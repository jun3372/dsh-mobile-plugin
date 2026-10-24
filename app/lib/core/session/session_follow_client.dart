import 'dart:async';

import '../mux/dsh_mux_client.dart';
import '../mux/mux_error.dart';
import '../mux/mux_subscription.dart';
import '../models/session_event.dart';

sealed class FollowFrame {
  const FollowFrame();
}

/// 一次完整的 follow 窗口（首帧或断线重连后的新基线）。
class FollowSnapshot extends FollowFrame {
  final Map<String, Object?> header;
  final int cursor;
  final List<SessionWireEvent> records;
  final bool hasMore;
  final int projectionsAsOfSeq;
  final Map<String, Object?> projections;
  final Object? assistantStream;

  const FollowSnapshot({
    required this.header,
    required this.cursor,
    required this.records,
    required this.hasMore,
    required this.projectionsAsOfSeq,
    required this.projections,
    required this.assistantStream,
  });
}

class FollowEvent extends FollowFrame {
  final SessionWireEvent event;

  const FollowEvent(this.event);
}

class FollowAssistantFrame extends FollowFrame {
  final Map<String, Object?> frame;

  const FollowAssistantFrame(this.frame);
}

/// 连接层断开，等待重连；旧窗口仍可展示。
class FollowWaiting extends FollowFrame {
  const FollowWaiting();
}

class FollowOpened extends FollowFrame {
  final bool restarted;

  const FollowOpened({required this.restarted});
}

class FollowFailure extends FollowFrame {
  final MuxError error;

  const FollowFailure(this.error);
}

/// `session/follow` 的轻客户端：open → snapshot → event / assistant-stream。
///
/// 没有 cursor 续传：断线重连自动重开并先收到新的 snapshot，交由上层整体替换。
class SessionFollowClient {
  static const defaultMaxMessages = 500;
  static const defaultTurnWindow = <String, Object?>{
    'minMessages': 50,
    'minTurns': 2,
  };

  final DshMuxClient _client;
  final String sessionId;
  final int maxMessages;
  final Map<String, Object?> turnWindow;
  final void Function(FollowFrame frame) _onFrame;

  MuxSubscription? _subscription;
  StreamSubscription<MuxStreamEvent>? _events;
  Timer? _retryTimer;
  bool _disposed = false;
  int _assistantRevision = 0;

  SessionFollowClient({
    required DshMuxClient client,
    required this.sessionId,
    required void Function(FollowFrame frame) onFrame,
    this.maxMessages = defaultMaxMessages,
    this.turnWindow = defaultTurnWindow,
  }) : _client = client,
       _onFrame = onFrame;

  void start() {
    if (_disposed || _subscription != null) return;
    _open();
  }

  /// 折叠违约或需要新基线时主动重开。
  void restart() {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    final subscription = _subscription;
    if (subscription == null || subscription.isDisposed) {
      _open();
      return;
    }
    subscription.restart();
  }

  void _open() {
    if (_disposed) return;
    final subscription = _client.openStream(
      'session/follow',
      args: {
        'request': {
          'address': {'kind': 'session', 'sessionId': sessionId},
          'assistantStream': true,
          'maxMessages': maxMessages,
          'turnWindow': turnWindow,
        },
      },
    );
    _subscription = subscription;
    _events = subscription.events.listen(_onEvent);
  }

  void _onEvent(MuxStreamEvent event) {
    if (_disposed) return;
    switch (event) {
      case MuxStreamOpened(:final restarted):
        _emit(FollowOpened(restarted: restarted));
      case MuxStreamItem():
        _onItem(event.value);
      case MuxStreamCarrierLost():
        _emit(const FollowWaiting());
      case MuxStreamFailure(:final error):
        _emit(FollowFailure(error));
        _scheduleRestart();
      case MuxStreamEnded():
        _emit(const FollowWaiting());
        _scheduleRestart();
    }
  }

  void _onItem(Object? value) {
    if (value is! Map) return;
    switch (value['type']) {
      case 'snapshot':
        final header = value['header'];
        final cursor = value['cursor'];
        final projections = value['projections'];
        if (cursor is! num || projections is! Map) return;
        final assistantStream = value['assistantStream'];
        _assistantRevision = assistantStream is Map
            ? (assistantStream['revision'] as num?)?.toInt() ?? 0
            : 0;
        _emit(
          FollowSnapshot(
            header: header is Map
                ? Map<String, Object?>.from(header)
                : const {},
            cursor: cursor.toInt(),
            records: SessionWireEvent.fromRecords(value['records']),
            hasMore: value['hasMore'] == true,
            projectionsAsOfSeq: (projections['asOfSeq'] as num?)?.toInt() ?? 0,
            projections: projections['values'] is Map
                ? Map<String, Object?>.from(projections['values'] as Map)
                : const {},
            assistantStream: assistantStream,
          ),
        );
      case 'event':
        final parsed = SessionWireEvent.fromRecord(value);
        if (parsed != null) _emit(FollowEvent(parsed));
      case 'assistant-stream':
        final frame = value['frame'];
        if (frame is! Map) return;
        final revision = (frame['revision'] as num?)?.toInt();
        if (revision == null || revision != _assistantRevision + 1) {
          // 修订号断档只能换新基线，不在客户端补洞。
          restart();
          return;
        }
        _assistantRevision = revision;
        _emit(FollowAssistantFrame(Map<String, Object?>.from(frame)));
      default:
        return;
    }
  }

  void _emit(FollowFrame frame) {
    if (_disposed) return;
    _onFrame(frame);
  }

  void _scheduleRestart() {
    if (_disposed || _retryTimer != null) return;
    _retryTimer = Timer(const Duration(milliseconds: 800), () {
      _retryTimer = null;
      if (!_disposed) restart();
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _events?.cancel();
    _events = null;
    _subscription?.dispose();
    _subscription = null;
  }
}
