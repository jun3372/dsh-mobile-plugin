import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dsh_mobile/core/mux/dsh_mux_client.dart';
import 'package:dsh_mobile/core/mux/mux_frame.dart';
import 'package:dsh_mobile/core/mux/mux_socket.dart';
import 'package:dsh_mobile/core/mux/mux_subscription.dart';
import 'package:dsh_mobile/core/mux/reconnect_policy.dart';
import 'package:dsh_mobile/core/mux/session_control_hub.dart';
import 'package:dsh_mobile/core/mux/workspace_hub.dart';
import 'package:dsh_mobile/core/session/session_follow_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('服务端帧解码', () {
    test('item 允许 value 缺省', () {
      final frame = decodeMuxServerFrame({'type': 'item', 'streamId': 's1'});
      expect(frame, isA<MuxItemFrame>());
      expect(frame!.streamId, 's1');
      expect((frame as MuxItemFrame).value, isNull);
    });

    test('item 保留任意 value 结构', () {
      final frame = decodeMuxServerFrame(
        jsonEncode({
          'type': 'item',
          'streamId': 's1',
          'value': {'type': 'snapshot', 'cursor': 3},
        }),
      );
      expect(frame, isA<MuxItemFrame>());
      expect((frame as MuxItemFrame).value, {'type': 'snapshot', 'cursor': 3});
    });

    test('end 与 error 严格校验', () {
      expect(
        decodeMuxServerFrame({'type': 'end', 'streamId': 's1'}),
        isA<MuxEndFrame>(),
      );
      final error = decodeMuxServerFrame({
        'type': 'error',
        'streamId': 's1',
        'error': {'code': 'gateway/cancelled', 'message': '取消'},
      });
      expect(error, isA<MuxErrorFrame>());
      expect((error as MuxErrorFrame).error.code, 'gateway/cancelled');
      expect(error.error.message, '取消');
    });

    test('未知/非法帧一律返回 null', () {
      expect(
        decodeMuxServerFrame({'type': 'opened', 'streamId': 's1'}),
        isNull,
      );
      expect(decodeMuxServerFrame({'type': 'item'}), isNull);
      expect(decodeMuxServerFrame({'type': 'item', 'streamId': ''}), isNull);
      expect(
        decodeMuxServerFrame({'type': 'item', 'streamId': 's1', 'extra': 1}),
        isNull,
      );
      expect(
        decodeMuxServerFrame({'type': 'end', 'streamId': 's1', 'value': 1}),
        isNull,
      );
      expect(
        decodeMuxServerFrame({
          'type': 'error',
          'streamId': 's1',
          'error': {'code': 'x'},
        }),
        isNull,
      );
      expect(decodeMuxServerFrame('not json'), isNull);
      expect(decodeMuxServerFrame(42), isNull);
      expect(decodeMuxServerFrame('<html>'), isNull);
    });
  });

  group('客户端帧编码', () {
    test('open 携带 endpoint 与 args 外壳', () {
      expect(
        encodeMuxOpen(
          streamId: 'abc',
          endpoint: 'session/follow',
          payload: {
            'args': {'request': 1},
          },
        ),
        {
          'type': 'open',
          'streamId': 'abc',
          'endpoint': 'session/follow',
          'payload': {
            'args': {'request': 1},
          },
        },
      );
    });

    test('cancel 只带 streamId', () {
      expect(encodeMuxCancel('abc'), {'type': 'cancel', 'streamId': 'abc'});
    });
  });

  group('重连退避', () {
    test('指数增长并封顶', () {
      const policy = ReconnectPolicy();
      final steady = _FixedRandom(0.5);
      expect(policy.delayFor(1, random: steady).inMilliseconds, 500);
      expect(policy.delayFor(2, random: steady).inMilliseconds, 1000);
      expect(policy.delayFor(3, random: steady).inMilliseconds, 2000);
      expect(policy.delayFor(4, random: steady).inMilliseconds, 4000);
      expect(policy.delayFor(5, random: steady).inMilliseconds, 8000);
      expect(policy.delayFor(6, random: steady).inMilliseconds, 10000);
      expect(policy.delayFor(20, random: steady).inMilliseconds, 10000);
    });

    test('±20% 抖动且不会为零', () {
      const policy = ReconnectPolicy();
      expect(policy.delayFor(1, random: _FixedRandom(0)).inMilliseconds, 400);
      expect(policy.delayFor(1, random: _FixedRandom(1)).inMilliseconds, 600);
      expect(
        policy.delayFor(10, random: _FixedRandom(1)).inMilliseconds,
        12000,
      );
    });
  });

  group('DshMuxClient', () {
    test('连接、打开流、路由 item、掉线后新 streamId 重开、释放发送 cancel', () async {
      final sockets = <_FakeMuxSocket>[];
      Uri? connectedUri;
      String? connectedToken;
      final client = DshMuxClient(
        origin: Uri.parse('https://host:39081'),
        tokenProvider: () async => 'secret-token',
        socketFactory: (uri, token) async {
          connectedUri = uri;
          connectedToken = token;
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

      final subscription = client.openStream(
        'session/follow',
        args: {
          'request': {
            'address': {'kind': 'session', 'sessionId': 's1'},
          },
        },
      );
      final events = <MuxStreamEvent>[];
      subscription.events.listen(events.add);

      await _waitFor(
        () =>
            sockets.length == 1 && client.state == MuxConnectionState.connected,
      );
      expect(connectedUri.toString(), 'wss://host:39081/api/remote.mux');
      expect(connectedToken, 'secret-token');

      final firstOpen = sockets[0].frames.singleWhere(
        (frame) => frame['type'] == 'open',
      );
      final firstStreamId = firstOpen['streamId'] as String;
      expect(firstOpen['endpoint'], 'session/follow');
      expect(firstOpen['payload'], {
        'args': {
          'request': {
            'address': {'kind': 'session', 'sessionId': 's1'},
          },
        },
      });
      expect(firstStreamId, isNotEmpty);
      expect(subscription.streamId, firstStreamId);
      expect(events.whereType<MuxStreamOpened>().single.restarted, isFalse);

      sockets[0].push({
        'type': 'item',
        'streamId': firstStreamId,
        'value': {'type': 'snapshot'},
      });
      await _waitFor(() => events.whereType<MuxStreamItem>().isNotEmpty);

      sockets[0].push({'type': 'future-frame', 'streamId': firstStreamId});
      await _waitFor(() => client.ignoredFrames == 1);

      sockets[0].drop();
      await _waitFor(() => client.state == MuxConnectionState.waiting);
      await _waitFor(() => sockets.length == 2);
      await _waitFor(() => client.state == MuxConnectionState.connected);

      final secondOpen = sockets[1].frames.lastWhere(
        (frame) => frame['type'] == 'open',
      );
      final secondStreamId = secondOpen['streamId'] as String;
      expect(secondStreamId, isNot(firstStreamId));
      expect(subscription.streamId, secondStreamId);
      expect(events.whereType<MuxStreamOpened>().last.restarted, isTrue);

      subscription.dispose();
      expect(sockets[1].frames.last, {
        'type': 'cancel',
        'streamId': secondStreamId,
      });
    });

    test('连接尚未建立时可以登记多条流，连上后逐条 open', () async {
      final sockets = <_FakeMuxSocket>[];
      final client = DshMuxClient(
        origin: Uri.parse('http://127.0.0.1:39081'),
        tokenProvider: () async => 't',
        socketFactory: (uri, token) async {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(client.dispose);

      final a = client.openStream('session/control');
      final b = client.openStream('workspace/follow');
      await _waitFor(
        () =>
            sockets.length == 1 && client.state == MuxConnectionState.connected,
      );

      final opens = sockets[0].frames
          .where((frame) => frame['type'] == 'open')
          .toList();
      expect(opens, hasLength(2));
      expect(
        opens.map((frame) => frame['endpoint']),
        containsAll(['session/control', 'workspace/follow']),
      );
      expect(a.streamId, isNotNull);
      expect(b.streamId, isNotNull);
      expect(a.streamId, isNot(b.streamId));
      expect(
        sockets[0].frames.every((frame) => frame['streamId'] != null),
        isTrue,
      );
    });

    test('服务端 error 帧投递失败并解除订阅', () async {
      final sockets = <_FakeMuxSocket>[];
      final client = DshMuxClient(
        origin: Uri.parse('http://127.0.0.1:39081'),
        tokenProvider: () async => 't',
        socketFactory: (uri, token) async {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(client.dispose);

      final subscription = client.openStream('session/follow');
      final events = <MuxStreamEvent>[];
      subscription.events.listen(events.add);
      await _waitFor(() => client.state == MuxConnectionState.connected);

      sockets[0].push({
        'type': 'error',
        'streamId': subscription.streamId,
        'error': {'code': 'session/not-found', 'message': 'gone'},
      });
      await _waitFor(() => events.whereType<MuxStreamFailure>().isNotEmpty);
      expect(subscription.phase, MuxSubscriptionPhase.failed);
    });
  });

  group('SessionFollowClient', () {
    test('snapshot/event 透传，assistant 修订号断档自动重开', () async {
      final sockets = <_FakeMuxSocket>[];
      final client = DshMuxClient(
        origin: Uri.parse('http://127.0.0.1:39081'),
        tokenProvider: () async => 't',
        socketFactory: (uri, token) async {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(client.dispose);
      final frames = <FollowFrame>[];
      final follow = SessionFollowClient(
        client: client,
        sessionId: 's1',
        onFrame: frames.add,
      );
      addTearDown(follow.dispose);
      follow.start();

      await _waitFor(() => client.state == MuxConnectionState.connected);
      final firstOpen = sockets[0].frames.singleWhere(
        (frame) => frame['type'] == 'open',
      );
      expect(firstOpen['endpoint'], 'session/follow');
      expect(firstOpen['payload'], {
        'args': {
          'request': {
            'address': {'kind': 'session', 'sessionId': 's1'},
            'assistantStream': true,
            'maxMessages': 500,
            'turnWindow': {'minMessages': 50, 'minTurns': 2},
          },
        },
      });
      final firstStreamId = firstOpen['streamId'] as String;

      sockets[0].push({
        'type': 'item',
        'streamId': firstStreamId,
        'value': {
          'type': 'snapshot',
          'header': {'cwd': '/tmp'},
          'cursor': 2,
          'records': [
            {
              'type': 'event',
              'event': {
                'type': 'user/message',
                'seq': 2,
                'time': 1,
                'data': {
                  'turn': 1,
                  'content': [
                    {'type': 'text', 'text': '你好'},
                  ],
                  'source': {'kind': 'user', 'rpcId': 'r1'},
                },
              },
            },
          ],
          'hasMore': false,
          'projections': {
            'asOfSeq': 2,
            'values': {'title': '标题'},
          },
          'assistantStream': {'revision': 3},
        },
      });
      await _waitFor(() => frames.whereType<FollowSnapshot>().isNotEmpty);
      final snapshot = frames.whereType<FollowSnapshot>().single;
      expect(snapshot.cursor, 2);
      expect(snapshot.projectionsAsOfSeq, 2);
      expect(snapshot.projections['title'], '标题');
      expect(snapshot.records.single.type, 'user/message');
      expect(snapshot.records.single.seq, 2);

      sockets[0].push({
        'type': 'item',
        'streamId': firstStreamId,
        'value': {
          'type': 'event',
          'event': {
            'type': 'assistant/message',
            'seq': 3,
            'time': 2,
            'data': {
              'turn': 1,
              'step': 0,
              'message': {
                'content': [
                  {'type': 'text', 'text': '回复'},
                ],
              },
            },
          },
        },
      });
      await _waitFor(() => frames.whereType<FollowEvent>().isNotEmpty);
      expect(frames.whereType<FollowEvent>().single.event.seq, 3);

      // 修订号必须逐帧 +1；断档不允许客户端补洞，只能重开流。
      sockets[0].push({
        'type': 'item',
        'streamId': firstStreamId,
        'value': {
          'type': 'assistant-stream',
          'frame': {'type': 'start', 'attemptId': 'a1', 'revision': 5},
        },
      });
      await _waitFor(
        () => sockets[0].frames.any((frame) => frame['type'] == 'cancel'),
      );
      expect(
        sockets[0].frames.singleWhere((frame) => frame['type'] == 'cancel'),
        {'type': 'cancel', 'streamId': firstStreamId},
      );
      final secondOpen = sockets[0].frames.lastWhere(
        (frame) => frame['type'] == 'open',
      );
      expect(secondOpen['streamId'], isNot(firstStreamId));
      await _waitFor(
        () =>
            frames.whereType<FollowOpened>().any((opened) => opened.restarted),
      );
    });

    test('会话流 error 帧透出失败并安排重开', () async {
      final sockets = <_FakeMuxSocket>[];
      final client = DshMuxClient(
        origin: Uri.parse('http://127.0.0.1:39081'),
        tokenProvider: () async => 't',
        socketFactory: (uri, token) async {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(client.dispose);
      final frames = <FollowFrame>[];
      final follow = SessionFollowClient(
        client: client,
        sessionId: 's1',
        onFrame: frames.add,
      );
      addTearDown(follow.dispose);
      follow.start();

      await _waitFor(() => client.state == MuxConnectionState.connected);
      final streamId = sockets[0].frames.singleWhere(
        (frame) => frame['type'] == 'open',
      )['streamId'];
      sockets[0].push({
        'type': 'error',
        'streamId': streamId,
        'error': {'code': 'gateway/internal', 'message': 'boom'},
      });
      await _waitFor(() => frames.whereType<FollowFailure>().isNotEmpty);
      expect(
        frames.whereType<FollowFailure>().single.error.code,
        'gateway/internal',
      );
      // 失败后 800ms 重开同一条逻辑流。
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(
        sockets[0].frames.where((frame) => frame['type'] == 'open').length,
        2,
      );
    });
  });

  group('SessionControlHub', () {
    test('baseline 建水位，逐键只接受更高 seq', () async {
      final sockets = <_FakeMuxSocket>[];
      final client = DshMuxClient(
        origin: Uri.parse('http://127.0.0.1:39081'),
        tokenProvider: () async => 't',
        socketFactory: (uri, token) async {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(client.dispose);
      final hub = SessionControlHub(client);
      addTearDown(hub.dispose);
      final changes = <String>[];
      hub.changes.listen(changes.add);
      hub.start();

      await _waitFor(() => client.state == MuxConnectionState.connected);
      final streamId = sockets[0].frames.singleWhere(
        (frame) => frame['type'] == 'open',
      )['streamId'];
      expect(streamId, isNotNull);

      sockets[0].push({
        'type': 'item',
        'streamId': streamId,
        'value': {
          'type': 'baseline',
          'value': {
            'projections': {
              's1': {
                'asOfSeq': 5,
                'values': {'title': '旧标题', 'running': false},
              },
            },
          },
        },
      });
      await _waitFor(() => hub.store.valuesOf('s1') != null);
      expect(hub.store.valuesOf('s1')!['title'], '旧标题');
      expect(changes, ['']);

      sockets[0].push({
        'type': 'item',
        'streamId': streamId,
        'value': {
          'type': 'projection',
          'sessionId': 's1',
          'key': 'title',
          'value': '同水位应忽略',
          'seq': 5,
        },
      });
      await _pump();
      expect(hub.store.valuesOf('s1')!['title'], '旧标题');

      sockets[0].push({
        'type': 'item',
        'streamId': streamId,
        'value': {
          'type': 'projection',
          'sessionId': 's1',
          'key': 'title',
          'value': '新标题',
          'seq': 6,
        },
      });
      await _waitFor(() => hub.store.valuesOf('s1')!['title'] == '新标题');
      expect(changes, ['', 's1']);
      expect(hub.store.asOfSeqOf('s1'), 6);
    });
  });

  group('WorkspaceHub', () {
    test('baseline 替换集合，增量 upsert/order/archived/remove', () async {
      final sockets = <_FakeMuxSocket>[];
      final client = DshMuxClient(
        origin: Uri.parse('http://127.0.0.1:39081'),
        tokenProvider: () async => 't',
        socketFactory: (uri, token) async {
          final socket = _FakeMuxSocket();
          sockets.add(socket);
          return socket;
        },
      );
      addTearDown(client.dispose);
      final hub = WorkspaceHub(client);
      addTearDown(hub.dispose);
      hub.start();

      await _waitFor(() => client.state == MuxConnectionState.connected);
      final streamId = sockets[0].frames.singleWhere(
        (frame) => frame['type'] == 'open',
      )['streamId'];

      void send(Map<String, Object?> value) {
        sockets[0].push({'type': 'item', 'streamId': streamId, 'value': value});
      }

      send({
        'type': 'baseline',
        'value': {
          'items': [
            {
              'workspaceId': 'w1',
              'path': '/a',
              'title': 'A',
              'sessionIds': ['s1', 's2'],
              'createdAt': '2026-10-01T00:00:00.000Z',
              'updatedAt': '2026-10-02T00:00:00.000Z',
            },
            {
              'workspaceId': 'w2',
              'path': '/b',
              'title': 'B',
              'sessionIds': ['s3'],
              'createdAt': '2026-10-01T00:00:00.000Z',
              'updatedAt': '2026-10-02T00:00:00.000Z',
            },
          ],
          'archivedSessionIds': ['s2'],
        },
      });
      await _waitFor(() => hub.hasBaseline);
      expect(hub.items, hasLength(2));
      expect(hub.items.first.updatedAt, '2026-10-02T00:00:00.000Z');
      expect(hub.archivedSet, {'s2'});
      expect(hub.orderedSessionIds, ['s1', 's2', 's3']);

      send({
        'type': 'upsert',
        'workspace': {
          'workspaceId': 'w3',
          'path': '/c',
          'title': 'C',
          'sessionIds': ['s4'],
          'createdAt': '2026-10-01T00:00:00.000Z',
          'updatedAt': '2026-10-02T00:00:00.000Z',
        },
      });
      await _waitFor(() => hub.items.length == 3);
      expect(hub.orderedSessionIds, contains('s4'));

      send({
        'type': 'order',
        'workspaceIds': ['w3', 'w2', 'w1'],
      });
      await _pump();
      expect(hub.items.first.workspaceId, 'w1');
      expect(hub.orderedSessionIds, ['s4', 's3', 's1', 's2']);

      send({
        'type': 'archived',
        'archivedSessionIds': ['s1'],
      });
      await _pump();
      expect(hub.archivedSet, {'s1'});

      send({'type': 'remove', 'workspaceId': 'w3'});
      await _pump();
      expect(hub.items, hasLength(2));
      expect(hub.orderedSessionIds, isNot(contains('s4')));
    });
  });
}

/// 同步微任务推进，避免测试依赖真实延迟。
Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitFor(bool Function() predicate, {int attempts = 200}) async {
  for (var i = 0; i < attempts; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('等待条件超时');
}

class _FixedRandom implements Random {
  final double value;

  _FixedRandom(this.value);

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
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
