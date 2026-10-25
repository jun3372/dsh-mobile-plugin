import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/features/servers/pairing_controller.dart';
import 'package:dsh_mobile/features/servers/widgets/pairing_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用可控的假绑定器替换真实网络流程，保留 provider 状态驱动。
class _FakePairingController extends PairingController {
  _FakePairingController({required this.succeeds, this.errorMessage});

  final bool succeeds;
  final String? errorMessage;

  static final _origin = Uri.parse('http://192.168.1.5:39081');

  @override
  PairingState build() => const PairingState();

  @override
  Future<bool> bind(
    String raw, {
    String? manualPassword,
    void Function(PairingState state)? onStage,
  }) async {
    void emit(PairingState next) {
      state = next;
      onStage?.call(next);
    }

    emit(PairingState(status: PairingStatus.checking, origin: _origin));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    emit(
      succeeds
          ? PairingState(status: PairingStatus.success, origin: _origin)
          : PairingState(
              status: PairingStatus.failed,
              message: errorMessage ?? '绑定失败',
              origin: _origin,
            ),
    );
    return succeeds;
  }
}

void main() {
  /// 拦截系统通道，收集震动/音效调用，验证反馈确实触发。
  List<MethodCall> recordPlatformCalls() {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return calls;
  }

  Future<Future<bool?> Function()> pumpHarness(
    WidgetTester tester,
    _FakePairingController fake,
  ) async {
    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pairingControllerProvider.overrideWith(() => fake)],
        child: MaterialApp(
          theme: buildDshTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async {
                    result = await PairingProgressDialog.show(
                      context,
                      'payload',
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return () async => result;
  }

  testWidgets('进度弹窗展示当前阶段与服务端，成功后自动关闭', (tester) async {
    final calls = recordPlatformCalls();
    final fake = _FakePairingController(succeeds: true);
    final readResult = await pumpHarness(tester, fake);
    await tester.pump();

    await tester.tap(find.text('打开'));
    await tester.pump(); // 挂载弹窗并触发首帧绑定
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('正在连接服务端…'), findsOneWidget);
    expect(find.text('192.168.1.5:39081'), findsOneWidget);
    // 阶段切换的 AnimatedSwitcher 过渡期内可能有新旧两个转圈。
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('绑定成功'), findsOneWidget);

    // 成功态停留 650ms 后自动收起。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(await readResult(), isTrue);
    // 成功反馈：点击音 + 两段震动（medium/light）。
    expect(
      calls.any(
        (call) =>
            call.method == 'SystemSound.play' &&
            call.arguments == 'SystemSoundType.click',
      ),
      isTrue,
    );
    expect(
      calls.where((call) => call.method == 'HapticFeedback.vibrate').length,
      greaterThanOrEqualTo(2),
    );
  });

  testWidgets('失败时留在弹窗内展示原因，可关闭返回扫码', (tester) async {
    final calls = recordPlatformCalls();
    final fake = _FakePairingController(
      succeeds: false,
      errorMessage: '访问密码不正确',
    );
    final readResult = await pumpHarness(tester, fake);
    await tester.pump();

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('绑定失败'), findsOneWidget);
    expect(find.text('访问密码不正确'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    // 等图标过渡结束，转圈应完全消失。
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 失败反馈：告警音 + 两次重震。
    expect(
      calls.any(
        (call) =>
            call.method == 'SystemSound.play' &&
            call.arguments == 'SystemSoundType.alert',
      ),
      isTrue,
    );
    expect(
      calls.where((call) => call.method == 'HapticFeedback.vibrate').length,
      greaterThanOrEqualTo(2),
    );

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(await readResult(), isFalse);
  });
}
