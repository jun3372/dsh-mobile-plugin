import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/features/sessions/widgets/code_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 收集一行里 (文本, 颜色) 片段，方便断言着色。
List<(String, Color?)> _pieces(List<InlineSpan> line) {
  final out = <(String, Color?)>[];
  void walk(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final style = span.style;
    if (span.text != null && span.text!.isNotEmpty) {
      out.add((span.text!, style?.color));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, style ?? inherited);
    }
  }

  for (final span in line) {
    walk(span, null);
  }
  return out;
}

void main() {
  const base = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.55);

  List<List<InlineSpan>> highlight(String source, String language) {
    final lines = DshCodeHighlight.highlightLines(
      source: source,
      language: language,
      base: base,
      theme: dshCodeTheme(DshPalette.dark, Brightness.dark),
    );
    expect(lines, isNotNull, reason: '$language 解析失败');
    return lines!;
  }

  group('languageFor', () {
    test('按扩展名与特殊文件名识别语言', () {
      expect(DshCodeHighlight.languageFor('main.dart'), 'dart');
      expect(DshCodeHighlight.languageFor('server.GO'), 'go');
      expect(DshCodeHighlight.languageFor('deploy.yml'), 'yaml');
      expect(DshCodeHighlight.languageFor('README.md'), 'markdown');
      expect(DshCodeHighlight.languageFor('app.tsx'), 'typescript');
      expect(DshCodeHighlight.languageFor('index.html'), 'xml');
      expect(DshCodeHighlight.languageFor('build.gradle.kts'), 'kotlin');
    });

    test('无扩展名的构建文件与点文件', () {
      expect(DshCodeHighlight.languageFor('Dockerfile'), 'dockerfile');
      expect(DshCodeHighlight.languageFor('GNUmakefile'), 'makefile');
      expect(DshCodeHighlight.languageFor('.gitignore'), 'ini');
      expect(DshCodeHighlight.languageFor('.env'), 'ini');
    });

    test('未知类型返回 null（走纯文本）', () {
      expect(DshCodeHighlight.languageFor('LICENSE'), isNull);
      expect(DshCodeHighlight.languageFor('notes.xyz'), isNull);
      expect(DshCodeHighlight.languageFor('archive.tar.gz'), isNull);
    });
  });

  group('highlightLines', () {
    test('dart 片段产出多种颜色，关键字与注释各自命中主题色', () {
      const source = '''
// 注释
class Greeter {
  final String name = 'hi';
}''';
      final theme = dshCodeTheme(DshPalette.dark, Brightness.dark);
      final lines = highlight(source, 'dart');

      expect(_pieces(lines[0]).single.$2, theme['comment']!.color);
      final keywords = _pieces(lines[1]);
      expect(
        keywords.any((p) => p.$1 == 'class' && p.$2 == theme['keyword']!.color),
        isTrue,
        reason: 'class 应该标成关键字色：$keywords',
      );
      final colors = lines.expand(_pieces).map((p) => p.$2).toSet();
      expect(colors.length, greaterThan(2));
    });

    test('着色片段仍继承基础字号与行高', () {
      final lines = DshCodeHighlight.highlightLines(
        source: 'const a = 1;',
        language: 'dart',
        base: base,
        theme: dshCodeTheme(DshPalette.light, Brightness.light),
      );
      expect(lines, isNotNull);
      final span = lines!.first.first as TextSpan;
      expect(span.style?.fontSize, 12.5);
      expect(span.style?.fontFamily, 'monospace');
    });

    test('跨行块注释不破坏行数，文本一字不差', () {
      const source = '''
/*
 * 两行块注释
 */
void main() {}''';
      final lines = highlight(source, 'dart');
      expect(lines.length, source.split('\n').length);
      final rebuilt = lines
          .map((line) => _pieces(line).map((p) => p.$1).join())
          .join('\n');
      expect(rebuilt, source);
    });

    test('未注册语言、空文本与 null 语言一律退回纯文本', () {
      final theme = dshCodeTheme(DshPalette.light, Brightness.light);
      expect(
        DshCodeHighlight.highlightLines(
          source: 'a=1',
          language: 'not-a-language',
          base: base,
          theme: theme,
        ),
        isNull,
      );
      expect(
        DshCodeHighlight.highlightLines(
          source: '',
          language: 'dart',
          base: base,
          theme: theme,
        ),
        isNull,
      );
      expect(
        DshCodeHighlight.highlightLines(
          source: 'a=1',
          language: null,
          base: base,
          theme: theme,
        ),
        isNull,
      );
    });

    test('json / yaml / shell 等常见类型都能解析', () {
      expect(highlight('{\n  "a": 1\n}', 'json').length, 3);
      expect(highlight('name: dsh\nport: 39081\n', 'yaml').length, 3);
      expect(highlight('#!/bin/bash\necho hi\n', 'bash').length, 3);
    });
  });
}
