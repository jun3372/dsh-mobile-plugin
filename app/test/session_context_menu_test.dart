import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/core/models/dsh_session.dart';
import 'package:dsh_mobile/features/tasks/widgets/session_context_menu.dart';
import 'package:dsh_mobile/features/tasks/widgets/session_row_tile.dart';
import 'package:dsh_mobile/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _sessions = [
  const SessionSummary(sessionId: 'a', title: '绘画页输入框状态优化'),
  const SessionSummary(sessionId: 'b', title: '会话列表长按菜单'),
];

/// 复刻 tasks_page 的接线：Builder 锚点 + 长按弹出上下文菜单。
Widget _harness({
  required List<SessionMenuAction> Function(SessionSummary) actionsOf,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    theme: buildDshTheme(Brightness.light),
    builder: (context, child) => reduceMotion
        ? MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          )
        : child!,
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          for (final session in _sessions)
            Builder(
              builder: (rowContext) => InkWell(
                onTap: () {},
                onLongPress: () {
                  final box = rowContext.findRenderObject()! as RenderBox;
                  showSessionContextMenu(
                    rowContext,
                    anchorRect: box.localToGlobal(Offset.zero) & box.size,
                    preview: SessionRowTile(session: session, pinned: false),
                    actions: actionsOf(session),
                  );
                },
                child: SessionRowTile(session: session, pinned: false),
              ),
            ),
        ],
      ),
    ),
  );
}

List<SessionMenuAction> _defaultActions(SessionSummary session) => [
  SessionMenuAction(
    label: '置顶',
    icon: Icons.push_pin_outlined,
    onTap: () => _tapped.add('置顶'),
  ),
  SessionMenuAction(label: '重命名', icon: Icons.drive_file_rename_outline),
  SessionMenuAction(
    label: '归档',
    icon: Icons.inventory_2_outlined,
    onTap: () => _tapped.add('归档'),
  ),
];

final _tapped = <String>[];

/// 被长按行的清晰副本。
final _previewFinder = find.byKey(const Key('session-row-preview'));

void main() {
  setUp(() => _tapped.clear());

  testWidgets('长按会话行弹出锚定菜单卡，不再走底部面板', (tester) async {
    await tester.pumpWidget(_harness(actionsOf: _defaultActions));

    await tester.longPress(find.text('绘画页输入框状态优化'));
    await tester.pumpAndSettle();

    expect(find.text('置顶'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('归档'), findsOneWidget);
    expect(find.byType(DshSheetTitle), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('清晰副本与被长按的行像素级对齐', (tester) async {
    await tester.pumpWidget(_harness(actionsOf: _defaultActions));

    final before = tester.getRect(
      find.ancestor(
        of: find.text('会话列表长按菜单'),
        matching: find.byType(SessionRowTile),
      ),
    );

    await tester.longPress(find.text('会话列表长按菜单'));
    await tester.pumpAndSettle();

    expect(_previewFinder, findsOneWidget);
    expect(tester.getRect(_previewFinder), before);
  });

  testWidgets('选中动作后浮层关闭并回调一次', (tester) async {
    await tester.pumpWidget(_harness(actionsOf: _defaultActions));

    await tester.longPress(find.text('绘画页输入框状态优化'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('归档'));
    await tester.pumpAndSettle();

    expect(_tapped, ['归档']);
    expect(find.text('置顶'), findsNothing);
    expect(_previewFinder, findsNothing);
    expect(SessionContextMenu.isOpen, isFalse);
  });

  testWidgets('点菜单外区域关闭且不触发动作', (tester) async {
    await tester.pumpWidget(_harness(actionsOf: _defaultActions));

    await tester.longPress(find.text('绘画页输入框状态优化'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(400, 590));
    await tester.pumpAndSettle();

    expect(_tapped, isEmpty);
    expect(find.text('置顶'), findsNothing);
  });

  testWidgets('空间不足时菜单卡翻到行的上方', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDshTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (rowContext) => Align(
              alignment: Alignment.bottomCenter,
              child: InkWell(
                onLongPress: () {
                  final box = rowContext.findRenderObject()! as RenderBox;
                  showSessionContextMenu(
                    rowContext,
                    anchorRect: box.localToGlobal(Offset.zero) & box.size,
                    preview: SessionRowTile(
                      session: _sessions.first,
                      pinned: false,
                    ),
                    actions: _defaultActions(_sessions.first),
                  );
                },
                child: SessionRowTile(session: _sessions.first, pinned: false),
              ),
            ),
          ),
        ),
      ),
    );

    final anchor = tester.getRect(find.byType(SessionRowTile));
    await tester.longPress(find.text('绘画页输入框状态优化'));
    await tester.pumpAndSettle();

    // 菜单卡是浮层里唯一带 Material 的卡片，取最上层那个。
    final cardTop = tester.getRect(find.text('置顶')).top;
    expect(cardTop, lessThan(anchor.top));
  });

  testWidgets('系统要求减少动效时不做高斯模糊', (tester) async {
    await tester.pumpWidget(
      _harness(actionsOf: _defaultActions, reduceMotion: true),
    );

    await tester.longPress(find.text('绘画页输入框状态优化'));
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('置顶'), findsOneWidget);
  });
}
