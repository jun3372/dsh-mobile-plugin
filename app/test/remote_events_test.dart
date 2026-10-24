import 'dart:async';
import 'dart:convert';

import 'package:dsh_mobile/core/mux/dsh_mux_client.dart';
import 'package:dsh_mobile/core/mux/mux_socket.dart';
import 'package:dsh_mobile/core/mux/reconnect_policy.dart';
import 'package:dsh_mobile/core/mux/remote_events.dart';
import 'package:dsh_mobile/core/services/api_client.dart';
import 'package:dsh_mobile/core/services/dsh_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('\$events：ready、审批/提问 waterfall、回填与 cancel', () async {
    final requests = <http.Request>[];
    final api = DshApi(
      ApiClient(
        origin: Uri.parse('http://host:39081'),
        password: 'pw',
        client: MockClient((request) async {
          if (request.url.path == '/_dsh_mobile/v1/login') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({'token': 't' * 43, 'expiresIn': 43200})),
              200,
            );
          }
          requests.add(request);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'type': 'server-response',
                'rpcId': 'x',
                'result': {'ok': true, 'value': null},
              }),
            ),
            200,
          );
        }),
      ),
    );

    final sockets = <_FakeMuxSocket>[];
    final client = DshMuxClient(
      origin: Uri.parse('http://host:39081'),
      tokenProvider: () async => 't',
      socketFactory: (uri, token) async {
        final socket = _FakeMuxSocket();
        sockets.add(socket);
        return socket;
      },
    );
    addTearDown(client.dispose);
    final hub = RemoteEventsHub(client, api);
    addTearDown(hub.dispose);
    final approvalChanges = <List<String>>[];
    final questionChanges = <List<String>>[];
    hub.approvals.listen(
      (items) => approvalChanges.add([for (final item in items) item.eventId]),
    );
    hub.questions.listen(
      (items) => questionChanges.add([for (final item in items) item.eventId]),
    );
    hub.start();

    await _waitFor(() => client.state == MuxConnectionState.connected);
    final streamId = sockets.last.frames.singleWhere(
      (frame) => frame['type'] == 'open',
    )['streamId'];

    void send(Map<String, Object?> value) {
      sockets.last.push({'type': 'item', 'streamId': streamId, 'value': value});
    }

    send({
      'type': 'ready',
      'clientId': 'client-1',
      'host': {'home': '/home/jun'},
    });
    await _waitFor(() => hub.clientId == 'client-1');
    expect(hub.home, '/home/jun');

    send({
      'type': 'waterfall',
      'event': 'approval/request',
      'eventId': 'ev-1',
      'agentId': 'agent-1',
      'request': {
        'toolName': 'bash',
        'callId': 'call-1',
        'reason': 'fallback reason',
        'displayReason': {'zh': '需要执行 ls', 'en': 'run ls'},
      },
    });
    await _waitFor(() => hub.pendingApprovals.isNotEmpty);
    final approval = hub.pendingApprovals.single;
    expect(approval.toolName, 'bash');
    expect(approval.callId, 'call-1');
    expect(approval.detail, '需要执行 ls');

    await hub.answerApproval('ev-1', allowed: true);
    expect(hub.pendingApprovals, isEmpty);
    final approvalBody = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(requests.last.url.path, '/api/\$events/result');
    expect(approvalBody['payload'], {
      'args': {
        'clientId': 'client-1',
        'eventId': 'ev-1',
        'outcome': {'kind': 'result', 'value': 'allowed-once'},
      },
    });

    send({
      'type': 'waterfall',
      'event': 'user-questions/request',
      'eventId': 'ev-2',
      'agentId': 'agent-1',
      'request': {
        'questions': [
          {
            'id': 'q1',
            'question': '继续吗？',
            'options': [
              {'label': '是'},
              {'label': '否'},
            ],
            'multiSelect': true,
          },
          {'id': 'q2', 'question': '补充说明？'},
        ],
        'wait': {'callId': 'call-2'},
      },
    });
    await _waitFor(() => hub.pendingQuestions.isNotEmpty);
    final question = hub.pendingQuestions.single;
    expect(question.eventId, 'ev-2');
    expect(question.callId, 'call-2');
    expect(question.questions, hasLength(2));
    expect(question.questions.first.multiSelect, isTrue);

    await hub.answerQuestions('ev-2', const [
      QuestionAnswer(questionId: 'q1', selected: ['是']),
      QuestionAnswer(questionId: 'q2', selected: [], custom: '补充'),
    ]);
    expect(hub.pendingQuestions, isEmpty);
    final questionBody = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(questionBody['payload'], {
      'args': {
        'clientId': 'client-1',
        'eventId': 'ev-2',
        'outcome': {
          'kind': 'result',
          'value': {
            'answers': [
              {
                'id': 'q1',
                'selected': ['是'],
              },
              {'id': 'q2', 'selected': <String>[], 'custom': '补充'},
            ],
          },
        },
      },
    });

    send({
      'type': 'waterfall',
      'event': 'approval/request',
      'eventId': 'ev-3',
      'agentId': 'agent-1',
      'request': {'toolName': 'write'},
    });
    await _waitFor(() => hub.pendingApprovals.isNotEmpty);
    expect(approvalChanges, isNotEmpty);
    send({'type': 'cancel', 'eventId': 'ev-3'});
    await _waitFor(() => hub.pendingApprovals.isEmpty);
    expect(questionChanges, isNotEmpty);
  });

  test('\$events 重连清空旧 waterfall，等待宿主重投', () async {
    final api = DshApi(
      ApiClient(
        origin: Uri.parse('http://host:39081'),
        password: 'pw',
        client: MockClient((request) async {
          if (request.url.path == '/_dsh_mobile/v1/login') {
            return http.Response.bytes(
              utf8.encode(jsonEncode({'token': 't' * 43, 'expiresIn': 43200})),
              200,
            );
          }
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'type': 'server-response',
                'rpcId': 'x',
                'result': {'ok': true, 'value': null},
              }),
            ),
            200,
          );
        }),
      ),
    );
    final sockets = <_FakeMuxSocket>[];
    final client = DshMuxClient(
      origin: Uri.parse('http://host:39081'),
      tokenProvider: () async => 't',
      socketFactory: (uri, token) async {
        final socket = _FakeMuxSocket();
        sockets.add(socket);
        return socket;
      },
      reconnectPolicy: const ReconnectPolicy(
        initial: Duration(milliseconds: 5),
        maximum: Duration(milliseconds: 20),
        jitter: 0,
      ),
    );
    addTearDown(client.dispose);
    final hub = RemoteEventsHub(client, api);
    addTearDown(hub.dispose);
    var reconnects = 0;
    hub.reconnected.listen((_) => reconnects += 1);
    hub.start();

    await _waitFor(() => client.state == MuxConnectionState.connected);
    var streamId = sockets.first.frames.singleWhere(
      (frame) => frame['type'] == 'open',
    )['streamId'];
    sockets.first.push({
      'type': 'item',
      'streamId': streamId,
      'value': {
        'type': 'ready',
        'clientId': 'client-1',
        'host': {'home': '/home/jun'},
      },
    });
    sockets.first.push({
      'type': 'item',
      'streamId': streamId,
      'value': {
        'type': 'waterfall',
        'event': 'approval/request',
        'eventId': 'ev-1',
        'agentId': 'agent-1',
        'request': {'toolName': 'bash'},
      },
    });
    await _waitFor(() => hub.pendingApprovals.isNotEmpty);

    sockets.first.drop();
    await _waitFor(() => sockets.length == 2);
    await _waitFor(() => client.state == MuxConnectionState.connected);
    await _waitFor(() => reconnects == 1);
    expect(hub.pendingApprovals, isEmpty);

    streamId = sockets.last.frames.lastWhere(
      (frame) => frame['type'] == 'open',
    )['streamId'];
    sockets.last.push({
      'type': 'item',
      'streamId': streamId,
      'value': {
        'type': 'waterfall',
        'event': 'approval/request',
        'eventId': 'ev-1',
        'agentId': 'agent-1',
        'request': {'toolName': 'bash'},
      },
    });
    await _waitFor(() => hub.pendingApprovals.isNotEmpty);
    expect(hub.pendingApprovals.single.eventId, 'ev-1');
  });
}

Future<void> _waitFor(bool Function() predicate, {int attempts = 200}) async {
  for (var i = 0; i < attempts; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('等待条件超时');
}

class _FakeMuxSocket implements MuxSocket {
  final StreamController<Object?> _messages =
      StreamController<Object?>.broadcast();
  final Completer<void> _done = Completer<void>();
  final List<Map<String, Object?>> frames = [];

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> get done => _done.future;

  @override
  void sendText(String text) {
    frames.add(Map<String, Object?>.from(jsonDecode(text) as Map));
  }

  void push(Object? message) {
    if (!_messages.isClosed) _messages.add(message);
  }

  void drop() {
    if (!_messages.isClosed) unawaited(_messages.close());
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> close([int code = 1000, String reason = '']) async {
    drop();
  }
}
