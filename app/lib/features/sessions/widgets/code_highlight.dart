import 'package:flutter/material.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/less.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/objectivec.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../../app/theme.dart';

/// 代码预览的语法高亮：re_highlight（highlight.js 11 的纯 Dart 移植）解析，
/// 结果自绘成 TextSpan，配色取自设计 token，不引第三方主题 widget。
abstract final class DshCodeHighlight {
  static final Highlight _engine = Highlight()
    ..registerLanguages({
      'bash': langBash,
      'c': langC,
      'cpp': langCpp,
      'dart': langDart,
      'diff': langDiff,
      'dockerfile': langDockerfile,
      'go': langGo,
      'ini': langIni,
      'java': langJava,
      'javascript': langJavascript,
      'json': langJson,
      'kotlin': langKotlin,
      'less': langLess,
      'lua': langLua,
      'makefile': langMakefile,
      'markdown': langMarkdown,
      'objectivec': langObjectivec,
      'php': langPhp,
      'properties': langProperties,
      'python': langPython,
      'ruby': langRuby,
      'rust': langRust,
      'scss': langScss,
      'sql': langSql,
      'swift': langSwift,
      'typescript': langTypescript,
      'xml': langXml,
      'yaml': langYaml,
    });

  /// 按文件名（含扩展名）映射到 hljs 语言名；未覆盖的返回 null 走纯文本。
  static String? languageFor(String filename) {
    final lower = filename.toLowerCase();
    for (final entry in _exactNames.entries) {
      if (lower.endsWith(entry.key)) return entry.value;
    }
    final dot = lower.lastIndexOf('.');
    final base = dot <= 0 ? lower : lower.substring(0, dot);
    if (base == 'dockerfile') return 'dockerfile';
    if (base == 'makefile' || base == 'gnumakefile') return 'makefile';
    if (dot < 0) return null;
    return _byExtension[lower.substring(dot + 1)];
  }

  /// 高亮并切成行。返回的行数与 [source] 的行数不一致（解析异常、
  /// 渲染丢字）时返回 null，调用方退回纯文本，保证行号永远对得上。
  static List<List<InlineSpan>>? highlightLines({
    required String source,
    required String? language,
    required TextStyle base,
    required Map<String, TextStyle> theme,
  }) {
    if (language == null || source.isEmpty) return null;
    try {
      final result = _engine.highlight(code: source, language: language);
      if (result.errorRaised != null || result.illegal) return null;
      final renderer = TextSpanRenderer(base, theme);
      result.render(renderer);
      final span = renderer.span;
      if (span == null) return null;
      final pieces = <_Piece>[];
      _flatten(span, null, pieces);
      final lines = <List<InlineSpan>>[[]];
      for (final piece in pieces) {
        var text = piece.text;
        while (true) {
          final newline = text.indexOf('\n');
          if (newline < 0) {
            if (text.isNotEmpty) {
              lines.last.add(TextSpan(text: text, style: piece.style));
            }
            break;
          }
          if (newline > 0) {
            lines.last.add(
              TextSpan(text: text.substring(0, newline), style: piece.style),
            );
          }
          lines.add([]);
          text = text.substring(newline + 1);
        }
      }
      if (lines.length != source.split('\n').length) return null;
      return lines;
    } catch (_) {
      // 解析器对畸形代码可能抛异常；预览不该因此白屏，退回纯文本。
      return null;
    }
  }

  static void _flatten(
    InlineSpan span,
    TextStyle? inherited,
    List<_Piece> out,
  ) {
    if (span is! TextSpan) return;
    final style = _merge(inherited, span.style);
    final text = span.text;
    if (text != null && text.isNotEmpty) out.add(_Piece(text, style));
    for (final child in span.children ?? const <InlineSpan>[]) {
      _flatten(child, style, out);
    }
  }

  /// 父子样式合并：子样式优先，未设置的字段继承父样式（含 color），
  /// 这样只带 italic 的 emphasis 也能保住基础字号、行高与正文色。
  static TextStyle? _merge(TextStyle? parent, TextStyle? child) {
    if (parent == null) return child;
    if (child == null) return parent;
    if (!child.inherit) return child;
    return child.copyWith(
      color: child.color ?? parent.color,
      backgroundColor: child.backgroundColor ?? parent.backgroundColor,
      foreground: child.foreground ?? parent.foreground,
      background: child.background ?? parent.background,
      decoration: child.decoration ?? parent.decoration,
      decorationColor: child.decorationColor ?? parent.decorationColor,
      decorationStyle: child.decorationStyle ?? parent.decorationStyle,
      decorationThickness:
          child.decorationThickness ?? parent.decorationThickness,
      fontWeight: child.fontWeight ?? parent.fontWeight,
      fontStyle: child.fontStyle ?? parent.fontStyle,
      fontFamily: child.fontFamily ?? parent.fontFamily,
      fontFamilyFallback: child.fontFamilyFallback ?? parent.fontFamilyFallback,
      fontSize: child.fontSize ?? parent.fontSize,
      letterSpacing: child.letterSpacing ?? parent.letterSpacing,
      wordSpacing: child.wordSpacing ?? parent.wordSpacing,
      height: child.height ?? parent.height,
      leadingDistribution:
          child.leadingDistribution ?? parent.leadingDistribution,
      locale: child.locale ?? parent.locale,
      shadows: child.shadows ?? parent.shadows,
      fontFeatures: child.fontFeatures ?? parent.fontFeatures,
      fontVariations: child.fontVariations ?? parent.fontVariations,
      debugLabel: [
        parent.debugLabel,
        child.debugLabel,
      ].whereType<String>().join('+'),
    );
  }

  static const _exactNames = {
    '.dockerfile': 'dockerfile',
    '.gitignore': 'ini',
    '.env': 'ini',
    '.bashrc': 'bash',
    '.zshrc': 'bash',
    '.profile': 'bash',
  };

  static const _byExtension = {
    'bash': 'bash',
    'sh': 'bash',
    'zsh': 'bash',
    'c': 'c',
    'h': 'c',
    'cc': 'cpp',
    'cpp': 'cpp',
    'cxx': 'cpp',
    'hpp': 'cpp',
    'dart': 'dart',
    'diff': 'diff',
    'patch': 'diff',
    'go': 'go',
    'conf': 'ini',
    'ini': 'ini',
    'toml': 'ini',
    'java': 'java',
    'js': 'javascript',
    'mjs': 'javascript',
    'cjs': 'javascript',
    'jsx': 'javascript',
    'json': 'json',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'less': 'less',
    'lua': 'lua',
    'md': 'markdown',
    'markdown': 'markdown',
    'm': 'objectivec',
    'mm': 'objectivec',
    'php': 'php',
    'properties': 'properties',
    'py': 'python',
    'rb': 'ruby',
    'rs': 'rust',
    'scss': 'scss',
    'sql': 'sql',
    'swift': 'swift',
    'ts': 'typescript',
    'tsx': 'typescript',
    'vue': 'xml',
    'html': 'xml',
    'htm': 'xml',
    'xml': 'xml',
    'yaml': 'yaml',
    'yml': 'yaml',
  };
}

class _Piece {
  final String text;
  final TextStyle? style;

  const _Piece(this.text, this.style);
}

/// 代码配色：正文/注释沿用 palette token，语义色按深浅色各调一组。
Map<String, TextStyle> dshCodeTheme(DshPalette p, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final keyword = Color(dark ? 0xFFC586E0 : 0xFF9A38B5);
  final string = Color(dark ? 0xFF9ECE8F : 0xFF0A7D33);
  final number = Color(dark ? 0xFFD19A66 : 0xFFB05A00);
  final title = Color(dark ? 0xFF7AA2F7 : 0xFF1D4ED8);
  final builtin = Color(dark ? 0xFF5CD6C6 : 0xFF0F7B7B);
  final attribute = Color(dark ? 0xFFE5C07B : 0xFF8A5A00);
  return {
    'comment': TextStyle(color: p.secondaryText, fontStyle: FontStyle.italic),
    'quote': TextStyle(color: p.secondaryText, fontStyle: FontStyle.italic),
    'keyword': TextStyle(color: keyword),
    'literal': TextStyle(color: number),
    'number': TextStyle(color: number),
    'symbol': TextStyle(color: number),
    'bullet': TextStyle(color: number),
    'regexp': TextStyle(color: string),
    'string': TextStyle(color: string),
    'char': TextStyle(color: string),
    'meta-string': TextStyle(color: string),
    'template-tag': TextStyle(color: builtin),
    'template-variable': TextStyle(color: attribute),
    'title': TextStyle(color: title),
    'title.function': TextStyle(color: title),
    'title.class': TextStyle(color: builtin),
    'title.class_name': TextStyle(color: builtin),
    'built_in': TextStyle(color: builtin),
    'type': TextStyle(color: builtin),
    'class': TextStyle(color: builtin),
    'attr': TextStyle(color: attribute),
    'attribute': TextStyle(color: attribute),
    'property': TextStyle(color: attribute),
    'variable': TextStyle(color: attribute),
    'params': TextStyle(color: p.midText),
    'selector-tag': TextStyle(color: keyword),
    'selector-id': TextStyle(color: title),
    'selector-class': TextStyle(color: builtin),
    'section': TextStyle(color: title),
    'name': TextStyle(color: keyword),
    'tag': TextStyle(color: keyword),
    'meta': TextStyle(color: p.midText),
    'addition': TextStyle(color: string),
    'deletion': TextStyle(color: p.dangerRed),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.w700),
  };
}
