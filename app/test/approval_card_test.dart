import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/core/models/approval_request.dart';
import 'package:dsh_mobile/core/models/dsh_models.dart';
import 'package:dsh_mobile/core/session/session_replica.dart';
import 'package:dsh_mobile/features/sessions/session_providers.dart';
import 'package:dsh_mobile/features/sessions/widgets/approval_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: buildDshTheme(Brightness.light),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 360, child: SingleChildScrollView(child: child)),
      ),
    ),
  );

  ApprovalRequest planApproval() => const ApprovalRequest(
    eventId: 'e1',
    agentId: 'a1',
    toolName: 'ExitPlanMode',
    displayReason: '已写好计划，可以开始执行。',
  );

  testWidgets('计划审批渲染计划卡：表头+摘要+建议修改/允许一次', (tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      wrap(
        ApprovalCard(
          approval: planApproval(),
          onAnswer: (allowed) async => answers.add(allowed),
          onFeedback: (_) async {},
        ),
      ),
    );

    expect(find.text('计划'), findsOneWidget);
    expect(find.text('已写好计划，可以开始执行。'), findsOneWidget);
    expect(find.text('建议修改'), findsOneWidget);
    expect(find.text('允许一次'), findsOneWidget);
    expect(find.text('需要你的确认'), findsNothing);

    // 「允许一次」走 allowed=true 回填。
    await tester.tap(find.text('允许一次'));
    await tester.pump();
    expect(answers, [true]);
  });

  testWidgets('建议修改展开反馈框：提交反馈先空禁用、填词后拒绝并回传文本', (tester) async {
    final answers = <bool>[];
    final feedbacks = <String>[];
    await tester.pumpWidget(
      wrap(
        ApprovalCard(
          approval: planApproval(),
          onAnswer: (allowed) async => answers.add(allowed),
          onFeedback: (text) async => feedbacks.add(text),
        ),
      ),
    );

    await tester.tap(find.text('建议修改'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('计划中有哪些需要调整？'), findsOneWidget);
    // 展开态按钮换位：左「允许一次」右「提交反馈」。
    expect(find.text('建议修改'), findsNothing);
    expect(find.text('提交反馈'), findsOneWidget);
    expect(find.text('允许一次'), findsOneWidget);

    // 空文本时「提交反馈」禁用，点击无副作用。
    await tester.tap(find.text('提交反馈'));
    await tester.pump();
    expect(feedbacks, isEmpty);
    expect(answers, isEmpty);

    await tester.enterText(find.byType(TextField), '第二步拆细一点');
    await tester.pump();
    await tester.tap(find.text('提交反馈'));
    await tester.pump();
    expect(feedbacks, ['第二步拆细一点']);

    // 展开态「允许一次」仍可批准。
    await tester.tap(find.text('允许一次'));
    await tester.pump();
    expect(answers, [true]);
  });

  testWidgets('计划卡渲染 markdown 正文预览，点表头进入计划详情全文页', (tester) async {
    final plan =
        '# 实施计划\n\n## 阶段一\n${List.generate(40, (i) => '第 $i 步：构建一条足够长的计划条目以触发限高渐隐预览。').join('\n')}';
    await tester.pumpWidget(
      wrap(
        ApprovalCard(
          approval: const ApprovalRequest(
            eventId: 'e3',
            agentId: 'a1',
            toolName: 'exit_plan_mode',
            callId: 'call-1',
          ),
          planText: plan,
          onAnswer: (_) async {},
        ),
      ),
    );

    expect(find.text('计划'), findsOneWidget);
    // markdown 标题渲染进预览正文，超长内容被限高但不溢出报错。
    expect(find.textContaining('实施计划'), findsWidgets);
    expect(find.textContaining('阶段一'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    expect(find.text('计划详情'), findsOneWidget);
    // 全文页能看到预览里被裁掉的尾部条目。
    expect(find.textContaining('第 39 步'), findsOneWidget);
  });

  testWidgets('短计划不走限高渐隐', (tester) async {
    await tester.pumpWidget(
      wrap(
        ApprovalCard(
          approval: const ApprovalRequest(
            eventId: 'e4',
            agentId: 'a1',
            toolName: 'ExitPlanMode',
            callId: 'call-2',
          ),
          planText: '# 小计划\n\n- 一步\n- 两步',
          onAnswer: (_) async {},
        ),
      ),
    );
    expect(find.textContaining('小计划'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ApprovalCard),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets('非计划工具仍渲染通用审批卡', (tester) async {
    await tester.pumpWidget(
      wrap(
        ApprovalCard(
          approval: const ApprovalRequest(
            eventId: 'e2',
            agentId: 'a1',
            toolName: 'Bash',
            displayReason: '要执行一条命令',
          ),
          onAnswer: (_) async {},
        ),
      ),
    );

    expect(find.text('需要你的确认'), findsOneWidget);
    expect(find.text('Bash'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);
    expect(find.text('允许一次'), findsOneWidget);
    expect(find.text('计划'), findsNothing);
  });

  UserQuestion planReviewQuestion() => const UserQuestion(
    id: 'plan-review',
    question: 'Approve this plan and leave plan mode?',
    header: 'Plan review',
    detail: '# 演示计划\n\n## 阶段一\n搭建工程骨架',
    options: [
      QuestionOption(label: 'Approve', description: '离开计划模式并开始执行'),
      QuestionOption(label: 'Keep planning', description: '留在计划模式并回传反馈'),
    ],
    intentKind: 'plan-review',
    intentApprove: 'Approve',
  );

  SessionQuestionPrompt planReviewPrompt() => SessionQuestionPrompt(
    agentId: 'a1',
    eventId: 'ev-1',
    questions: [planReviewQuestion()],
  );

  test('planReview 收窄：intent 命中且选项含 approve 标签', () {
    final review = planReviewPrompt().planReview;
    expect(review, isNotNull);
    expect(review!.plan, contains('演示计划'));
    expect(review.approve.label, 'Approve');
    expect(review.decline?.label, 'Keep planning');
    // 普通问答不命中。
    expect(
      SessionQuestionPrompt(
        agentId: 'a1',
        eventId: 'ev-2',
        questions: [
          const UserQuestion(
            id: 'q1',
            question: '选个方案',
            detail: '说明',
            options: [
              QuestionOption(label: 'A'),
              QuestionOption(label: 'B'),
            ],
          ),
        ],
      ).planReview,
      isNull,
    );
  });

  test('底部输入区路由：pendingPlanReview 命中首个计划评审，普通问答不命中', () {
    final prompt = planReviewPrompt();
    final plain = SessionQuestionPrompt(
      agentId: 'a1',
      eventId: 'ev-2',
      questions: [
        const UserQuestion(
          id: 'q1',
          question: '选个方案',
          detail: '说明',
          options: [
            QuestionOption(label: 'A'),
            QuestionOption(label: 'B'),
          ],
        ),
      ],
    );
    final pending = SessionViewState(
      questions: [plain, prompt],
    ).pendingPlanReview;
    expect(pending, isNotNull);
    expect(pending!.prompt, same(prompt));
    expect(pending.review.plan, contains('演示计划'));
    expect(SessionViewState(questions: [plain]).pendingPlanReview, isNull);
    expect(const SessionViewState().pendingPlanReview, isNull);
  });

  testWidgets('计划评审正文卡渲染计划内容而非问答选项', (tester) async {
    final review = planReviewPrompt().planReview!;
    await tester.pumpWidget(wrap(PlanReviewContentCard(review: review)));

    expect(find.text('计划'), findsOneWidget);
    expect(find.textContaining('演示计划'), findsWidgets);
    // 不走问答卡：没有选项行与「回答」入口；按钮在底部动作条。
    expect(find.text('回答'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('建议修改'), findsNothing);
    expect(find.text('允许一次'), findsNothing);
  });

  testWidgets('计划评审动作条点「允许一次」回填 approve', (tester) async {
    final approved = <String?>[];
    final review = planReviewPrompt().planReview!;
    await tester.pumpWidget(
      wrap(
        PlanReviewActionBar(
          review: review,
          onApprove: () async => approved.add(null),
          onFeedback: (text) async => approved.add(text),
        ),
      ),
    );

    expect(find.text('计划'), findsOneWidget);
    expect(find.text('已写好计划，可以开始执行。'), findsOneWidget);
    expect(find.text('建议修改'), findsOneWidget);
    expect(find.text('允许一次'), findsOneWidget);

    await tester.tap(find.text('允许一次'));
    await tester.pump();
    expect(approved, [null]);
  });

  testWidgets('计划评审动作条「建议修改」展开反馈：提交回填 decline+custom', (tester) async {
    final approved = <String?>[];
    final review = planReviewPrompt().planReview!;
    await tester.pumpWidget(
      wrap(
        PlanReviewActionBar(
          review: review,
          onApprove: () async => approved.add(null),
          onFeedback: (text) async => approved.add(text),
        ),
      ),
    );

    await tester.tap(find.text('建议修改'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('提交反馈'), findsOneWidget);

    // 空文本禁用，填词后提交。
    await tester.tap(find.text('提交反馈'));
    await tester.pump();
    expect(approved, isEmpty);
    await tester.enterText(find.byType(TextField), '第二步拆细一点');
    await tester.pump();
    await tester.tap(find.text('提交反馈'));
    await tester.pump();
    expect(approved, ['第二步拆细一点']);
  });

  testWidgets('计划评审正文卡点表头进入计划详情全文页', (tester) async {
    final review = planReviewPrompt().planReview!;
    await tester.pumpWidget(wrap(PlanReviewContentCard(review: review)));

    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    expect(find.text('计划详情'), findsOneWidget);
  });
}
