import 'package:dsh_mobile/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppBar 返回图标尺寸跟随主题标题栏 token', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        theme: buildDshTheme(Brightness.light),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(appBar: AppBar(title: const Text('已归档'))),
      ),
    );
    await tester.pumpAndSettle();

    final iconFinder = find.descendant(
      of: find.byType(BackButton),
      matching: find.byType(Icon),
    );
    expect(find.byType(BackButton), findsOneWidget);
    // 默认 BackButton 不自带尺寸，由 AppBar 的 IconTheme 决定。
    expect(IconTheme.of(tester.element(iconFinder)).size, DshIcon.header);
    // 主题收紧 leadingWidth（默认 56），返回箭头两侧留白同步变小。
    expect(tester.getSize(find.byType(BackButton)).width, 48);
  });
}
