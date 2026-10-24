import 'package:dsh_mobile/features/sessions/composer/composer_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectComposerTrigger @ 语法（移植宿主 grammar.js）', () {
    test('普通 @token 命中，query 为 @ 到光标切片', () {
      const draft = '看看 @src/ma';
      final hit = detectComposerTrigger(draft, draft.length);
      expect(hit, isNotNull);
      expect(hit!.kind, ComposerTriggerKind.at);
      expect(hit.query, 'src/ma');
      expect(hit.start, draft.indexOf('@'));
      expect(hit.end, draft.length);
      expect(hit.quoted, isFalse);
    });

    test("未闭合引号 @\" 可跨空白", () {
      const draft = '读一下 @"my docs/';
      final hit = detectComposerTrigger(draft, draft.length);
      expect(hit!.kind, ComposerTriggerKind.at);
      expect(hit.query, 'my docs/');
      expect(hit.quoted, isTrue);
    });

    test('email 里的 @ 不是触发符', () {
      const draft = '联系 jun3@example';
      expect(detectComposerTrigger(draft, draft.length), isNull);
    });

    test('行首 @ 也是触发符', () {
      const draft = '@';
      final hit = detectComposerTrigger(draft, 1);
      expect(hit?.query, '');
    });

    test('引号闭合后不再命中', () {
      const draft = '@"a b" 后续';
      expect(detectComposerTrigger(draft, draft.length), isNull);
    });
  });

  group('detectComposerTrigger / 语法', () {
    test('行首 / 命中命令', () {
      const draft = '/perm';
      final hit = detectComposerTrigger(draft, draft.length);
      expect(hit!.kind, ComposerTriggerKind.slash);
      expect(hit.query, 'perm');
    });

    test('空白后的 / 命中（宿主扫到第一个空白）', () {
      const draft = '帮我 /goal';
      final hit = detectComposerTrigger(draft, draft.length);
      expect(hit!.kind, ComposerTriggerKind.slash);
      expect(hit.start, draft.indexOf('/'));
    });

    test('URL 里的斜杠当普通字符继续扫描', () {
      const draft = '参考 https://a.com/x';
      expect(detectComposerTrigger(draft, draft.length), isNull);
    });

    test('claimed 档位抑制 / 但保留 @', () {
      const draft = '/plan off @src';
      expect(
        detectComposerTrigger(
          draft,
          draft.length,
          guard: TriggerGuard.claimed,
        )?.kind,
        ComposerTriggerKind.at,
      );
      const slashDraft = '/plan';
      expect(
        detectComposerTrigger(
          slashDraft,
          slashDraft.length,
          guard: TriggerGuard.claimed,
        ),
        isNull,
      );
    });

    test('frozen 档位两个都抑制', () {
      const draft = '/plan';
      expect(
        detectComposerTrigger(draft, draft.length, guard: TriggerGuard.frozen),
        isNull,
      );
    });

    test('hasClaimedCommand 只认最前面的命令 token', () {
      expect(hasClaimedCommand('/plan off'), isTrue);
      expect(hasClaimedCommand('  /plan off'), isTrue);
      expect(hasClaimedCommand('正文 /plan'), isFalse);
      expect(hasClaimedCommand('/'), isFalse);
    });
  });

  group('formatFileMention', () {
    test('普通文件不带引号，目录补尾斜杠', () {
      expect(
        formatFileMention('lib/a.dart', isDirectory: false),
        '@lib/a.dart',
      );
      expect(formatFileMention('lib/src', isDirectory: true), '@lib/src/');
    });

    test('含空格走引号；目录保持引号打开以便下钻', () {
      expect(formatFileMention('my docs', isDirectory: true), '@"my docs/');
      expect(
        formatFileMention('my docs/a.txt', isDirectory: false),
        '@"my docs/a.txt"',
      );
    });

    test('preserveQuote 即使无空格也保留引号', () {
      expect(
        formatFileMention('src', isDirectory: false, preserveQuote: true),
        '@"src"',
      );
    });

    test('控制字符与引号无法表达，返回 null', () {
      expect(formatFileMention('a\nb', isDirectory: false), isNull);
      expect(formatFileMention('a"b', isDirectory: false), isNull);
    });
  });

  group('replaceTrigger', () {
    test('用命中区间替换 token 并落到插入文本之后', () {
      const draft = '看看 @src/ma';
      final hit = detectComposerTrigger(draft, draft.length)!;
      final result = replaceTrigger(draft, hit, '@src/main.dart');
      expect(result.text, '看看 @src/main.dart');
      expect(result.caret, result.text.length);
    });

    test('替换后引号形态也能正确闭合', () {
      const draft = '读 @"my do';
      final hit = detectComposerTrigger(draft, draft.length)!;
      final result = replaceTrigger(draft, hit, '@"my docs/a.md"');
      expect(result.text, '读 @"my docs/a.md"');
    });
  });

  group('rankByQuery 有序子序列 + 前缀优先', () {
    test('空查询按名称字典序返回全量', () {
      final ranked = rankByQuery('', [
        'plan',
        'compact',
        'goal',
      ], name: (i) => i);
      expect(ranked, ['compact', 'goal', 'plan']);
    });

    test('前缀命中排在子序列命中之前', () {
      final ranked = rankByQuery('pl', [
        'apple',
        'plan',
        'explode',
      ], name: (i) => i);
      expect(ranked.first, 'plan');
      expect(ranked, contains('explode'));
    });

    test('大小写不敏感，且 label 也参与匹配', () {
      final ranked = rankByQuery(
        'perm',
        ['permission', 'plan'],
        name: (i) => i,
        label: (i) => i == 'permission' ? '权限预设' : '计划',
      );
      expect(ranked, ['permission']);
    });

    test('不匹配的项被剔除', () {
      expect(rankByQuery('xyz', ['plan', 'goal'], name: (i) => i), isEmpty);
    });

    test('命中越靠前排越高', () {
      final ranked = rankByQuery('ab', ['zzzab', 'ab'], name: (i) => i);
      expect(ranked, ['ab', 'zzzab']);
    });
  });
}
