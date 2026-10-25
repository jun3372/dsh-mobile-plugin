import 'package:dsh_mobile/widgets/composer/composer_document.dart';
import 'package:dsh_mobile/widgets/composer/trigger_menu_controller.dart';
import 'package:dsh_mobile/widgets/composer/trigger_sources.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource extends TriggerSource {
  final ComposerTriggerKind kind;
  final List<TriggerItem> Function(String query) build;
  int calls = 0;

  _FakeSource({required this.kind, required this.build});

  @override
  String get groupTitle => kind == ComposerTriggerKind.slash ? '指令' : '文件';

  @override
  bool accepts(ComposerTriggerKind target) => target == kind;

  @override
  Future<List<TriggerItem>> candidates(String query) async {
    calls++;
    return build(query);
  }
}

void main() {
  const commands = [
    TriggerItem(title: '/plan', insertion: '/plan '),
    TriggerItem(title: '/permission', insertion: '/permission '),
  ];
  const files = [
    TriggerItem(title: 'src', subtitle: 'src', insertion: '@src/', drill: true),
    TriggerItem(title: 'a.md', subtitle: 'a.md', insertion: '@a.md'),
  ];

  TriggerMenuController build({
    required List<String> edits,
    List<TriggerSource>? sources,
  }) {
    return TriggerMenuController(
      sources:
          sources ??
          [
            _FakeSource(
              kind: ComposerTriggerKind.slash,
              build: (_) => commands,
            ),
            _FakeSource(kind: ComposerTriggerKind.at, build: (_) => files),
          ],
      onDraftEdited: (text, caret) => edits.add('$text|$caret'),
      onActionPick: (_) {},
      debounce: const Duration(milliseconds: 20),
    );
  }

  testWidgets('空查询立即出菜单，继续输入走防抖', (tester) async {
    final edits = <String>[];
    final controller = build(edits: edits);
    addTearDown(controller.dispose);

    controller.onDraftChanged('/', 1);
    await tester.pump();
    expect(controller.isOpen, isTrue);
    expect(controller.groups.single.title, '指令');
    final slashCalls = (controller.sources.first as _FakeSource).calls;
    expect(slashCalls, 1);

    controller.onDraftChanged('/pe', 3);
    await tester.pump();
    expect((controller.sources.first as _FakeSource).calls, slashCalls);
    await tester.pump(const Duration(milliseconds: 30));
    expect((controller.sources.first as _FakeSource).calls, slashCalls + 1);
  });

  testWidgets('点行选定：写回草稿并关闭菜单', (tester) async {
    final edits = <String>[];
    final controller = build(edits: edits);
    addTearDown(controller.dispose);

    controller.onDraftChanged('看 /pl', 5);
    await tester.pump(const Duration(milliseconds: 30));
    controller.pick(controller.currentItem!);
    expect(controller.isOpen, isFalse);
    expect(edits.single, '看 /plan |8');
  });

  testWidgets('目录行选定后保持打开并停在尾斜杠继续下钻', (tester) async {
    final edits = <String>[];
    final controller = build(edits: edits);
    addTearDown(controller.dispose);

    controller.onDraftChanged('@s', 2);
    await tester.pump(const Duration(milliseconds: 30));
    final dir = controller.groups.first.items.first;
    expect(dir.drill, isTrue);
    controller.pick(dir);
    expect(edits.single, '@src/|5');
    await tester.pump(const Duration(milliseconds: 30));
    // 菜单未关，且以新 query（src/）重新拉了一次候选。
    expect(controller.isOpen, isTrue);
    expect(controller.trigger?.query, 'src/');
  });

  testWidgets('指针关闭后，同 token 同查询不重开；输入新查询重新武装', (tester) async {
    final edits = <String>[];
    final controller = build(edits: edits);
    addTearDown(controller.dispose);

    controller.onDraftChanged('@s', 2);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.isOpen, isTrue);

    controller.dismiss();
    expect(controller.isOpen, isFalse);
    controller.onDraftChanged('@s', 2);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.isOpen, isFalse);

    controller.onDraftChanged('@sr', 3);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.isOpen, isTrue);
  });

  testWidgets('外部点击关闭从不改写草稿', (tester) async {
    final edits = <String>[];
    final controller = build(edits: edits);
    addTearDown(controller.dispose);

    controller.onDraftChanged('@s', 2);
    await tester.pump(const Duration(milliseconds: 30));
    controller.dismiss();
    expect(edits, isEmpty);
  });

  testWidgets('已认领命令时 / 抑制、@ 仍可用', (tester) async {
    final edits = <String>[];
    final controller = build(edits: edits);
    addTearDown(controller.dispose);

    controller.guard = TriggerGuard.claimed;
    controller.onDraftChanged('/plan off /pe', 13);
    await tester.pump();
    expect(controller.isOpen, isFalse);

    controller.onDraftChanged('/plan off @s', 12);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.isOpen, isTrue);
    expect(controller.groups.single.title, '文件');
  });

  testWidgets('↑/↓ 在扁平列表上循环，纯 UI 动作候选先关菜单', (tester) async {
    final edits = <String>[];
    var actions = 0;
    final controller = TriggerMenuController(
      sources: [
        _FakeSource(
          kind: ComposerTriggerKind.slash,
          build: (_) => [
            ...commands,
            const TriggerItem(title: '/model', onPick: _noop),
          ],
        ),
      ],
      onDraftEdited: (text, caret) => edits.add(text),
      onActionPick: (_) => actions++,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    controller.onDraftChanged('/', 1);
    await tester.pump();
    expect(controller.highlight, 0);
    controller.moveHighlight(-1);
    expect(controller.highlight, 2);
    controller.moveHighlight(1);
    expect(controller.highlight, 0);

    controller.pick(controller.groups.first.items.last);
    expect(actions, 1);
    expect(controller.isOpen, isFalse);
    expect(edits, isEmpty);
  });

  testWidgets('单源失败只丢该分组，其它分组照常', (tester) async {
    final edits = <String>[];
    final controller = build(
      edits: edits,
      sources: [
        _FakeSource(kind: ComposerTriggerKind.at, build: (_) => files),
        _BrokenSource(),
      ],
    );
    addTearDown(controller.dispose);

    controller.onDraftChanged('@s', 2);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.groups.length, 1);
    expect(controller.groups.single.items, isNotEmpty);
  });

  testWidgets('候选为空时不高亮越界，菜单保持打开等待继续输入', (tester) async {
    final controller = build(
      edits: [],
      sources: [
        _FakeSource(kind: ComposerTriggerKind.slash, build: (_) => const []),
      ],
    );
    addTearDown(controller.dispose);

    controller.onDraftChanged('/zz', 3);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.isOpen, isTrue);
    expect(controller.groups, isEmpty);
    expect(controller.currentItem, isNull);
    expect(controller.highlight, 0);
    controller.moveHighlight(1);
    expect(controller.highlight, 0);
  });
}

void _noop() {}

class _BrokenSource extends TriggerSource {
  @override
  String get groupTitle => '对话';

  @override
  bool accepts(ComposerTriggerKind kind) => kind == ComposerTriggerKind.at;

  @override
  Future<List<TriggerItem>> candidates(String query) async {
    throw Exception('宿主未挂该插件');
  }
}
