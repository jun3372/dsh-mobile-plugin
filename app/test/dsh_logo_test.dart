import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/widgets/dsh_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<SvgPicture> pumpLogo(
    WidgetTester tester,
    Brightness brightness,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDshTheme(brightness),
        home: const Scaffold(body: Center(child: DshLogo(height: 28))),
      ),
    );
    return tester.widget<SvgPicture>(find.byType(SvgPicture));
  }

  testWidgets('标志用 SVG 渲染，浅色主题着墨黑', (tester) async {
    final svg = await pumpLogo(tester, Brightness.light);

    expect(find.byType(Image), findsNothing);
    expect(
      svg.colorFilter,
      ColorFilter.mode(DshPalette.light.foreground, BlendMode.srcIn),
    );
  });

  testWidgets('深色主题切换为亮白，避免黑鲸不可见', (tester) async {
    final svg = await pumpLogo(tester, Brightness.dark);

    expect(
      svg.colorFilter,
      ColorFilter.mode(DshPalette.dark.foreground, BlendMode.srcIn),
    );
  });
}
