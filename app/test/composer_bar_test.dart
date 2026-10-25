import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/core/models/composer_models.dart';
import 'package:dsh_mobile/core/services/api_client.dart';
import 'package:dsh_mobile/core/services/dsh_api.dart';
import 'package:dsh_mobile/widgets/composer/attachment_sources.dart';
import 'package:dsh_mobile/widgets/composer/attachment_store.dart';
import 'package:dsh_mobile/widgets/composer/composer_bar.dart';
import 'package:dsh_mobile/widgets/composer/composer_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ComposerController controller;

  setUp(() {
    controller = ComposerController(
      sessionId: 's1',
      sources: const [],
      attachments: AttachmentStore(
        api: DshApi(ApiClient(origin: Uri.parse('http://h:1'), password: 'p')),
        sessionId: 's1',
      ),
      ports: ComposerPorts(
        send: (_, _, _) async {},
        executeCommand: (_, _) async =>
            const CommandExecution(matched: true, ok: true),
      ),
    );
  });

  tearDown(() => controller.dispose());

  Widget wrap({
    required ComposerViewData view,
    required VoidCallback onCancel,
  }) {
    return MaterialApp(
      theme: buildDshTheme(Brightness.light),
      home: Scaffold(
        body: ComposerBar(
          controller: controller,
          view: view,
          sources: AttachmentSources(),
          actions: ComposerActions(
            showModelPicker: () {},
            showPermissionPicker: () {},
            togglePlan: () {},
            showGoalEditor: () {},
            cancelTurn: onCancel,
            hostCommands: () async => const [],
          ),
          onError: (_) {},
        ),
      ),
    );
  }

  testWidgets('收起态主按钮随运行状态在发送与停止之间切换', (tester) async {
    var running = false;
    var cancelled = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return wrap(
            view: ComposerViewData(ready: true, running: running),
            onCancel: () => cancelled++,
          );
        },
      ),
    );

    // 空闲且空草稿：收起态右侧为发送箭头。
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);

    // 运行中：同一位置换成停止钮，点击触发取消。
    rebuild(() => running = true);
    await tester.pump();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    expect(cancelled, 1);
  });

  testWidgets('空闲收起态点击发送箭头展开输入卡', (tester) async {
    await tester.pumpWidget(
      wrap(view: const ComposerViewData(ready: true), onCancel: () {}),
    );

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
  });
}
