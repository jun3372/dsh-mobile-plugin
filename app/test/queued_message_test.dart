import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile/core/models/queued_message.dart';

/// inbox 投影里一条真实的用户排队消息。
Map<String, dynamic> _userItem(
  String id,
  String text, {
  String rpcId = 'r-1',
}) => {
  'id': id,
  'content': [
    {'type': 'text', 'text': text},
  ],
  'source': {'kind': 'user', 'rpcId': rpcId},
};

/// 授权切换时宿主注入模型的通知（source.kind=user-approval），
/// Web 按 placement=context 过滤，队列里不可见。
Map<String, dynamic> _injectedItem(String id, String text) => {
  'id': id,
  'content': [
    {'type': 'text', 'text': text},
  ],
  'source': {'kind': 'user-approval'},
};

void main() {
  group('QueuedMessage.fromProjection', () {
    test('只保留 source.kind=user 的条目，过滤授权切换注入的通知', () {
      final inbox = {
        'next-turn': [_userItem('m-1', '继续')],
        'next-step': [
          _injectedItem(
            'm-2',
            'The approval policy changed from "ask" to "never" (changed by the user).',
          ),
          _userItem('m-3', '插队消息', rpcId: 'r-3'),
        ],
      };
      final queue = QueuedMessage.fromProjection(inbox);
      expect(queue.map((item) => item.itemId), ['m-1', 'm-3']);
      expect(queue.map((item) => item.target), ['next-turn', 'next-step']);
      expect(queue.last.rpcId, 'r-3');
    });

    test('注入通知单独存在时队列为空', () {
      final inbox = {
        'next-step': [_injectedItem('m-1', 'The approval policy changed.')],
      };
      expect(QueuedMessage.fromProjection(inbox), isEmpty);
    });

    test('source 缺失的条目同样不透出到队列', () {
      final inbox = {
        'next-turn': [
          {
            'id': 'm-1',
            'content': [
              {'type': 'text', 'text': 'no source'},
            ],
          },
        ],
      };
      expect(QueuedMessage.fromProjection(inbox), isEmpty);
    });
  });
}
