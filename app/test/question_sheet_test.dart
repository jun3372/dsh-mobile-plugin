import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/core/models/dsh_models.dart';
import 'package:dsh_mobile/core/services/dsh_api.dart' show QuestionAnswer;
import 'package:dsh_mobile/core/session/session_replica.dart';
import 'package:dsh_mobile/features/sessions/widgets/question_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SessionQuestionPrompt buildPrompt({
    required List<UserQuestion> questions,
    String? eventId = 'e1',
    String state = 'open',
  }) => SessionQuestionPrompt(
    eventId: eventId,
    callId: 'c1',
    agentId: 'a1',
    questions: questions,
    state: state,
  );

  UserQuestion singleChoice() => const UserQuestion(
    id: 'q1',
    header: '项目定位',
    question: '你想要的"短视频 APP"和现有 honghuo 项目是什么关系？',
    options: [
      QuestionOption(
        label: '全新独立 App（推荐）',
        description: '从零起一个新 Flutter 工程，做抖音式单条短视频信息流。',
      ),
      QuestionOption(label: '在 honghuo 上演进', description: '不新建工程，复用现有设计系统与后端。'),
    ],
  );

  /// 打开 sheet；[remainingMs] 非空时 sheet 内有周期 tick，须用 pump 步进。
  Future<void> openSheet(
    WidgetTester tester, {
    required SessionQuestionPrompt prompt,
    int? remainingMs,
    void Function(List<QuestionAnswer>)? onAnswer,
    void Function()? onSkip,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDshTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showQuestionSheet(
                  ctx,
                  prompt: prompt,
                  remainingMs: remainingMs,
                  onAnswer: (answers) async => onAnswer?.call(answers),
                  onSkip: onSkip == null ? null : () async => onSkip(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets('渲染复刻截图：标题/header/加粗问题/垂直选项/描述/推荐徽标', (tester) async {
    await openSheet(tester, prompt: buildPrompt(questions: [singleChoice()]));

    expect(find.text('请回答以下问题'), findsOneWidget);
    expect(find.text('项目定位'), findsOneWidget);
    expect(find.textContaining('短视频 APP'), findsOneWidget);
    // label 净化 + 「推荐」独立徽标；选项垂直堆叠，不再用 Wrap chip。
    expect(find.text('全新独立 App'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.textContaining('抖音式单条短视频信息流'), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('instantPick：点选项直接提交并关闭 sheet', (tester) async {
    final captured = <List<QuestionAnswer>>[];
    await openSheet(
      tester,
      prompt: buildPrompt(questions: [singleChoice()]),
      onAnswer: captured.add,
    );

    await tester.tap(find.text('在 honghuo 上演进'));
    await tester.pumpAndSettle();

    expect(captured, hasLength(1));
    expect(captured.single.single.questionId, 'q1');
    expect(captured.single.single.selected, ['在 honghuo 上演进']);
    expect(captured.single.single.custom, isNull);
    expect(find.text('请回答以下问题'), findsNothing);
  });

  testWidgets('instantPick：底部自定义输入提交携带 custom、selected 为空', (tester) async {
    final captured = <List<QuestionAnswer>>[];
    await openSheet(
      tester,
      prompt: buildPrompt(questions: [singleChoice()]),
      onAnswer: captured.add,
    );

    await tester.enterText(find.byType(TextField), '换个思路');
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(captured.single.single.custom, '换个思路');
    expect(captured.single.single.selected, isEmpty);
  });

  testWidgets('multiSelect：先禁用后启用，提交含两项选择与内联自定义', (tester) async {
    final captured = <List<QuestionAnswer>>[];
    const multi = UserQuestion(
      id: 'q2',
      question: '要包含哪些端？',
      multiSelect: true,
      options: [
        QuestionOption(label: 'Android'),
        QuestionOption(label: '鸿蒙'),
      ],
    );
    await openSheet(
      tester,
      prompt: buildPrompt(questions: [multi]),
      onAnswer: captured.add,
    );

    FilledButton submit() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '提交回答'));
    expect(submit().onPressed, isNull);

    await tester.tap(find.text('Android'));
    await tester.pump();
    await tester.tap(find.text('鸿蒙'));
    await tester.pump();
    expect(submit().onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), '只要平板适配');
    await tester.pump();
    await tester.tap(find.text('提交回答'));
    await tester.pumpAndSettle();

    final answer = captured.single.single;
    expect(answer.selected, ['Android', '鸿蒙']);
    expect(answer.custom, '只要平板适配');
    expect(find.text('请回答以下问题'), findsNothing);
  });

  testWidgets('多题分页：单选点完自动切题，多选停留，末页提交', (tester) async {
    final captured = <List<QuestionAnswer>>[];
    const q1 = UserQuestion(
      id: 'p1',
      question: '放在哪里？',
      options: [
        QuestionOption(label: '当前仓库'),
        QuestionOption(label: '新仓库'),
      ],
    );
    const q2 = UserQuestion(
      id: 'p2',
      question: '要哪些端？',
      multiSelect: true,
      options: [
        QuestionOption(label: '鸿蒙'),
        QuestionOption(label: '安卓'),
      ],
    );
    const q3 = UserQuestion(
      id: 'p3',
      question: '数据来源？',
      options: [
        QuestionOption(label: 'Mock'),
        QuestionOption(label: '真实后端'),
      ],
    );
    await openSheet(
      tester,
      prompt: buildPrompt(questions: [q1, q2, q3]),
      onAnswer: captured.add,
    );

    // 第一页只渲染 q1，页码 1/3。
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('放在哪里？'), findsOneWidget);
    expect(find.text('数据来源？'), findsNothing);

    // 单选点完 → 短暂露出勾选后自动切到 2/3，无需按「下一个问题」。
    await tester.tap(find.text('当前仓库'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('要哪些端？'), findsOneWidget);

    // 多选点选不自动跳页。
    await tester.tap(find.text('鸿蒙'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    await tester.tap(find.text('下一个问题'));
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);

    // 末页：三题答完前「提交回答」禁用；q3 单选点完不再前进。
    FilledButton submit() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '提交回答'));
    expect(submit().onPressed, isNull);
    await tester.tap(find.text('Mock'));
    await tester.pump();
    expect(find.text('3/3'), findsOneWidget);
    expect(submit().onPressed, isNotNull);
    await tester.tap(find.text('提交回答'));
    await tester.pumpAndSettle();

    final answers = captured.single;
    expect(answers, hasLength(3));
    expect(answers[0].questionId, 'p1');
    expect(answers[0].selected, ['当前仓库']);
    expect(answers[1].questionId, 'p2');
    expect(answers[1].selected, ['鸿蒙']);
    expect(answers[2].questionId, 'p3');
    expect(answers[2].selected, ['Mock']);
    expect(find.text('请回答以下问题'), findsNothing);
  });

  testWidgets('跳过：waterfall 显示并回调；continued 隐藏且有提示', (tester) async {
    var skipTaps = 0;
    await openSheet(
      tester,
      prompt: buildPrompt(questions: [singleChoice()]),
      onSkip: () => skipTaps++,
    );
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(skipTaps, 1);

    // continued（无 eventId）：没有拒绝通道，隐藏跳过并提示直接回填。
    await openSheet(
      tester,
      prompt: buildPrompt(
        questions: [singleChoice()],
        eventId: null,
        state: 'continued',
      ),
    );
    expect(find.text('跳过'), findsNothing);
    expect(find.text('该提问已离开实时窗口，提交后将直接回填'), findsOneWidget);
  });

  testWidgets('倒计时：25s 显示红色剩余并逐秒递减', (tester) async {
    await openSheet(
      tester,
      prompt: buildPrompt(questions: [singleChoice()]),
      remainingMs: 25000,
      settle: false,
    );
    final urgent = tester.widget<Text>(find.text('剩余 00:25'));
    expect(urgent.style?.color, DshPalette.light.dangerRed);
    // 本地 tick 每秒递减（超时动作由 notifier 权威驱动，此处仅展示）。
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('剩余 00:24'), findsOneWidget);
  });

  testWidgets('倒计时：45s 用常规色', (tester) async {
    await openSheet(
      tester,
      prompt: buildPrompt(questions: [singleChoice()]),
      remainingMs: 45000,
      settle: false,
    );
    final calm = tester.widget<Text>(find.text('剩余 00:45'));
    expect(calm.style?.color, isNot(DshPalette.light.dangerRed));
  });

  testWidgets('键盘弹起（底部 inset 300）无布局溢出', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await openSheet(
      tester,
      prompt: buildPrompt(questions: [singleChoice()]),
      settle: false,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('请回答以下问题'), findsOneWidget);
  });

  testWidgets('splitRecommended 剥中英文推荐后缀', (tester) async {
    expect(splitRecommended('全新独立 App（推荐）'), (
      label: '全新独立 App',
      recommended: true,
    ));
    expect(splitRecommended('Option A (Recommended)'), (
      label: 'Option A',
      recommended: true,
    ));
    expect(splitRecommended('无标记'), (label: '无标记', recommended: false));
  });
}
