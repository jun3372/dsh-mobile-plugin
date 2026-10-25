import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile/core/mux/remote_events.dart';
import 'package:dsh_mobile/core/models/dsh_models.dart';
import 'package:dsh_mobile/features/notifications/background_alert_controller.dart';

RemoteQuestionRequest questionRequest(
  String eventId, {
  List<UserQuestion> questions = const [],
  String agentId = 'session-1',
}) {
  return RemoteQuestionRequest(
    eventId: eventId,
    agentId: agentId,
    callId: 'call-1',
    questions: questions.isNotEmpty
        ? questions
        : const [UserQuestion(id: 'q1', question: '继续吗？')],
  );
}

void main() {
  group('planFor 文案', () {
    test('普通提问：标题带会话名，正文为首题内容', () {
      final plan = planFor(questionRequest('e1'), '重构登录模块');
      expect(plan.title, '「重构登录模块」等待你的输入');
      expect(plan.body, '继续吗？');
      expect(plan.id, 'e1'.hashCode);
    });

    test('标题缺失：降级通用标题', () {
      final plan = planFor(questionRequest('e1'), null);
      expect(plan.title, '有一个会话等待你的输入');
      final empty = planFor(questionRequest('e1'), '');
      expect(empty.title, '有一个会话等待你的输入');
    });

    test('多题：正文带数量前缀', () {
      final plan = planFor(
        questionRequest(
          'e1',
          questions: const [
            UserQuestion(id: 'q1', question: '用哪个方案？'),
            UserQuestion(id: 'q2', question: '何时上线？'),
          ],
        ),
        '会话',
      );
      expect(plan.body, '2 个问题待回答：用哪个方案？');
    });

    test('长题干截断到 120 字', () {
      final plan = planFor(
        questionRequest(
          'e1',
          questions: [UserQuestion(id: 'q1', question: '长' * 200)],
        ),
        '会话',
      );
      expect(plan.body.length, 121);
      expect(plan.body.endsWith('…'), isTrue);
    });

    test('plan-review：单题 + intentKind 命中计划文案', () {
      final plan = planFor(
        questionRequest(
          'e2',
          questions: const [
            UserQuestion(
              id: 'plan-review',
              question: 'Approve this plan and leave plan mode?',
              detail: '# 执行计划\n\n第一步：重构数据层\n第二步：补测试',
              intentKind: 'plan-review',
            ),
          ],
        ),
        '重构登录模块',
      );
      expect(plan.title, '「重构登录模块」计划待你确认');
      expect(plan.body, '第一步：重构数据层');
    });

    test('plan-review：detail 为空或全标题行时降级文案', () {
      final empty = planFor(
        questionRequest(
          'e2',
          questions: const [
            UserQuestion(id: 'p', question: '?', intentKind: 'plan-review'),
          ],
        ),
        null,
      );
      expect(empty.title, '有一个计划待确认');
      expect(empty.body, '请审阅执行计划');

      final headingsOnly = planFor(
        questionRequest(
          'e3',
          questions: const [
            UserQuestion(
              id: 'p',
              question: '?',
              detail: '# 标题\n## 子标题',
              intentKind: 'plan-review',
            ),
          ],
        ),
        null,
      );
      expect(headingsOnly.body, '请审阅执行计划');
    });

    test('plan-review 正文截断到 80 字', () {
      final plan = planFor(
        questionRequest(
          'e4',
          questions: [
            UserQuestion(
              id: 'p',
              question: '?',
              detail: '长' * 100,
              intentKind: 'plan-review',
            ),
          ],
        ),
        null,
      );
      expect(plan.body.length, 81);
      expect(plan.body.endsWith('…'), isTrue);
    });

    test('两题的 plan 不按 plan-review 处理（走普通提问文案）', () {
      final plan = planFor(
        questionRequest(
          'e5',
          questions: const [
            UserQuestion(id: 'a', question: '一', intentKind: 'plan-review'),
            UserQuestion(id: 'b', question: '二', intentKind: 'plan-review'),
          ],
        ),
        '会话',
      );
      expect(plan.title, '「会话」等待你的输入');
    });
  });

  group('diffNotifications 镜像同步', () {
    test('新 pending 生成 show，重复不重弹', () {
      final request = questionRequest('e1');
      final first = diffNotifications(pending: [request], shown: const {});
      expect(first.show, hasLength(1));
      expect(first.cancel, isEmpty);

      final again = diffNotifications(
        pending: [request],
        shown: {'e1'},
        resolveTitle: (_) => '会话',
      );
      expect(again.show, isEmpty);
      expect(again.cancel, isEmpty);
    });

    test('pending 消失生成 cancel', () {
      final diff = diffNotifications(pending: const [], shown: {'e1', 'e2'});
      expect(diff.cancel, ['e1', 'e2']);
      expect(diff.show, isEmpty);
    });

    test('重连重放同一 pending：已弹集合不变时幂等', () {
      final request = questionRequest('e1');
      final diff = diffNotifications(pending: [request], shown: {'e1'});
      expect(diff.show, isEmpty);
      expect(diff.cancel, isEmpty);
    });

    test('resolveTitle 提供会话标题', () {
      final diff = diffNotifications(
        pending: [questionRequest('e1')],
        shown: const {},
        resolveTitle: (agentId) => agentId == 'session-1' ? '我的任务' : null,
      );
      expect(diff.show.single.title, '「我的任务」等待你的输入');
    });
  });
}
