import 'package:dsh_mobile/app/app.dart';
import 'package:dsh_mobile/features/servers/onboarding_page.dart';
import 'package:dsh_mobile/features/servers/servers_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const DshApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('未绑定服务端时展示扫码引导页', (tester) async {
    await _pumpApp(tester);
    expect(find.text('探索未至之境'), findsWidgets);
    expect(find.text('扫码绑定 DSH 服务端'), findsOneWidget);
    expect(find.byType(OnboardingPage), findsOneWidget);
  });
}
