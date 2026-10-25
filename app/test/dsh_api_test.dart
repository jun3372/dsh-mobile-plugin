import 'dart:convert';

import 'package:dsh_mobile/core/models/composer_models.dart';
import 'package:dsh_mobile/core/models/session_event.dart';
import 'package:dsh_mobile/core/models/transcript_node.dart';
import 'package:dsh_mobile/core/models/workspace_file.dart';
import 'package:dsh_mobile/core/services/api_client.dart';
import 'package:dsh_mobile/core/services/dsh_api.dart';
import 'package:dsh_mobile/core/session/transcript_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> captured;

  DshApi apiWith(Future<http.Response> Function(http.Request) handler) {
    captured = [];
    return DshApi(
      ApiClient(
        origin: Uri.parse('http://host:39081'),
        password: 'pw',
        client: MockClient((request) async {
          if (request.url.path == '/_dsh_mobile/v1/login') {
            return http.Response(
              jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
              200,
            );
          }
          captured.add(request);
          return await handler(request);
        }),
      ),
    );
  }

  // 真实网关返回 UTF-8 字节流；http.Response 字符串构造默认 latin1，中文会抛错。
  http.Response okRpc(Object? value) => http.Response.bytes(
    utf8.encode(
      jsonEncode({
        'type': 'server-response',
        'rpcId': 'x',
        'result': {'ok': true, 'value': value},
      }),
    ),
    200,
  );

  test('listSessions 解析 items 并容错', () async {
    final api = apiWith(
      (_) async => okRpc({
        'items': [
          {
            'sessionId': 's1',
            'updatedAt': 1792660795006,
            'running': true,
            'blank': false,
            'cwd': '/Users/jun/projects/weaver',
            'projections': {
              'asOfSeq': 18,
              'values': {'title': '框架与 Spring Boot 区别'},
            },
          },
          {'sessionId': 's2', 'blank': true},
          'junk',
          {'no': 'sessionId'},
        ],
      }),
    );
    final sessions = await api.listSessions();
    // 'junk' 非 map 直接丢弃；{no: sessionId} 容错为空 id 保留。
    expect(sessions, hasLength(3));
    expect(sessions[0].title, '框架与 Spring Boot 区别');
    expect(sessions[0].running, isTrue);
    expect(sessions[0].folderName, 'weaver');
    expect(sessions[0].asOfSeq, 18);
    expect(sessions[1].blank, isTrue);
    expect(sessions[2].sessionId, isEmpty);
  });

  test('listWorkspaceDirectory 使用 workspaceFileScopeId + 相对路径', () async {
    final api = apiWith(
      (_) async => okRpc({
        'path': 'app/lib',
        'entries': [
          {'name': 'sessions', 'type': 'directory'},
          {'name': 'main.dart', 'type': 'file', 'size': 812},
          {'name': 'link', 'type': 'other'},
          'junk',
        ],
        'truncated': true,
      }),
    );
    final listing = await api.listWorkspaceDirectory(
      sessionId: 's1',
      path: 'app/lib',
    );
    expect(listing.path, 'app/lib');
    expect(listing.entries, hasLength(3));
    expect(listing.entries[0].isDirectory, isTrue);
    expect(listing.entries[1].size, 812);
    expect(listing.entries[2].type, WorkspaceEntryType.other);
    expect(listing.truncated, isTrue);

    expect(captured.single.url.path, '/api/workspaceFiles/list');
    final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
    final args = (body['payload'] as Map)['args'] as Map;
    expect(args['workspaceFileScopeId'], 's1');
    expect(args['path'], 'app/lib');
  });

  test('readWorkspaceFile 读取一页文本并解析行号', () async {
    final api = apiWith(
      (_) async => okRpc({
        'offset': 21,
        'text': 'final a = 1;\nprint(a);',
        'lines': 2,
        'eof': false,
        'bytes': 4096,
      }),
    );
    final page = await api.readWorkspaceFile(
      sessionId: 's1',
      path: 'lib/main.dart',
      offset: 21,
      limit: 1000,
    );
    expect(page.offset, 21);
    expect(page.lines, 2);
    expect(page.eof, isFalse);
    expect(page.bytes, 4096);
    expect(page.text, contains('print(a);'));

    expect(captured.single.url.path, '/api/workspaceFiles/read');
    final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
    final args = (body['payload'] as Map)['args'] as Map;
    expect(args['workspaceFileScopeId'], 's1');
    expect(args['path'], 'lib/main.dart');
    expect((args['range'] as Map)['offset'], 21);
    expect((args['range'] as Map)['limit'], 1000);
  });

  test('readWorkspaceFileBytes 解析 multipart 附件并按 eof 分片续读', () async {
    const boundary = 'dsh-boundary';
    http.Response multipart(
      List<int> bytes, {
      required bool eof,
      int offset = 0,
    }) {
      final metadata = jsonEncode({
        'type': 'server-response',
        'rpcId': 'x',
        'result': {
          'ok': true,
          'value': {'offset': offset, 'data': null, 'eof': eof, 'bytes': 3},
        },
        'attachments': [
          {
            'path': ['data'],
            'codec': 'bytes',
            'part': 'bytes-0',
          },
        ],
      });
      final body = <int>[
        ...utf8.encode('--$boundary\r\n'),
        ...utf8.encode(
          'content-disposition: form-data; name="metadata"\r\n'
          'content-type: application/json\r\n\r\n',
        ),
        ...utf8.encode(metadata),
        ...utf8.encode('\r\n--$boundary\r\n'),
        ...utf8.encode(
          'content-disposition: form-data; name="bytes-0"\r\n'
          'content-type: application/octet-stream\r\n\r\n',
        ),
        ...bytes,
        ...utf8.encode('\r\n--$boundary--\r\n'),
      ];
      return http.Response.bytes(
        body,
        200,
        headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
      );
    }

    var calls = 0;
    final api = apiWith((_) async {
      calls++;
      return calls == 1
          ? multipart([1, 2], eof: false)
          : multipart([3], eof: true, offset: 2);
    });
    final bytes = await api.readWorkspaceFileBytes(
      sessionId: 's1',
      path: 'assets/logo.png',
    );
    expect(bytes.data, [1, 2, 3]);
    expect(bytes.totalBytes, 3);
    expect(bytes.truncated, isFalse);

    expect(captured, hasLength(2));
    final firstArgs =
        ((jsonDecode(captured.first.body) as Map)['payload'] as Map)['args']
            as Map;
    expect(firstArgs['path'], 'assets/logo.png');
    expect((firstArgs['range'] as Map)['offset'], 0);
    final secondArgs =
        ((jsonDecode(captured.last.body) as Map)['payload'] as Map)['args']
            as Map;
    expect((secondArgs['range'] as Map)['offset'], 2);
  });

  test('readWorkspaceFileBytes 遇到旧宿主按 options 重发并记住参数名', () async {
    const boundary = 'legacy-boundary';
    http.Response multipart(List<int> bytes) {
      final metadata = jsonEncode({
        'type': 'server-response',
        'rpcId': 'x',
        'result': {
          'ok': true,
          'value': {
            'offset': 0,
            'data': null,
            'eof': true,
            'bytes': bytes.length,
          },
        },
        'attachments': [
          {
            'path': ['data'],
            'codec': 'bytes',
            'part': 'bytes-0',
          },
        ],
      });
      return http.Response.bytes(
        <int>[
          ...utf8.encode(
            '--$boundary\r\ncontent-disposition: form-data; name="metadata"\r\n'
            'content-type: application/json\r\n\r\n',
          ),
          ...utf8.encode(metadata),
          ...utf8.encode(
            '\r\n--$boundary\r\ncontent-disposition: form-data; name="bytes-0"\r\n'
            'content-type: application/octet-stream\r\n\r\n',
          ),
          ...bytes,
          ...utf8.encode('\r\n--$boundary--\r\n'),
        ],
        200,
        headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
      );
    }

    Map<String, Object?> argsOf(http.Request request) =>
        ((jsonDecode(request.body) as Map)['payload'] as Map)['args']
            as Map<String, Object?>;

    final api = apiWith((request) async {
      final args = argsOf(request);
      if (args.containsKey('range')) {
        return http.Response(
          jsonEncode({
            'result': {
              'ok': false,
              'error': {
                'code': 'gateway/bad-request',
                'message':
                    'typert gateway: workspaceFiles/readBytes: args fields do not '
                    'match the descriptor: missing "options"; unexpected "range"',
              },
            },
          }),
          200,
        );
      }
      return multipart([9, 8, 7]);
    });

    final first = await api.readWorkspaceFileBytes(
      sessionId: 's1',
      path: 'images/a.jpg',
    );
    expect(first.data, [9, 8, 7]);
    // 第一次：range 被拒 + options 重发。
    expect(captured, hasLength(2));
    expect(argsOf(captured.first).containsKey('range'), isTrue);
    expect(argsOf(captured.last).containsKey('options'), isTrue);

    captured.clear();
    final second = await api.readWorkspaceFileBytes(
      sessionId: 's1',
      path: 'images/b.jpg',
    );
    expect(second.data, [9, 8, 7]);
    // 之后不再探测，直接走 options。
    expect(captured, hasLength(1));
    expect(argsOf(captured.single).containsKey('options'), isTrue);
  });

  test('prompt 使用实测信封格式（requestId/sessionId/mode/content）', () async {
    final api = apiWith((_) async => okRpc({'accepted': true}));
    await api.prompt(sessionId: 's1', requestId: 'req-1', text: '你好');
    expect(captured, hasLength(1));
    final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
    expect(captured.first.url.path, '/api/session/prompt');
    final args = (body['payload'] as Map)['args'] as Map;
    final request = args['request'] as Map;
    expect(request['sessionId'], 's1');
    expect(request['mode'], 'queue');
    expect(request['requestId'], 'req-1');
    expect((request['content'] as List).first, {'type': 'text', 'text': '你好'});
  });

  test('selectAgentPreset 参数在 args 顶层', () async {
    final api = apiWith((_) async => okRpc('cordis'));
    await api.selectAgentPreset(sessionId: 's1', presetId: 'cordis');
    expect(captured, hasLength(1));
    final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
    expect(captured.first.url.path, '/api/agentPresets/select');
    expect((body['payload'] as Map)['args'], {
      'agentId': 's1',
      'agentPreset': 'cordis',
    });
  });

  test('list 参数名固定为 _request', () async {
    final api = apiWith((_) async => okRpc({'items': []}));
    await api.listSessions();
    final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
    expect((body['payload'] as Map)['args'], {'_request': {}});
  });

  test('page 传 address/throughSeq/beforeSeq 并解析 hasMore', () async {
    final api = apiWith((_) async => okRpc({'records': [], 'hasMore': true}));
    final page = await api.page('s1', throughSeq: 18, beforeSeq: 3);
    final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
    final request = ((body['payload'] as Map)['args'] as Map)['request'] as Map;
    expect(request['address'], {'kind': 'session', 'sessionId': 's1'});
    expect(request['throughSeq'], 18);
    expect(request['beforeSeq'], 3);
    expect(page.hasMore, isTrue);
    expect(page.events, isEmpty);
  });

  group('session/projections 三态', () {
    test('sequenced / migration-required / null', () async {
      var value = <String, Object?>{
        'kind': 'sequenced',
        'asOfSeq': 18,
        'values': {
          'title': '标题',
          'goal': {
            'goal': {
              'id': 'g1',
              'revision': 2,
              'objective': '完成任务',
              'phase': 'active',
              'maxGoalRounds': 5,
            },
            'roundsStarted': 1,
          },
          'plan': {'active': true, 'pending': false},
          'todos': [
            {'content': '写代码', 'status': 'in_progress'},
            {'content': '跑测试', 'status': 'completed'},
          ],
        },
      };
      final api = apiWith((_) async => okRpc(value));
      final projections = await api.projections('s1');
      expect(projections.asOfSeq, 18);
      expect(projections.title, '标题');
      expect(projections.goal?.objective, '完成任务');
      expect(projections.goal?.roundsStarted, 1);
      expect(projections.plan?.active, isTrue);
      expect(projections.plan?.pending, isFalse);
      expect(projections.todos.last.isDone, isTrue);

      value = {
        'kind': 'migration-required',
        'values': {'title': '旧会话'},
      };
      final migration = await api.projections('s1');
      expect(migration.migrationRequired, isTrue);
      expect(migration.title, '旧会话');

      final nullApi = apiWith((_) async => okRpc(null));
      final empty = await nullApi.projections('s1');
      expect(empty.asOfSeq, 0);
      expect(empty.values, isEmpty);
    });
  });

  group('TranscriptBuilder', () {
    SessionWireEvent event(
      String type,
      int seq,
      Object? data, {
      int time = 0,
    }) => SessionWireEvent(type: type, seq: seq, time: time, data: data);

    test('真实用户消息保留、注入消息过滤、assistant 拆 text/reasoning', () {
      final builder = TranscriptBuilder()
        ..replace([
          event('permission/preset', 0, {'preset': 'workspace-write'}),
          event('user/message', 8, {
            'content': [
              {'type': 'text', 'text': '请直接回复：收到'},
            ],
            'source': {'kind': 'user', 'rpcId': 'req-1'},
            'role': 'user',
          }),
          event('user/message', 9, {
            'content': [
              {'type': 'text', 'text': 'Current runtime context...'},
            ],
            'role': 'user',
          }),
          event('assistant/message', 16, {
            'turn': 1,
            'step': 1,
            'message': {
              'role': 'assistant',
              'content': [
                {'type': 'reasoning', 'text': '用户要我说收到'},
                {'type': 'text', 'text': '收到'},
              ],
            },
          }),
          event('turn/end', 18, {
            'turn': 1,
            'reason': {'kind': 'completed'},
          }),
          event('future/unknown-event', 19, {}),
        ]);

      expect(builder.nodes, hasLength(2));
      expect(builder.nodes[0].kind, TranscriptKind.user);
      expect(builder.nodes[0].text, '请直接回复：收到');
      expect(builder.nodes[1].kind, TranscriptKind.assistant);
      expect(builder.nodes[1].text, '收到');
      expect(builder.nodes[1].reasoning, '用户要我说收到');
      expect(builder.baseSeq, 0);
      expect(builder.seenRpcIds, {'req-1'});
    });

    test('按 seq 去重且未知事件不抛错', () {
      final builder = TranscriptBuilder()
        ..append(
          event('user/message', 5, {
            'source': {'kind': 'user'},
            'content': [
              {'type': 'text', 'text': 'hi'},
            ],
          }),
        )
        ..append(
          event('user/message', 5, {
            'source': {'kind': 'user'},
            'content': [
              {'type': 'text', 'text': 'duplicate'},
            ],
          }),
        )
        ..append(event('unknown/type', 6, 'junk'));
      expect(builder.nodes, hasLength(1));
      expect(builder.nodes.single.text, 'hi');
      expect(builder.baseSeq, 5);
    });

    test('仅图片的消息保留并记录数量', () {
      final builder = TranscriptBuilder()
        ..replace([
          event('user/message', 5, {
            'source': {'kind': 'user'},
            'content': [
              {'type': 'image', 'mediaType': 'image/png', 'data': 'aGk='},
            ],
          }),
        ]);
      expect(builder.nodes, hasLength(1));
      expect(builder.nodes.single.text, isEmpty);
      expect(builder.nodes.single.imageCount, 1);
    });

    test('工具调用与结果按 callId 合并', () {
      final builder = TranscriptBuilder()
        ..replace([
          event('tool/call', 3, {
            'callId': 'call-1',
            'name': 'read_file',
            'arguments': '{"path":"a"}',
          }),
          event('tool/result', 4, {
            'message': {
              'toolCallId': 'call-1',
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
            },
          }),
        ]);
      expect(builder.nodes, hasLength(1));
      final tool = builder.nodes.single;
      expect(tool.kind, TranscriptKind.tool);
      expect(tool.toolName, 'read_file');
      expect(tool.toolArguments, '{"path":"a"}');
      expect(tool.toolResult, 'ok');
      expect(tool.toolFinished, isTrue);
      expect(tool.toolFailed, isFalse);
    });

    test('轮次错误降级为错误节点', () {
      final builder = TranscriptBuilder()
        ..replace([
          event('turn/end', 18, {
            'reason': {
              'kind': 'error',
              'error': {'code': 'x', 'message': '模型不可用'},
            },
          }),
        ]);
      expect(builder.nodes.single.kind, TranscriptKind.error);
      expect(builder.nodes.single.text, '模型不可用');
    });

    test('prepend 只补充缺失的更早事件', () {
      final builder = TranscriptBuilder()
        ..replace([
          event('user/message', 8, {
            'source': {'kind': 'user'},
            'content': [
              {'type': 'text', 'text': 'newer'},
            ],
          }),
        ])
        ..prepend([
          event('user/message', 8, {
            'source': {'kind': 'user'},
            'content': [
              {'type': 'text', 'text': 'duplicate'},
            ],
          }),
          event('user/message', 3, {
            'source': {'kind': 'user'},
            'content': [
              {'type': 'text', 'text': 'older'},
            ],
          }),
        ]);
      expect(builder.nodes.map((n) => n.text), ['older', 'newer']);
      expect(builder.baseSeq, 3);
    });
  });

  test('newRpcId 是合法 uuid v4 格式', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    for (var i = 0; i < 20; i++) {
      expect(newRpcId(), matches(pattern));
    }
  });

  group('新增方法信封（实测参数名锁定）', () {
    test('rename 用 {request:{sessionId,title}}', () async {
      final api = apiWith((_) async => okRpc({'title': '新标题', 'seq': 1}));
      final title = await api.rename('s1', '新标题');
      expect(title, '新标题');
      final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
      expect(captured.first.url.path, '/api/session/rename');
      expect(((body['payload'] as Map)['args'] as Map)['request'], {
        'sessionId': 's1',
        'title': '新标题',
      });
    });

    test('archive/unarchive 参数与返回 id 集合', () async {
      final api = apiWith((request) async {
        final method = request.url.path;
        expect(
          method,
          anyOf(
            '/api/workspace/archiveSession',
            '/api/workspace/unarchiveSession',
          ),
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final requestArgs =
            ((body['payload'] as Map)['args'] as Map)['request'] as Map;
        expect(requestArgs['sessionId'], 's1');
        return okRpc({
          'archivedSessionIds': ['a', 's1'],
        });
      });
      expect(await api.archive('s1'), ['a', 's1']);
      expect(await api.unarchive('s1'), ['a', 's1']);
    });

    test('fork 返回新 sessionId', () async {
      final api = apiWith((_) async => okRpc({'sessionId': 's-new'}));
      expect(await api.fork('s1'), 's-new');
    });

    test('modelCatalog 无参数，解析分组', () async {
      final api = apiWith((request) async {
        expect(request.url.path, '/api/session/modelCatalog');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect((body['payload'] as Map)['args'], isEmpty);
        return okRpc({
          'default': {'provider': 'p1', 'model': 'm1'},
          'routableProviders': ['p1'],
          'groups': [
            {
              'id': 'p1',
              'name': 'Provider One',
              'models': [
                {
                  'id': 'm1',
                  'name': 'Model One',
                  'reasoning': {
                    'efforts': [
                      {'id': 'off', 'name': 'Off'},
                    ],
                  },
                },
              ],
            },
          ],
        });
      });
      final catalog = await api.modelCatalog();
      expect(catalog.defaultProvider, 'p1');
      expect(catalog.groups, hasLength(1));
      expect(catalog.groups.first.models.first.efforts.first.id, 'off');
    });

    test('selectModel 携带 provider/model/reasoningEffort', () async {
      final api = apiWith((_) async => okRpc({'selected': {}}));
      await api.selectModel(
        sessionId: 's1',
        provider: 'p1',
        model: 'm1',
        reasoningEffort: 'off',
      );
      final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
      expect(((body['payload'] as Map)['args'] as Map)['request'], {
        'sessionId': 's1',
        'provider': 'p1',
        'model': 'm1',
        'reasoningEffort': 'off',
      });
    });

    test(
      'answerQuestions 用 {agentId, callId, answer:{answers:[...]}}',
      () async {
        final api = apiWith((_) async => okRpc({'ok': true}));
        await api.answerQuestions(
          sessionId: 's1',
          callId: 'call-1',
          answers: [
            const QuestionAnswer(
              questionId: 'q1',
              selected: ['选项A'],
              custom: '补充',
            ),
          ],
        );
        final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
        expect(captured.first.url.path, '/api/userQuestions/answer');
        final args = (body['payload'] as Map)['args'] as Map;
        expect(args['agentId'], 's1');
        expect(args['callId'], 'call-1');
        expect((args['answer'] as Map)['answers'], [
          {
            'id': 'q1',
            'selected': ['选项A'],
            'custom': '补充',
          },
        ]);
      },
    );

    test('eventsResult 用 {clientId, eventId, outcome}', () async {
      final api = apiWith((_) async => okRpc(null));
      await api.eventsResult(
        clientId: 'client-1',
        eventId: 'event-1',
        outcome: const {'kind': 'result', 'value': 'allowed-once'},
      );
      final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
      expect(captured.first.url.path, '/api/\$events/result');
      expect((body['payload'] as Map)['args'], {
        'clientId': 'client-1',
        'eventId': 'event-1',
        'outcome': {'kind': 'result', 'value': 'allowed-once'},
      });
    });

    test('创建会话', () async {
      final api = apiWith((_) async => okRpc({'sessionId': 's-new'}));
      expect(await api.createSession(), 's-new');
      var body = jsonDecode(captured.last.body) as Map<String, dynamic>;
      expect(captured.last.url.path, '/api/session/create');
      expect(((body['payload'] as Map)['args'] as Map)['request'], isEmpty);

      expect(await api.createSession(cwd: '/root/weaver'), 's-new');
      body = jsonDecode(captured.last.body) as Map<String, dynamic>;
      expect(((body['payload'] as Map)['args'] as Map)['request'], {
        'cwd': '/root/weaver',
      });
    });

    test('prompt 可携带图片 base64 项', () async {
      final api = apiWith((_) async => okRpc({'accepted': true}));
      await api.prompt(
        sessionId: 's1',
        requestId: 'req-1',
        text: '看图',
        attachments: [
          const PromptImage(
            mediaType: 'image/png',
            base64Data: 'aGk=',
            name: 'x.png',
          ),
        ],
      );
      final body = jsonDecode(captured.first.body) as Map<String, dynamic>;
      final request =
          ((body['payload'] as Map)['args'] as Map)['request'] as Map;
      expect(request['content'], [
        {'type': 'text', 'text': '看图'},
        {
          'type': 'image',
          'mediaType': 'image/png',
          'data': 'aGk=',
          'name': 'x.png',
        },
      ]);
    });
  });

  // 网关按 descriptor 严格校验参数名：写成 `agent` 会被判 arguments-invalid，
  // 菜单静默为空。这里把 wire 字段名钉死。
  group('composer RPC 的 wire 参数名', () {
    Map<String, dynamic> lastArgs() {
      final body = jsonDecode(captured.last.body) as Map<String, dynamic>;
      return (body['payload'] as Map)['args'] as Map<String, dynamic>;
    }

    test('commands/list 与 commands/execute 用 agentId', () async {
      final api = apiWith((request) async {
        if (request.url.path.endsWith('commands/list')) {
          return okRpc([
            {'name': 'compact', 'description': 'Compact'},
          ]);
        }
        return okRpc({
          'commandId': 'c1',
          'result': {'kind': 'success', 'text': '已切换'},
        });
      });
      await api.commands(sessionId: 's1');
      expect(lastArgs(), {'agentId': 's1'});

      final executed = await api.executeCommand(sessionId: 's1', line: '/plan');
      expect(lastArgs()['agentId'], 's1');
      expect(lastArgs()['line'], '/plan');
      expect(lastArgs()['submittedAttachments'], isA<List>());
      expect(executed.matched, isTrue);
      expect(executed.ok, isTrue);
      expect(executed.text, '已切换');
    });

    test(
      'fileReferences/list 与 sessionReferenceResolver 用 agentId + query',
      () async {
        final api = apiWith((request) async {
          if (request.url.path.endsWith('fileReferences/list')) {
            return okRpc([
              {'path': 'docs', 'kind': 'directory'},
            ]);
          }
          return okRpc([
            {'mention': '@[a](dsh-session:b)', 'sessionId': 'b', 'label': 'a'},
          ]);
        });
        await api.fileReferenceCandidates(sessionId: 's1', query: 'do');
        expect(lastArgs(), {'agentId': 's1', 'query': 'do'});

        await api.sessionReferenceCandidates(sessionId: 's1', query: '');
        expect(lastArgs(), {'agentId': 's1', 'query': ''});
      },
    );

    test('goals/* 用 agentId + ref/request', () async {
      final api = apiWith(
        (_) async => okRpc({
          'ref': {'id': 'g1', 'revision': 2},
        }),
      );
      await api.createGoal(sessionId: 's1', objective: '目标');
      expect(lastArgs()['agentId'], 's1');
      expect(lastArgs()['request'], {'objective': '目标'});

      await api.pauseGoal(
        sessionId: 's1',
        ref: const GoalRef(id: 'g1', revision: 2),
      );
      expect(lastArgs()['agentId'], 's1');
      expect(lastArgs()['ref'], {'id': 'g1', 'revision': 2});
    });

    test('skills/list 用 request.sessionId', () async {
      final api = apiWith((_) async => okRpc({'skills': []}));
      await api.skills(sessionId: 's1');
      expect(lastArgs(), {
        'request': {'sessionId': 's1'},
      });
    });
  });
}
