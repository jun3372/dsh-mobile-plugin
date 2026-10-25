import 'dart:async';

import '../models/approval_request.dart';
import '../models/dsh_models.dart';
import '../services/dsh_api.dart';
import 'dsh_mux_client.dart';
import 'mux_subscription.dart';

/// `$events` waterfall 中的一条用户提问。
class RemoteQuestionRequest {
  final String eventId;
  final String agentId;
  final String? callId;

  /// 宿主侧带超时的前台等待（`ask_user_question` 限时提问）。
  final bool timedWait;
  final List<UserQuestion> questions;

  const RemoteQuestionRequest({
    required this.eventId,
    required this.agentId,
    required this.callId,
    required this.questions,
    this.timedWait = false,
  });

  static RemoteQuestionRequest? fromInvocation({
    required String eventId,
    required String agentId,
    required Object? request,
  }) {
    if (request is! Map) return null;
    final rawQuestions = request['questions'];
    if (rawQuestions is! List) return null;
    final questions = rawQuestions
        .whereType<Map>()
        .map((json) => UserQuestion.fromJson(Map<String, dynamic>.from(json)))
        .toList();
    if (questions.isEmpty) return null;
    final wait = request['wait'];
    final callId = wait is Map
        ? wait['callId'] as String?
        : request['callId'] as String?;
    return RemoteQuestionRequest(
      eventId: eventId,
      agentId: agentId,
      callId: callId,
      questions: questions,
      timedWait: wait is Map && wait['timed'] == true,
    );
  }
}

/// `$events` 转发的会话列表信号。
sealed class RemoteSessionSignal {
  const RemoteSessionSignal();
}

class RemoteSessionAdded extends RemoteSessionSignal {
  final Map<String, Object?> summary;

  const RemoteSessionAdded(this.summary);
}

class RemoteSessionRemoved extends RemoteSessionSignal {
  final String sessionId;

  const RemoteSessionRemoved(this.sessionId);
}

class RemoteSessionStatus extends RemoteSessionSignal {
  final String sessionId;
  final bool running;

  const RemoteSessionStatus(this.sessionId, this.running);
}

class RemoteSessionError extends RemoteSessionSignal {
  final String sessionId;
  final String message;

  const RemoteSessionError(this.sessionId, this.message);
}

class RemoteSessionActivity extends RemoteSessionSignal {
  final String sessionId;
  final int time;

  const RemoteSessionActivity(this.sessionId, this.time);
}

/// 服务器级 `$events`：审批、用户提问 waterfall，以及会话列表信号。
class RemoteEventsHub {
  final DshMuxClient _client;
  final DshApi _api;

  final StreamController<List<ApprovalRequest>> _approvalsChanged =
      StreamController<List<ApprovalRequest>>.broadcast(sync: true);
  final StreamController<List<RemoteQuestionRequest>> _questionsChanged =
      StreamController<List<RemoteQuestionRequest>>.broadcast(sync: true);
  final StreamController<RemoteSessionSignal> _sessionSignals =
      StreamController<RemoteSessionSignal>.broadcast(sync: true);
  final StreamController<void> _reconnected = StreamController<void>.broadcast(
    sync: true,
  );

  final Map<String, ApprovalRequest> _approvals = {};
  final Map<String, RemoteQuestionRequest> _questions = {};

  MuxSubscription? _subscription;
  StreamSubscription<MuxStreamEvent>? _events;
  String? _clientId;
  String? _home;
  bool _started = false;
  bool _disposed = false;

  RemoteEventsHub(this._client, this._api);

  Stream<List<ApprovalRequest>> get approvals => _approvalsChanged.stream;

  Stream<List<RemoteQuestionRequest>> get questions => _questionsChanged.stream;

  Stream<RemoteSessionSignal> get sessionSignals => _sessionSignals.stream;

  /// 重连并拿到新 generation 后触发。
  Stream<void> get reconnected => _reconnected.stream;

  String? get clientId => _clientId;

  String? get home => _home;

  List<ApprovalRequest> get pendingApprovals =>
      List.unmodifiable(_approvals.values);

  List<RemoteQuestionRequest> get pendingQuestions =>
      List.unmodifiable(_questions.values);

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _subscription = _client.openStream(
      '\$events',
      args: const <String, Object?>{},
    );
    _events = _subscription!.events.listen(_onEvent);
  }

  void _onEvent(MuxStreamEvent event) {
    switch (event) {
      case MuxStreamOpened(:final restarted):
        _clientId = null;
        _approvals.clear();
        _questions.clear();
        _emitPending();
        if (restarted && !_reconnected.isClosed) _reconnected.add(null);
      case MuxStreamItem():
        _onItem(event.value);
      case MuxStreamFailure():
      case MuxStreamEnded():
      case MuxStreamCarrierLost():
        break;
    }
  }

  void _onItem(Object? value) {
    if (value is! Map) return;
    final type = value['type'];
    if (type == 'ready') {
      _clientId = value['clientId'] as String?;
      final host = value['host'];
      _home = host is Map ? host['home'] as String? : null;
      return;
    }
    if (type == 'cancel') {
      final eventId = value['eventId'];
      if (eventId is String) _removePending(eventId);
      return;
    }
    if (type == 'waterfall') {
      _onWaterfall(value);
      return;
    }
    if (type == 'emit') {
      _onEmit(value);
    }
  }

  void _onWaterfall(Map value) {
    final event = value['event'];
    final eventId = value['eventId'];
    final agentId = value['agentId'];
    if (event is! String || eventId is! String || agentId is! String) return;
    if (event == 'approval/request') {
      final approval = ApprovalRequest.fromInvocation(
        eventId: eventId,
        agentId: agentId,
        request: value['request'],
      );
      if (approval == null) return;
      _approvals[eventId] = approval;
      if (!_approvalsChanged.isClosed) {
        _approvalsChanged.add(List.unmodifiable(_approvals.values));
      }
      return;
    }
    if (event == 'user-questions/request') {
      final questions = RemoteQuestionRequest.fromInvocation(
        eventId: eventId,
        agentId: agentId,
        request: value['request'],
      );
      if (questions == null) return;
      _questions[eventId] = questions;
      if (!_questionsChanged.isClosed) {
        _questionsChanged.add(List.unmodifiable(_questions.values));
      }
    }
  }

  void _onEmit(Map value) {
    final event = value['event'];
    final args = value['args'];
    if (event is! String || args is! List) return;
    RemoteSessionSignal? signal;
    switch (event) {
      case 'api-session/added':
        if (args.isNotEmpty && args.first is Map) {
          signal = RemoteSessionAdded(
            Map<String, Object?>.from(args.first as Map),
          );
        }
      case 'api-session/removed':
        if (args.isNotEmpty && args.first is String) {
          signal = RemoteSessionRemoved(args.first as String);
        }
      case 'api-session/status':
        if (args.length >= 2 && args[0] is String && args[1] is bool) {
          signal = RemoteSessionStatus(args[0] as String, args[1] as bool);
        }
      case 'api-session/error':
        if (args.length >= 2 && args[0] is String) {
          signal = RemoteSessionError(args[0] as String, '${args[1]}');
        }
      case 'api-session/activity':
        if (args.length >= 2 && args[0] is String && args[1] is num) {
          signal = RemoteSessionActivity(
            args[0] as String,
            (args[1] as num).toInt(),
          );
        }
      default:
        return;
    }
    if (signal != null && !_sessionSignals.isClosed) {
      _sessionSignals.add(signal);
    }
  }

  Future<void> answerApproval(String eventId, {required bool allowed}) async {
    final clientId = _clientId;
    if (clientId == null) {
      throw StateError('事件流尚未就绪');
    }
    await _api.eventsResult(
      clientId: clientId,
      eventId: eventId,
      outcome: {
        'kind': 'result',
        'value': allowed ? 'allowed-once' : 'rejected',
      },
    );
    _removePending(eventId);
  }

  Future<void> answerQuestions(
    String eventId,
    List<QuestionAnswer> answers,
  ) async {
    final clientId = _clientId;
    if (clientId == null) {
      throw StateError('事件流尚未就绪');
    }
    await _api.eventsResult(
      clientId: clientId,
      eventId: eventId,
      outcome: {
        'kind': 'result',
        'value': {
          'answers': [
            for (final answer in answers)
              {
                'id': answer.questionId,
                'selected': answer.selected,
                if (answer.custom != null && answer.custom!.isNotEmpty)
                  'custom': answer.custom,
              },
          ],
        },
      },
    );
    _removePending(eventId);
  }

  /// 以错误码拒绝一次 waterfall（限时提问超时用 `ASK_TIMED_OUT`）。
  Future<void> rejectQuestion(String eventId, String code) async {
    final clientId = _clientId;
    if (clientId == null) {
      throw StateError('事件流尚未就绪');
    }
    await _api.eventsResult(
      clientId: clientId,
      eventId: eventId,
      outcome: {
        'kind': 'rejected',
        'error': {
          'name': 'UserQuestionError',
          'code': code,
          'message': code == 'ASK_TIMED_OUT'
              ? 'ask_user_question timed out before the user answered'
              : code,
        },
      },
    );
    _removePending(eventId);
  }

  /// 订阅一条限时提问的剩余等待（`userQuestions/attachWait`，帧为毫秒数）。
  /// 流关闭表示等待已释放；取消订阅会释放客户端的 claim。
  Stream<Object?> attachWait({
    required String agentId,
    required String callId,
  }) {
    final subscription = _client.openStream(
      'userQuestions/attachWait',
      args: {'agentId': agentId, 'callId': callId},
      autoReopen: false,
    );
    late final StreamController<Object?> controller;
    StreamSubscription<MuxStreamEvent>? events;

    // 终态：关闭对外流、解除 mux 事件监听并 dispose 订阅（释放服务端 claim）。
    // 不做终态清理的话，物理重连会把已 ended 的订阅强制重开，
    // 之后的事件会派发给这里已关闭的 controller（StateError）。
    void settle() {
      if (!controller.isClosed) unawaited(controller.close());
      unawaited(events?.cancel());
      subscription.dispose();
    }

    controller = StreamController<Object?>(
      onListen: () {
        events = subscription.events.listen((event) {
          switch (event) {
            case MuxStreamItem(:final value):
              controller.add(value);
            case MuxStreamEnded():
              settle();
            case MuxStreamFailure(:final error):
              controller.addError(StateError(error.message));
              settle();
            case MuxStreamOpened():
            case MuxStreamCarrierLost():
              break;
          }
        });
      },
      onCancel: () {
        unawaited(events?.cancel());
        subscription.dispose();
      },
    );
    return controller.stream;
  }

  void _removePending(String eventId) {
    final removedApproval = _approvals.remove(eventId) != null;
    final removedQuestion = _questions.remove(eventId) != null;
    _emitPending(approvals: removedApproval, questions: removedQuestion);
  }

  void _emitPending({bool approvals = true, bool questions = true}) {
    if (approvals && !_approvalsChanged.isClosed) {
      _approvalsChanged.add(List.unmodifiable(_approvals.values));
    }
    if (questions && !_questionsChanged.isClosed) {
      _questionsChanged.add(List.unmodifiable(_questions.values));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events?.cancel();
    _events = null;
    _subscription?.dispose();
    _subscription = null;
    unawaited(_approvalsChanged.close());
    unawaited(_questionsChanged.close());
    unawaited(_sessionSignals.close());
    unawaited(_reconnected.close());
  }
}
