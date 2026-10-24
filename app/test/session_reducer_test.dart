import 'package:dsh_mobile/core/models/dsh_models.dart';
import 'package:dsh_mobile/core/models/pending_submission.dart';
import 'package:dsh_mobile/core/models/session_event.dart';
import 'package:dsh_mobile/core/models/transcript_node.dart';
import 'package:dsh_mobile/core/session/assistant_stream_folder.dart';
import 'package:dsh_mobile/core/session/session_follow_client.dart';
import 'package:dsh_mobile/core/session/session_replica.dart';
import 'package:dsh_mobile/core/session/transcript_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptBuilder', () {
    test('用户消息只认 source.kind=user，其他上下文来源不渲染', () {
      final builder = TranscriptBuilder()
        ..replace([
          _event('user/message', 1, {
            'turn': 1,
            'content': [
              {'type': 'text', 'text': '你好'},
              {'type': 'image', 'attachmentId': 'a1'},
            ],
            'source': {'kind': 'user', 'rpcId': 'req-1'},
          }),
          _event('user/message', 2, {
            'turn': 1,
            'content': [
              {'type': 'text', 'text': '运行时上下文'},
            ],
            'source': {'kind': 'runtime-context'},
          }),
        ]);
      expect(builder.nodes, hasLength(1));
      expect(builder.nodes.single.kind, TranscriptKind.user);
      expect(builder.nodes.single.text, '你好');
      expect(builder.nodes.single.imageCount, 1);
      expect(builder.seenRpcIds, {'req-1'});
    });

    test('assistant 文本与推理合并为一条节点', () {
      final builder = TranscriptBuilder()
        ..replace([
          _event('assistant/message', 1, {
            'turn': 1,
            'step': 0,
            'message': {
              'content': [
                {'type': 'reasoning', 'text': '先想一想'},
                {'type': 'text', 'text': '答案'},
              ],
            },
          }),
        ]);
      final node = builder.nodes.single;
      expect(node.kind, TranscriptKind.assistant);
      expect(node.text, '答案');
      expect(node.reasoning, '先想一想');
    });

    test('工具调用与结果按 callId 合并为一张卡片', () {
      final builder = TranscriptBuilder()
        ..replace([
          _event('tool/call', 1, {
            'turn': 1,
            'step': 0,
            'callId': 'c1',
            'name': 'bash',
            'arguments': '{"command":"ls"}',
          }),
          _event('tool/result', 2, {
            'turn': 1,
            'step': 0,
            'message': {
              'toolCallId': 'c1',
              'content': [
                {'type': 'text', 'text': 'a.txt'},
              ],
              'isError': true,
            },
          }),
        ]);
      expect(builder.nodes, hasLength(1));
      final node = builder.nodes.single;
      expect(node.kind, TranscriptKind.tool);
      expect(node.toolName, 'bash');
      expect(node.toolCallId, 'c1');
      expect(node.toolArguments, '{"command":"ls"}');
      expect(node.toolResult, 'a.txt');
      expect(node.toolFailed, isTrue);
      expect(node.toolFinished, isTrue);
    });

    test('工具结果带 error.reason 时优先展示错误原因', () {
      final builder = TranscriptBuilder()
        ..replace([
          _event('tool/call', 1, {
            'turn': 1,
            'step': 0,
            'callId': 'c1',
            'name': 'bash',
          }),
          _event('tool/result', 2, {
            'turn': 1,
            'step': 0,
            'message': {'toolCallId': 'c1', 'content': <Object?>[]},
            'error': {'name': 'ToolError', 'reason': '命令被拒绝'},
          }),
        ]);
      expect(builder.nodes.single.toolResult, '命令被拒绝');
    });

    test('压缩摘要只落在 replace 检查点位置', () {
      final builder = TranscriptBuilder()
        ..replace([
          _event('compaction/summary', 1, {
            'compactionId': 'c1',
            'summary': [
              {'type': 'text', 'text': '前文摘要'},
            ],
          }),
          _event('user/message', 2, {
            'turn': 2,
            'content': [
              {'type': 'text', 'text': '压缩后的检查点'},
            ],
            'source': {
              'kind': 'plugin',
              'plugin': 'compact',
              'compactionId': 'c1',
            },
          }, surfaceOp: 'replace'),
        ]);
      expect(builder.nodes, hasLength(1));
      expect(builder.nodes.single.kind, TranscriptKind.compaction);
      expect(builder.nodes.single.text, '前文摘要');
    });

    test('turn/end 只对 error/interrupted/max-tokens 出节点', () {
      TranscriptBuilder build(Object reason) => TranscriptBuilder()
        ..replace([
          _event('turn/end', 1, {'turn': 1, 'reason': reason}),
        ]);

      expect(
        build({
          'kind': 'error',
          'error': {'code': 'boom', 'message': '模型不可用'},
        }).nodes.single.kind,
        TranscriptKind.error,
      );
      expect(
        build({'kind': 'max-tokens'}).nodes.single.kind,
        TranscriptKind.notice,
      );
      expect(
        build({'kind': 'interrupted'}).nodes.single.kind,
        TranscriptKind.error,
      );
      expect(build({'kind': 'blocked'}).nodes, isEmpty);
      expect(build({'kind': 'aborted'}).nodes, isEmpty);
      expect(
        build({
          'kind': 'aborted',
          'hook': {'reason': 'user'},
        }).nodes,
        isEmpty,
      );
    });

    test('同一 seq 重复 append 不产生重复节点', () {
      final builder = TranscriptBuilder()
        ..append(
          _event('user/message', 1, {
            'turn': 1,
            'content': [
              {'type': 'text', 'text': '一次'},
            ],
            'source': {'kind': 'user'},
          }),
        );
      builder.append(
        _event('user/message', 1, {
          'turn': 1,
          'content': [
            {'type': 'text', 'text': '一次'},
          ],
          'source': {'kind': 'user'},
        }),
      );
      expect(builder.nodes, hasLength(1));
    });

    test('prepend 历史后按 seq 排序且忽略重复', () {
      final builder = TranscriptBuilder()
        ..replace([
          _event('assistant/message', 5, {
            'turn': 2,
            'step': 0,
            'message': {
              'content': [
                {'type': 'text', 'text': '新'},
              ],
            },
          }),
        ]);
      builder.prepend([
        _event('user/message', 3, {
          'turn': 1,
          'content': [
            {'type': 'text', 'text': '旧一'},
          ],
          'source': {'kind': 'user'},
        }),
        _event('user/message', 3, {
          'turn': 1,
          'content': [
            {'type': 'text', 'text': '重复'},
          ],
          'source': {'kind': 'user'},
        }),
      ]);
      expect(builder.nodes.map((node) => node.text), ['旧一', '新']);
      expect(builder.baseSeq, 3);
    });
  });

  group('AssistantStreamFolder', () {
    test('start/chunk/end 折叠出临时节点，abandoned 后撤下', () {
      final folder = AssistantStreamFolder();
      expect(
        folder.acceptFrame({
          'type': 'start',
          'attemptId': 'a1',
          'revision': 1,
          'turn': 1,
          'step': 0,
          'startedAfterSeq': 5,
        }),
        AssistantFrameResult.updated,
      );
      expect(
        folder.acceptFrame({
          'type': 'chunk',
          'attemptId': 'a1',
          'revision': 2,
          'index': 0,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': '流式中'},
        }),
        AssistantFrameResult.updated,
      );
      expect(folder.liveNode?.text, '流式中');
      expect(folder.liveNode?.live, isTrue);

      expect(
        folder.acceptFrame({
          'type': 'end',
          'attemptId': 'a1',
          'revision': 3,
          'index': 1,
          'outcome': {'kind': 'abandoned'},
        }),
        AssistantFrameResult.updated,
      );
      expect(folder.liveNode, isNull);
      expect(folder.isLive, isFalse);
    });

    test('持久结算先暂存，committed 核对 seq/type 后放行', () {
      final folder = AssistantStreamFolder();
      folder.acceptFrame({
        'type': 'start',
        'attemptId': 'a1',
        'turn': 1,
        'step': 0,
        'startedAfterSeq': 5,
      });
      folder.acceptFrame({
        'type': 'chunk',
        'attemptId': 'a1',
        'index': 0,
        'chunk': {'type': 'text-delta', 'index': 0, 'text': '你好'},
      });

      final settlement = _event('assistant/message', 10, {
        'turn': 1,
        'step': 0,
        'message': {
          'content': [
            {'type': 'text', 'text': '你好'},
          ],
        },
      }, surfaceOp: 'append');
      expect(folder.acceptDurable(settlement), AssistantDurableResult.staged);
      expect(folder.drainReleased(), isEmpty);

      expect(
        folder.acceptFrame({
          'type': 'end',
          'attemptId': 'a1',
          'index': 1,
          'outcome': {
            'kind': 'committed',
            'eventType': 'assistant/message',
            'seq': 10,
          },
        }),
        AssistantFrameResult.updated,
      );
      final released = folder.drainReleased();
      expect(released, hasLength(1));
      expect(released.single.seq, 10);
      expect(folder.liveNode, isNull);
    });

    test('snapshot 已发布的结算不会因 end 帧重复放行', () {
      final folder = AssistantStreamFolder();
      final settlement = _event('assistant/message', 10, {
        'turn': 1,
        'step': 0,
        'message': {
          'content': [
            {'type': 'text', 'text': '你好'},
          ],
        },
      }, surfaceOp: 'append');
      folder.seedPublished([settlement]);
      folder.acceptFrame({
        'type': 'start',
        'attemptId': 'a1',
        'turn': 1,
        'step': 0,
        'startedAfterSeq': 5,
      });
      expect(
        folder.acceptFrame({
          'type': 'end',
          'attemptId': 'a1',
          'index': 0,
          'outcome': {
            'kind': 'committed',
            'eventType': 'assistant/message',
            'seq': 10,
          },
        }),
        AssistantFrameResult.updated,
      );
      expect(folder.drainReleased(), isEmpty);
    });

    test('index 断档、并发 start、pending 下的 abandoned 都要求重建', () {
      final folder = AssistantStreamFolder();
      folder.acceptFrame({
        'type': 'start',
        'attemptId': 'a1',
        'turn': 1,
        'step': 0,
        'startedAfterSeq': 5,
      });

      expect(
        folder.acceptFrame({
          'type': 'chunk',
          'attemptId': 'a1',
          'index': 2,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': '跳号'},
        }),
        AssistantFrameResult.rebaseline,
      );
      expect(
        folder.acceptFrame({
          'type': 'start',
          'attemptId': 'a2',
          'turn': 1,
          'step': 0,
          'startedAfterSeq': 5,
        }),
        AssistantFrameResult.rebaseline,
      );

      folder.acceptDurable(
        _event('assistant/message', 10, {
          'turn': 1,
          'step': 0,
          'message': {
            'content': [
              {'type': 'text', 'text': '你好'},
            ],
          },
        }, surfaceOp: 'append'),
      );
      expect(
        folder.acceptFrame({
          'type': 'end',
          'attemptId': 'a1',
          'index': 0,
          'outcome': {'kind': 'abandoned'},
        }),
        AssistantFrameResult.rebaseline,
      );
    });

    test('attemptId 不匹配的 chunk/end 直接忽略', () {
      final folder = AssistantStreamFolder();
      folder.acceptFrame({
        'type': 'start',
        'attemptId': 'a1',
        'turn': 1,
        'step': 0,
        'startedAfterSeq': 5,
      });
      expect(
        folder.acceptFrame({
          'type': 'chunk',
          'attemptId': 'other',
          'index': 0,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'x'},
        }),
        AssistantFrameResult.ignored,
      );
      expect(
        folder.acceptFrame({
          'type': 'end',
          'attemptId': 'other',
          'index': 0,
          'outcome': {'kind': 'abandoned'},
        }),
        AssistantFrameResult.ignored,
      );
      expect(folder.isLive, isTrue);
    });

    test('step/end 释放同轮同步骤的暂存结算', () {
      final folder = AssistantStreamFolder();
      folder.acceptFrame({
        'type': 'start',
        'attemptId': 'a1',
        'turn': 2,
        'step': 3,
        'startedAfterSeq': 5,
      });
      expect(
        folder.acceptDurable(
          _event('assistant/message', 10, {
            'turn': 2,
            'step': 3,
            'message': {
              'content': [
                {'type': 'text', 'text': '你好'},
              ],
            },
          }, surfaceOp: 'append'),
        ),
        AssistantDurableResult.staged,
      );
      expect(
        folder.acceptDurable(_event('step/end', 11, {'turn': 2, 'step': 3})),
        AssistantDurableResult.publish,
      );
      expect(folder.drainReleased().single.seq, 10);
    });

    test('baseline 展开 compact stream 恢复临时节点', () {
      final folder = AssistantStreamFolder();
      folder.resetWithBaseline({
        'revision': 4,
        'activeAttempt': {
          'attemptId': 'a1',
          'startedAfterSeq': 5,
          'turn': 1,
          'step': 0,
          'nextIndex': 2,
          'stream': [
            {
              'type': 'text-chunks',
              'index': 0,
              'texts': ['你', '好'],
            },
          ],
        },
      });
      expect(folder.isLive, isTrue);
      expect(folder.activeTurn, 1);
      expect(folder.activeStep, 0);
      expect(folder.liveNode?.text, '你好');
    });

    test('expandCompactAssistantStream 还原文本/推理/工具/原始 chunk', () {
      final chunks = expandCompactAssistantStream([
        {
          'type': 'text-chunks',
          'index': 0,
          'texts': ['a', 'b'],
        },
        {
          'type': 'reasoning-chunks',
          'index': 1,
          'texts': ['想'],
        },
        {
          'type': 'tool-call-chunks',
          'index': 2,
          'id': 'c1',
          'name': 'bash',
          'args': ['{"a":', '1}'],
        },
        {
          'type': 'chunk',
          'chunk': {'type': 'usage', 'index': 9},
        },
      ]);
      expect(chunks, hasLength(6));
      expect((chunks[0] as Map)['text'], 'a');
      expect((chunks[2] as Map)['type'], 'reasoning-delta');
      expect((chunks[3] as Map)['name'], 'bash');
      expect((chunks[4] as Map)['argumentsDelta'], '1}');
      expect((chunks[5] as Map)['type'], 'usage');
    });
  });

  group('SessionReplica', () {
    test('snapshot 建立窗口、投影、运行态与转写', () {
      final replica = SessionReplica('s1')
        ..installSnapshot(
          _snapshot(
            cursor: 2,
            hasMore: true,
            records: [
              _userEvent(1, '你好', rpcId: 'r1'),
              _event('assistant/message', 2, {
                'turn': 1,
                'step': 0,
                'message': {
                  'content': [
                    {'type': 'text', 'text': '回复'},
                  ],
                },
              }),
            ],
            projectionsAsOfSeq: 9,
            projections: {
              'title': '会话标题',
              'goal': {
                'goal': {
                  'id': 'g1',
                  'revision': 2,
                  'objective': '完成重构',
                  'phase': 'active',
                  'maxGoalRounds': 5,
                },
                'roundsStarted': 1,
              },
              'plan': {'active': true, 'pending': false},
              'todos': [
                {'content': '写代码', 'status': 'in_progress'},
              ],
              'turnOutline': [
                {'turn': 1, 'seq': 1, 'prompt': '你好', 'response': '回复'},
              ],
            },
            assistantStream: {
              'revision': 3,
              'activeAttempt': {
                'attemptId': 'a1',
                'startedAfterSeq': 2,
                'turn': 1,
                'step': 1,
                'nextIndex': 0,
                'stream': <Object?>[],
              },
            },
          ),
        );

      expect(replica.cursor, 2);
      expect(replica.hasMore, isTrue);
      expect(replica.hasSnapshot, isTrue);
      expect(replica.waitingForSnapshot, isFalse);
      expect(replica.running, isTrue);
      expect(replica.title, '会话标题');
      expect(replica.goal?.objective, '完成重构');
      expect(replica.goal?.roundsStarted, 1);
      expect(replica.plan?.active, isTrue);
      expect(replica.plan?.pending, isFalse);
      expect(replica.todos.single.isActive, isTrue);
      expect(replica.turnOutline.single.turn, 1);
      expect(replica.nodes.map((node) => node.kind), [
        TranscriptKind.user,
        TranscriptKind.assistant,
      ]);
    });

    test('seq 断裂要求重取基线，重复 seq 幂等', () {
      final replica = SessionReplica('s1')
        ..installSnapshot(_snapshot(cursor: 5, records: [_userEvent(5, '五')]));

      expect(replica.appendEvent(_userEvent(5, '五')), isTrue);
      expect(replica.appendEvent(_userEvent(7, '七')), isFalse);
      expect(replica.waitingForSnapshot, isTrue);
      expect(replica.cursor, 5);

      expect(replica.appendEvent(_userEvent(6, '六')), isTrue);
      expect(replica.cursor, 6);
    });

    test('回显按 rpcId 回收本地气泡', () {
      final replica = SessionReplica('s1')
        ..installSnapshot(_snapshot(cursor: 2));
      replica.addPending(
        const PendingSubmission(requestId: 'req-9', text: '本地消息'),
      );
      expect(replica.nodes.single.optimistic, isTrue);
      expect(replica.nodes.single.id, 'local-req-9');
      expect(replica.hasOptimistic, isTrue);

      replica.appendEvent(_userEvent(3, '本地消息', rpcId: 'req-9'));
      expect(replica.hasOptimistic, isFalse);
      expect(replica.pending.isEmpty, isTrue);
      expect(replica.nodes.where((node) => node.optimistic), isEmpty);
      expect(replica.nodes.single.text, '本地消息');
    });

    test('队列来自 inbox 投影并叠加尚未回显的本地排队消息', () {
      final replica = SessionReplica('s1')
        ..installSnapshot(
          _snapshot(
            cursor: 2,
            projections: {
              'inbox': {
                'next-turn': [
                  {
                    'id': 'i1',
                    'content': [
                      {'type': 'text', 'text': '宿主队列'},
                    ],
                    'source': {'kind': 'user', 'rpcId': 'r-inbox'},
                  },
                ],
                'next-step': <Object?>[],
              },
            },
          ),
        );
      replica.addPending(
        const PendingSubmission(
          requestId: 'r-inbox',
          text: '宿主队列',
          queued: true,
        ),
      );
      replica.addPending(
        const PendingSubmission(
          requestId: 'r-local',
          text: '本地排队',
          queued: true,
        ),
      );
      final queue = replica.queue;
      expect(queue.map((item) => item.text), ['宿主队列', '本地排队']);
      expect(queue.map((item) => item.rpcId), ['r-inbox', 'r-local']);
      expect(
        replica.nodes.where((node) => node.id == 'local-r-inbox'),
        isEmpty,
      );
    });

    test('提问投影与 waterfall 按 callId 合并，waterfall 优先', () {
      final replica = SessionReplica('s1')
        ..installSnapshot(
          _snapshot(
            projections: {
              'userQuestions': {
                'active': [
                  {
                    'callId': 'c1',
                    'state': 'continued',
                    'questions': [
                      {'id': 'q1', 'question': '继续吗？'},
                    ],
                  },
                  {
                    'callId': 'c2',
                    'state': 'open',
                    'questions': [
                      {'id': 'q2', 'question': '另一个问题'},
                    ],
                  },
                ],
                'settled': <Object?>[],
              },
            },
          ),
        )
        ..setWaterfallQuestions([
          const SessionQuestionPrompt(
            eventId: 'e1',
            callId: 'c1',
            agentId: 'agent-1',
            questions: [UserQuestion(id: 'q1', question: '继续吗？')],
          ),
        ]);
      final prompts = replica.questionPrompts;
      expect(prompts, hasLength(2));
      final c1 = prompts.singleWhere((prompt) => prompt.key == 'c1');
      expect(c1.viaWaterfall, isTrue);
      expect(c1.eventId, 'e1');
      expect(replica.hasQuestions, isTrue);
    });

    test('向上翻页把旧事件拼到头部并更新 hasMore', () {
      final replica = SessionReplica('s1')
        ..installSnapshot(
          _snapshot(cursor: 5, hasMore: true, records: [_userEvent(5, '最新')]),
        );
      expect(
        replica.prependOlder(
          SessionHistoryPage(
            events: [_userEvent(3, '更早'), _userEvent(4, '稍早')],
            hasMore: false,
          ),
        ),
        isTrue,
      );
      expect(replica.hasMore, isFalse);
      expect(replica.nodes.map((node) => node.text), ['更早', '稍早', '最新']);
      expect(replica.baseSeq, 3);

      expect(replica.prependOlder(const SessionHistoryPage()), isFalse);
      expect(replica.hasMore, isFalse);
    });

    test('control 投影按 asOfSeq 水位合并', () {
      final replica = SessionReplica('s1')
        ..installSnapshot(
          _snapshot(projectionsAsOfSeq: 9, projections: {'title': '基线'}),
        );
      expect(replica.applyControlValues({'title': '旧'}, 8), isFalse);
      expect(replica.title, '基线');
      expect(replica.applyControlValues({'title': '新'}, 10), isTrue);
      expect(replica.title, '新');
      expect(replica.projectionAsOfSeq, 10);
    });

    test('assistant 帧与持久结算协作，违约触发重建', () {
      final replica = SessionReplica('s1')
        ..installSnapshot(_snapshot(cursor: 5));
      replica.appendEvent(_event('turn/start', 6, {'turn': 1}));
      expect(replica.running, isTrue);

      expect(
        replica.acceptAssistantFrame({
          'type': 'start',
          'attemptId': 'a1',
          'revision': 1,
          'turn': 1,
          'step': 0,
          'startedAfterSeq': 6,
        }),
        isTrue,
      );
      expect(
        replica.acceptAssistantFrame({
          'type': 'chunk',
          'attemptId': 'a1',
          'revision': 2,
          'index': 0,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': '流式中'},
        }),
        isTrue,
      );
      expect(replica.nodes.last.live, isTrue);

      replica.appendEvent(
        _event('assistant/message', 7, {
          'turn': 1,
          'step': 0,
          'message': {
            'content': [
              {'type': 'text', 'text': '流式中'},
            ],
          },
        }, surfaceOp: 'append'),
      );
      // 结算仍在暂存，转写里只有 live 节点。
      expect(
        replica.nodes.where((node) => node.kind == TranscriptKind.assistant),
        hasLength(1),
      );

      expect(
        replica.acceptAssistantFrame({
          'type': 'end',
          'attemptId': 'a1',
          'index': 1,
          'outcome': {
            'kind': 'committed',
            'eventType': 'assistant/message',
            'seq': 7,
          },
        }),
        isTrue,
      );
      final assistantNodes = replica.nodes
          .where((node) => node.kind == TranscriptKind.assistant)
          .toList();
      expect(assistantNodes, hasLength(1));
      expect(assistantNodes.single.live, isFalse);
      expect(assistantNodes.single.text, '流式中');

      expect(
        replica.acceptAssistantFrame({
          'type': 'start',
          'attemptId': 'a2',
          'turn': 1,
          'step': 1,
          'startedAfterSeq': 7,
        }),
        isTrue,
      );
      expect(
        replica.acceptAssistantFrame({
          'type': 'chunk',
          'attemptId': 'a2',
          'index': 9,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'x'},
        }),
        isFalse,
      );
      expect(replica.waitingForSnapshot, isTrue);
    });
  });
}

SessionWireEvent _event(
  String type,
  int seq,
  Object? data, {
  String? surfaceOp,
}) => SessionWireEvent(
  type: type,
  seq: seq,
  time: 0,
  data: data,
  surfaceOp: surfaceOp,
);

SessionWireEvent _userEvent(int seq, String text, {String? rpcId}) =>
    _event('user/message', seq, {
      'turn': 1,
      'content': [
        {'type': 'text', 'text': text},
      ],
      'source': {'kind': 'user', 'rpcId': ?rpcId},
    });

FollowSnapshot _snapshot({
  List<SessionWireEvent> records = const [],
  int cursor = 0,
  bool hasMore = false,
  Map<String, Object?> projections = const {},
  int projectionsAsOfSeq = 0,
  Object? assistantStream,
}) => FollowSnapshot(
  header: const {},
  cursor: cursor,
  records: records,
  hasMore: hasMore,
  projectionsAsOfSeq: projectionsAsOfSeq,
  projections: projections,
  assistantStream: assistantStream,
);
