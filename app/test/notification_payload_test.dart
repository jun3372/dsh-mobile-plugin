import 'package:dsh_mobile/features/notifications/notification_tap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('通知 payload 编解码', () {
    test('编解码往返一致', () {
      final payload = encodeNotificationPayload(
        kind: 'question',
        serverId: 'srv-1',
        sessionId: 'agent-abc',
      );
      expect(payload, 'question|srv-1|agent-abc');
      final target = decodeNotificationPayload(payload);
      expect(target, isNotNull);
      expect(target!.kind, 'question');
      expect(target.serverId, 'srv-1');
      expect(target.sessionId, 'agent-abc');
    });

    test('空字段与格式错误返回 null（fail-closed）', () {
      expect(decodeNotificationPayload(''), isNull);
      expect(decodeNotificationPayload('question'), isNull);
      expect(decodeNotificationPayload('question|srv'), isNull);
      expect(decodeNotificationPayload('question||agent'), isNull);
      expect(decodeNotificationPayload('question|srv|'), isNull);
      expect(decodeNotificationPayload('|srv|agent'), isNull);
      expect(decodeNotificationPayload('a|b|c|d'), isNull);
    });
  });
}
