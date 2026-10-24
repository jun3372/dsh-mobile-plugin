import 'dart:async';

import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/features/sessions/widgets/session_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(theme: buildDshTheme(Brightness.light), home: child);

  final details = SessionDetails(
    sessionId: 'qs_01m5p9zrjqxa45wrk1jfn5d6r0',
    title: '参考这两张图优化一下计划模式下的计划弹窗部分的布局和样式',
    projectName: 'dsh-mobile-plugin',
    model: 'DeepSeek-Flash',
    environment: 'zhoujundeMacBook-Air.local',
    createdAt: DateTime(2026, 10, 24, 2, 36),
    updatedAt: DateTime(2026, 10, 24, 2, 36),
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(wrap(Scaffold(body: Container())));
    final context = tester.element(find.byType(Scaffold));
    unawaited(showSessionDetailsSheet(context, details: details));
    await tester.pumpAndSettle();
  }

  testWidgets('详情弹层渲染标题/任务 ID/元数据行', (tester) async {
    await openSheet(tester);

    expect(find.text('详情'), findsOneWidget);
    expect(find.text(details.title!), findsOneWidget);
    expect(find.text('dsh-mobile-plugin'), findsOneWidget);
    expect(find.text('任务 ID'), findsOneWidget);
    expect(find.text(details.sessionId), findsOneWidget);
    expect(find.text('元数据'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('DeepSeek-Flash'), findsOneWidget);
    expect(find.text('运行环境'), findsOneWidget);
    expect(find.text('zhoujundeMacBook-Air.local'), findsOneWidget);
    // 时间格式：2026年10月24日 02:36
    expect(find.text('创建时间'), findsOneWidget);
    expect(find.text('2026年10月24日 02:36'), findsNWidgets(2));
    expect(find.text('最后更新时间'), findsOneWidget);
  });

  testWidgets('缺失可选元数据时隐藏对应行并兜底', (tester) async {
    await tester.pumpWidget(wrap(Scaffold(body: Container())));
    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showSessionDetailsSheet(
        context,
        details: const SessionDetails(sessionId: 'qs_min'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新任务'), findsOneWidget);
    expect(find.text('未选择'), findsOneWidget);
    expect(find.text('创建时间'), findsNothing);
    expect(find.text('最后更新时间'), findsNothing);
  });

  testWidgets('复制钮写入剪贴板，关闭钮收起弹层', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await openSheet(tester);

    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();
    expect(copied, details.sessionId);
    // 复制成功：图标切换为绿色对勾（弹层内反馈，SnackBar 会被弹层遮挡）。
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    // 1.5s 后复原。
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsNothing);
  });
}
