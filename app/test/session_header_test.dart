import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/features/sessions/widgets/session_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: buildDshTheme(Brightness.light),
    home: Scaffold(body: child),
  );

  testWidgets('标题栏展示标题/服务端名，文件夹与更多分别回调', (tester) async {
    var folderTaps = 0;
    var moreTaps = 0;
    var titleTaps = 0;

    await tester.pumpWidget(
      wrap(
        SessionHeader(
          title: '调整会话输入框插件布局',
          serverName: 'zhoujundeMacBook-Air.local',
          onBack: () {},
          onFolder: () => folderTaps++,
          onMore: (_) => moreTaps++,
          onTitleTap: () => titleTaps++,
        ),
      ),
    );

    expect(find.text('调整会话输入框插件布局'), findsOneWidget);
    expect(find.text('zhoujundeMacBook-Air.local'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.computer_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pump();
    expect(folderTaps, 1);
    expect(moreTaps, 0);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pump();
    expect(moreTaps, 1);

    // 点击标题区触发详情弹层回调。
    await tester.tap(find.text('调整会话输入框插件布局'));
    await tester.pump();
    expect(titleTaps, 1);
  });

  testWidgets('缺少标题与服务端时展示兜底文案', (tester) async {
    await tester.pumpWidget(
      wrap(
        SessionHeader(
          title: null,
          serverName: null,
          onBack: () {},
          onFolder: () {},
          onMore: (_) {},
        ),
      ),
    );

    expect(find.text('新任务'), findsOneWidget);
    expect(find.text('本地服务端'), findsOneWidget);
  });
}
