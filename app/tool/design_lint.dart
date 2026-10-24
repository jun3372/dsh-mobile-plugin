// 设计规范合规检查脚本（值来源：design/DESIGN_SPEC.md）。
// 用法：dart run tool/design_lint.dart
// 退出码：0 = 无违规；1 = 存在违规。
import 'dart:io';

/// SPEC §2 允许的字号（sp）。logoGlyph 34 仅限 onboarding_logo 场景。
const List<double> _fontSizes = [
  11,
  12,
  13,
  13.5,
  14,
  15,
  16,
  18,
  20,
  22,
  24,
  26,
  34,
];

/// SPEC §3 允许的圆角（dp）。
const List<double> _radii = [6, 8, 10, 12, 14, 16, 18, 20, 24, 26, 28, 999];

/// Color(0x…) 字面量仅允许出现在 theme.dart（色板定义处）。
const _colorLiteralFiles = {'lib/app/theme.dart'};

final _fontSizeRe = RegExp(r'fontSize:\s*([0-9.]+)');
final _radiusRe = RegExp(r'[.:]circular\(\s*([0-9.]+)');
final _colorRe = RegExp(r'\bColor\(\s*0x[0-9a-fA-F]{8}\s*\)');
final _staticColorsRe = RegExp(r'\bDshColors\.');

void main() {
  final violations = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      void report(String message) => violations.add('$path:${i + 1}: $message');

      if (!line.trimLeft().startsWith('//')) {
        for (final match in _fontSizeRe.allMatches(line)) {
          final size = double.tryParse(match.group(1)!);
          if (size == null || !_fontSizes.contains(size)) {
            report('规范外 fontSize: ${match.group(1)}（SPEC §2）');
          }
        }
        for (final match in _radiusRe.allMatches(line)) {
          final radius = double.tryParse(match.group(1)!);
          if (radius == null || !_radii.contains(radius)) {
            report('规范外圆角: ${match.group(1)}（SPEC §3）');
          }
        }
        if (_colorRe.hasMatch(line) && !_colorLiteralFiles.any(path.endsWith)) {
          report('Color(0x…) 字面量只允许在 theme.dart 定义（SPEC §1）');
        }
        if (_staticColorsRe.hasMatch(line) && !path.endsWith('theme.dart')) {
          report('请使用 context.dsh.* 取色，禁止 DshColors.* 静态引用');
        }
      }
    }
  }
  if (violations.isEmpty) {
    stdout.writeln('design_lint: 0 违规，符合 design/DESIGN_SPEC.md');
    return;
  }
  stderr.writeln('design_lint: ${violations.length} 处违规');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exit(1);
}
