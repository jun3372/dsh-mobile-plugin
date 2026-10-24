import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_mobile/core/errors.dart';
import 'package:dsh_mobile/core/models/composer_models.dart';
import 'package:dsh_mobile/core/services/api_client.dart';
import 'package:dsh_mobile/core/services/dsh_api.dart';
import 'package:dsh_mobile/widgets/composer/attachment_store.dart';
import 'package:dsh_mobile/widgets/composer/composer_controller.dart';
import 'package:dsh_mobile/widgets/composer/composer_document.dart';
import 'package:dsh_mobile/widgets/composer/composer_draft_store.dart';
import 'package:dsh_mobile/widgets/composer/trigger_menu_controller.dart';
import 'package:dsh_mobile/widgets/composer/trigger_sources.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Directory tempDir = Directory.systemTemp;

Future<String> writeFile(String name, List<int> bytes) async {
  final file = File('${tempDir.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// 只返回固定候选的假来源，用于验证控制器与触发菜单的联动。
class _FakeSource extends TriggerSource {
  final List<TriggerItem> items;

  _FakeSource(this.items);

  @override
  String get groupTitle => '指令';

  @override
  bool accepts(ComposerTriggerKind kind) => kind == ComposerTriggerKind.slash;

  @override
  Future<List<TriggerItem>> candidates(String query) async =>
      items.where((item) => item.title.substring(1).startsWith(query)).toList();
}

class _RecordingPorts {
  final sent = <List<Object?>>[];
  final commands = <List<Object?>>[];
  Object? failWith;

  CommandExecution commandResult = const CommandExecution(
    matched: true,
    ok: true,
  );

  ComposerPorts build() => ComposerPorts(
    send: (text, attachments, mode) async {
      if (failWith case final error?) throw error;
      sent.add([text, attachments, mode]);
    },
    executeCommand: (line, attachments) async {
      if (failWith case final error?) throw error;
      commands.add([line, attachments]);
      return commandResult;
    },
  );
}

class _Harness {
  final AttachmentStore attachments;
  final ComposerController controller;
  final _RecordingPorts ports;
  late final TriggerMenuController menu = controller.menu;

  _Harness._(this.attachments, this.controller, this.ports);

  factory _Harness({
    ComposerDraftStore? drafts,
    List<TriggerItem> items = const [],
    bool uploadSucceeds = false,
  }) {
    final api = DshApi(
      ApiClient(
        origin: Uri.parse('http://h:1'),
        password: 'p',
        client: MockClient((http.Request request) async {
          if (request.url.path == '/_dsh_mobile/v1/login') {
            return http.Response(
              jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
              200,
            );
          }
          if (!uploadSucceeds) {
            // 永不返回，保持附件停留在「上传中」。
            return Completer<http.Response>().future;
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'value': {
                'receiptId': 'r-1',
                'file': {'attachmentId': 'a-1', 'name': 'b.txt', 'bytes': 1},
              },
            }),
            200,
          );
        }),
      ),
    );
    final attachments = AttachmentStore(api: api, sessionId: 's1');
    final ports = _RecordingPorts();
    final controller =
        ComposerController(
          sessionId: 's1',
          sources: [_FakeSource(items)],
          attachments: attachments,
          ports: ports.build(),
          drafts: drafts,
        )..syncEnvironment(
          const ComposerEnvironment(ready: true, workspaceName: '/repo/demo'),
        );
    return _Harness._(attachments, controller, ports);
  }

  void type(String value) {
    controller.text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('条件未满足');
}

Future<ComposerDraftStore> _draftStore([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return ComposerDraftStore(await SharedPreferences.getInstance());
}

void main() {
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dsh-composer');
  });
  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('占位文案', () {
    test('就绪态带工作区名，且不再出现「按住说话」', () {
      final h = _Harness();
      expect(h.controller.placeholderState, ComposerPlaceholderState.workspace);
      expect(h.controller.placeholderText, contains('demo'));
      expect(h.controller.placeholderText, isNot(contains('说话')));
    });

    test('无工作区时回落到通用文案', () {
      final h = _Harness();
      h.controller.syncEnvironment(const ComposerEnvironment(ready: true));
      expect(h.controller.placeholderState, ComposerPlaceholderState.ready);
    });

    test('状态优先级：未就绪 > 离线 > 规划 > 运行空草稿', () {
      final h = _Harness();
      h.controller.syncEnvironment(const ComposerEnvironment());
      expect(
        h.controller.placeholderState,
        ComposerPlaceholderState.unavailable,
      );
      h.controller.syncEnvironment(
        const ComposerEnvironment(ready: true, offline: true),
      );
      expect(
        h.controller.placeholderState,
        ComposerPlaceholderState.parentOffline,
      );
      h.controller.syncEnvironment(
        const ComposerEnvironment(ready: true, planMode: true),
      );
      expect(h.controller.placeholderState, ComposerPlaceholderState.plan);
      h.controller.syncEnvironment(
        const ComposerEnvironment(ready: true, running: true),
      );
      expect(
        h.controller.placeholderState,
        ComposerPlaceholderState.steerQueue,
      );
    });
  });

  group('发送门控', () {
    test('空草稿不可发送，文本或附件任一即可', () async {
      final h = _Harness();
      expect(h.controller.canSend, isFalse);
      h.type('你好');
      expect(h.controller.canSend, isTrue);
    });

    test('文件上传未完成时阻断发送并给出原因', () async {
      final h = _Harness();
      final path = await writeFile('doc.txt', utf8.encode('hello'));
      await h.attachments.addFiles([path]);
      h.type('带文件');
      expect(h.attachments.sendBlocker, contains('上传'));
      expect(h.controller.canSend, isFalse);
      await h.controller.submit();
      expect(h.ports.sent, isEmpty);
      expect(h.controller.notice, contains('上传'));
      expect(h.controller.draftText, '带文件');
    });
  });

  group('提交生命周期', () {
    test('成功发送后清空草稿并按 queue 提交', () async {
      final h = _Harness();
      h.type('跑一下测试');
      await h.controller.submit();
      expect(h.ports.sent.length, 1);
      expect(h.ports.sent.first[0], '跑一下测试');
      expect(h.ports.sent.first[2], 'queue');
      expect(h.controller.draftText, isEmpty);
      expect(h.controller.notice, isNull);
    });

    test('运行中按持久化的补位方式发送', () async {
      final drafts = await _draftStore();
      final h = _Harness(drafts: drafts);
      h.controller.setMode('steer');
      h.controller.syncEnvironment(
        const ComposerEnvironment(ready: true, running: true),
      );
      h.type('继续');
      await h.controller.submit();
      expect(h.ports.sent.first[2], 'steer');
      expect(drafts.readSendMode(), 'steer');
    });

    test('空闲时忽略补位方式，始终按 queue 发送', () async {
      final h = _Harness();
      h.controller.setMode('steer');
      h.type('新任务');
      await h.controller.submit();
      expect(h.ports.sent.first[2], 'queue');
    });

    test('失败按原顺序还原文本与附件', () async {
      final h = _Harness(uploadSucceeds: true);
      final png = await writeFile('a.png', base64Decode(_pngBase64));
      final txt = await writeFile('b.txt', utf8.encode('note'));
      await h.attachments.addImages([png]);
      await h.attachments.addFiles([txt]);
      await pumpEventQueue(times: 500);
      expect(h.attachments.sendBlocker, isNull);
      h.type('带附件的消息');
      final orderBefore = h.attachments.items.map((e) => e.name).join(',');
      h.ports.failWith = const NetworkException('网络不可用');
      await h.controller.submit();
      expect(h.attachments.sendBlocker, isNull);
      expect(h.controller.draftText, '带附件的消息');
      expect(h.attachments.items.map((e) => e.name).join(','), orderBefore);
      expect(h.controller.notice, '网络不可用');
    });

    test('命令草稿走 commands/execute，未匹配时还原草稿', () async {
      final h = _Harness();
      h.type('/compact');
      await h.controller.submit();
      expect(h.ports.sent, isEmpty);
      expect(h.ports.commands.first[0], '/compact');
      expect(h.controller.draftText, isEmpty);

      h.ports.commandResult = const CommandExecution.none();
      h.type('/unknown');
      await h.controller.submit();
      expect(h.controller.draftText, '/unknown');
      expect(h.controller.notice, contains('未识别'));
    });

    test('命令成功返回文本时作为提示展示', () async {
      final h = _Harness();
      h.ports.commandResult = const CommandExecution(
        matched: true,
        ok: true,
        text: '已压缩 12 条',
      );
      h.type('/compact');
      await h.controller.submit();
      expect(h.controller.notice, '已压缩 12 条');
      expect(h.controller.draftText, isEmpty);
    });

    test('队列撤回：空输入回填文本，已有内容追加一行', () async {
      final h = _Harness();
      await h.controller.recallToInput('撤回的消息');
      expect(h.controller.draftText, '撤回的消息');
      h.type('已有的草稿');
      await h.controller.recallToInput('撤回的消息');
      expect(h.controller.draftText, '已有的草稿\n撤回的消息');
    });

    test('运行中且输入为空时占位切换到排队语义', () async {
      final h = _Harness();
      h.controller.syncEnvironment(
        const ComposerEnvironment(ready: true, running: true),
      );
      expect(h.controller.placeholderText, contains('消息队列'));
    });

    test('会话未就绪时提交被忽略', () async {
      final h = _Harness();
      h.controller.syncEnvironment(const ComposerEnvironment());
      h.type('离线输入');
      await h.controller.submit();
      expect(h.ports.sent, isEmpty);
      expect(h.controller.draftText, '离线输入');
    });
  });

  group('触发菜单联动', () {
    test('输入 / 立即打开菜单并带上候选', () async {
      final h = _Harness(
        items: const [TriggerItem(title: '/compact', insertion: '/compact ')],
      );
      h.type('/');
      await _waitUntil(() => h.menu.groups.isNotEmpty);
      expect(h.menu.groups.first.title, '指令');
      expect(h.menu.groups.first.items.length, 1);
    });

    test('IME 组合态期间抑制菜单，提交后恢复', () async {
      final h = _Harness(
        items: const [TriggerItem(title: '/compact', insertion: '/compact ')],
      );
      h.controller.text.value = const TextEditingValue(
        text: '/ke',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.isComposing, isTrue);
      expect(h.menu.isOpen, isFalse);
      h.controller.text.value = const TextEditingValue(
        text: '/co',
        selection: TextSelection.collapsed(offset: 3),
      );
      await _waitUntil(() => h.menu.groups.isNotEmpty);
      expect(h.menu.groups.first.items.first.title, '/compact');
    });

    test('候选落地替换 token、关闭菜单且不自作主张重开', () async {
      final h = _Harness(
        items: const [TriggerItem(title: '/compact', insertion: '/compact ')],
      );
      h.type('看下 /co');
      await _waitUntil(() => h.menu.currentItem != null);
      h.menu.pick(h.menu.currentItem!);
      expect(h.controller.draftText, '看下 /compact ');
      expect(h.controller.caret, h.controller.draftText.length);
      expect(h.menu.isOpen, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(h.menu.isOpen, isFalse);
    });

    test('已认领命令头后 / 抑制但 @ 仍可用', () {
      final h = _Harness();
      h.type('/compact ');
      expect(h.controller.guard, TriggerGuard.claimed);
      expect(
        detectComposerTrigger('/compact ', 9, guard: TriggerGuard.claimed),
        isNull,
      );
    });

    test('会话离线时冻结触发符', () {
      final h = _Harness();
      h.controller.syncEnvironment(
        const ComposerEnvironment(ready: true, offline: true),
      );
      expect(h.controller.guard, TriggerGuard.frozen);
    });
  });

  group('草稿持久化', () {
    test('输入后防抖落盘，重新进入会话可恢复', () async {
      final drafts = await _draftStore();
      final h = _Harness(drafts: drafts);
      final png = await writeFile('keep.png', base64Decode(_pngBase64));
      await h.attachments.addImages([png]);
      h.type('未发完的草稿');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final stored = drafts.read('s1');
      expect(stored?.text, '未发完的草稿');
      expect(stored?.imagePaths, [png]);

      final restored = _Harness(drafts: drafts);
      await restored.controller.loadDraft();
      expect(restored.controller.draftText, '未发完的草稿');
      expect(restored.attachments.items.length, 1);
    });

    test('发送成功后清掉已存草稿', () async {
      final drafts = await _draftStore();
      final h = _Harness(drafts: drafts);
      h.type('马上发出');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(drafts.read('s1')?.isEmpty, isFalse);
      await h.controller.submit();
      expect(drafts.read('s1'), isNull);
    });

    test('dispose 时冲刷未落盘的草稿', () async {
      final drafts = await _draftStore();
      final h = _Harness(drafts: drafts);
      h.type('刚敲的字');
      h.controller.dispose();
      expect(drafts.read('s1')?.text, '刚敲的字');
    });

    test('坏数据与丢失文件只丢附件不丢文本', () async {
      final drafts = await _draftStore({
        'composer.draft.s1':
            '{"v":1,"text":"保留","attachments":[{"path":"/nope.png","image":true}]}',
      });
      final draft = drafts.read('s1');
      expect(draft?.text, '保留');
      expect(draft?.imagePaths, isEmpty);
    });

    test('未知版本一律视为空草稿', () async {
      final drafts = await _draftStore({'composer.draft.s1': '{"v":9}'});
      expect(drafts.read('s1'), isNull);
    });
  });
}
