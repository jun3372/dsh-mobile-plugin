import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 设计 token：值来源 app/design/DESIGN_SPEC.md（基准设备 HUAWEI Mate 80 Pro，
/// 截图 3x 实测）。页面代码一律通过 `context.dsh.*` 取色、`DshSpace`/`DshRadius`
/// 取尺寸，禁止硬编码。
@immutable
class DshPalette extends ThemeExtension<DshPalette> {
  const DshPalette({
    required this.background,
    required this.canvas,
    required this.surface,
    required this.foreground,
    required this.onForeground,
    required this.midText,
    required this.secondaryText,
    required this.tertiaryText,
    required this.chipGray,
    required this.dotGray,
    required this.divider,
    required this.accentBlue,
    required this.runningYellow,
    required this.dangerRed,
    required this.planGreen,
    required this.shadow,
  });

  /// 列表页背景（SPEC §1.1 background）。
  final Color background;

  /// 会话/新建任务页画布、用户气泡、次级填充（SPEC canvas）。
  final Color canvas;

  /// 输入卡、popover、浮层卡片（SPEC surface）。
  final Color surface;

  /// 主文本、选中 chip、主按钮底（SPEC ink）。
  final Color foreground;

  /// 黑底上的文字/图标。
  final Color onForeground;

  /// 次级正文：选择器取值、思考折叠行等（SPEC 实测 #616161）。
  final Color midText;

  /// 辅助文字、未选中 chip 文字。
  final Color secondaryText;

  /// 禁用/占位图标、chevron。
  final Color tertiaryText;

  /// 未选中 chip、禁用底。
  final Color chipGray;

  /// 状态点（待开始）、空白态图标。
  final Color dotGray;

  /// 分隔线、细边框。
  final Color divider;

  /// 链接、停止按钮。
  final Color accentBlue;

  /// 运行中虚线圆。
  final Color runningYellow;

  /// 错误、解绑。
  final Color dangerRed;

  /// 计划模式 chip 的文字与图标（截图实测 #5BB98B）。
  final Color planGreen;

  /// 圆钮/浮起卡轻阴影色；深色为透明（用边框表达层次）。
  final Color shadow;

  static const light = DshPalette(
    background: Color(0xFFFFFFFF),
    canvas: Color(0xFFF6F6F6),
    surface: Color(0xFFFFFFFF),
    foreground: Color(0xFF141414),
    onForeground: Color(0xFFFFFFFF),
    midText: Color(0xFF616161),
    secondaryText: Color(0xFF9E9EA0),
    tertiaryText: Color(0xFFC4C4C4),
    chipGray: Color(0xFFF0F0F2),
    dotGray: Color(0xFFE3E3E3),
    divider: Color(0xFFEEEEF0),
    accentBlue: Color(0xFF3478F6),
    runningYellow: Color(0xFFFBAE14),
    dangerRed: Color(0xFFE5484D),
    planGreen: Color(0xFF5BB98B),
    shadow: Color(0x0F000000),
  );

  static const dark = DshPalette(
    background: Color(0xFF0C0C0D),
    canvas: Color(0xFF0C0C0D),
    surface: Color(0xFF17171A),
    foreground: Color(0xFFF4F4F6),
    onForeground: Color(0xFF141414),
    midText: Color(0xFFC9C9CE),
    secondaryText: Color(0xFFA6A6AD),
    tertiaryText: Color(0xFF7C7C84),
    chipGray: Color(0xFF222226),
    dotGray: Color(0xFF3A3A3E),
    divider: Color(0xFF26262A),
    accentBlue: Color(0xFF3478F6),
    runningYellow: Color(0xFFFBAE14),
    dangerRed: Color(0xFFE5484D),
    planGreen: Color(0xFF6FCB9B),
    shadow: Color(0x00000000),
  );

  static DshPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<DshPalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  DshPalette copyWith({
    Color? background,
    Color? canvas,
    Color? surface,
    Color? foreground,
    Color? onForeground,
    Color? midText,
    Color? secondaryText,
    Color? tertiaryText,
    Color? chipGray,
    Color? dotGray,
    Color? divider,
    Color? accentBlue,
    Color? runningYellow,
    Color? dangerRed,
    Color? planGreen,
    Color? shadow,
  }) => DshPalette(
    background: background ?? this.background,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    foreground: foreground ?? this.foreground,
    onForeground: onForeground ?? this.onForeground,
    midText: midText ?? this.midText,
    secondaryText: secondaryText ?? this.secondaryText,
    tertiaryText: tertiaryText ?? this.tertiaryText,
    chipGray: chipGray ?? this.chipGray,
    dotGray: dotGray ?? this.dotGray,
    divider: divider ?? this.divider,
    accentBlue: accentBlue ?? this.accentBlue,
    runningYellow: runningYellow ?? this.runningYellow,
    dangerRed: dangerRed ?? this.dangerRed,
    planGreen: planGreen ?? this.planGreen,
    shadow: shadow ?? this.shadow,
  );

  @override
  DshPalette lerp(ThemeExtension<DshPalette>? other, double t) {
    if (other is! DshPalette) return this;
    return DshPalette(
      background: Color.lerp(background, other.background, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      onForeground: Color.lerp(onForeground, other.onForeground, t)!,
      midText: Color.lerp(midText, other.midText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      tertiaryText: Color.lerp(tertiaryText, other.tertiaryText, t)!,
      chipGray: Color.lerp(chipGray, other.chipGray, t)!,
      dotGray: Color.lerp(dotGray, other.dotGray, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      runningYellow: Color.lerp(runningYellow, other.runningYellow, t)!,
      dangerRed: Color.lerp(dangerRed, other.dangerRed, t)!,
      planGreen: Color.lerp(planGreen, other.planGreen, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// 间距 token（4dp 网格，SPEC §3）。
abstract final class DshSpace {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
}

/// 圆角 token（SPEC §3）。
abstract final class DshRadius {
  /// 会话页用户气泡（SPEC §3 实测 37px/3x ≈ 12dp，四角等半径）。
  static const chatBubble = 12.0;
  static const thumb = 8.0;
  static const leading = 10.0;
  static const codeBlock = 12.0;
  static const input = 14.0;
  static const card = 16.0;
  static const bubble = 20.0;
  static const inputCard = 24.0;

  /// 右上浮层菜单（SPEC §4 实测圆角 ≈ 24dp）。
  static const menu = 24.0;
  static const scanFrame = 28.0;
  static const pill = 999.0;
  static const sheet = BorderRadius.vertical(top: Radius.circular(bubble));
}

/// 动效 token（SPEC §4：仅颜色/透明度过渡 160–220ms）。
abstract final class DshMotion {
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;
}

/// 取色/取字的便捷入口。
extension DshThemeContext on BuildContext {
  DshPalette get dsh => DshPalette.of(this);
  TextTheme get dshText => Theme.of(this).textTheme;
}

TextTheme _buildTextTheme(DshPalette p, bool isDark) {
  // 以系统字阶为底保证未列出层级仍有值，再按 SPEC §2 覆写。
  final base =
      (isDark
              ? Typography.material2021().white
              : Typography.material2021().black)
          .apply(bodyColor: p.foreground, displayColor: p.foreground);
  return base.copyWith(
    displaySmall: base.displaySmall?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.25,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12,
      height: 1.4,
      color: p.secondaryText,
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: p.secondaryText,
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: p.secondaryText,
    ),
  );
}

SystemUiOverlayStyle _overlayStyle(DshPalette p, bool isDark) =>
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: p.background,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );

/// 构建浅色/深色主题（SPEC §1–§3）。
ThemeData buildDshTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final p = isDark ? DshPalette.dark : DshPalette.light;
  final text = _buildTextTheme(p, isDark);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.foreground,
        brightness: brightness,
      ).copyWith(
        primary: p.foreground,
        onPrimary: p.onForeground,
        secondary: p.accentBlue,
        onSecondary: Colors.white,
        surface: p.surface,
        onSurface: p.foreground,
        surfaceTint: Colors.transparent,
        outline: p.divider,
        outlineVariant: p.divider,
        error: p.dangerRed,
        onError: Colors.white,
        surfaceContainerLowest: p.surface,
        surfaceContainerLow: p.surface,
        surfaceContainer: p.canvas,
        surfaceContainerHigh: p.chipGray,
        surfaceContainerHighest: p.chipGray,
        inverseSurface: p.foreground,
        onInverseSurface: p.onForeground,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.divider,
    splashFactory: InkSparkle.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: text,
    primaryTextTheme: text,
    extensions: [p],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontSize: 18),
      iconTheme: IconThemeData(color: p.foreground, size: 22),
      systemOverlayStyle: _overlayStyle(p, isDark),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.foreground,
        foregroundColor: p.onForeground,
        disabledBackgroundColor: p.chipGray,
        disabledForegroundColor: p.tertiaryText,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: text.labelLarge,
        shape: const StadiumBorder(),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.foreground,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.foreground,
        minimumSize: const Size(44, 44),
        side: BorderSide(color: p.divider),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? p.tertiaryText
              : p.foreground,
        ),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        iconSize: const WidgetStatePropertyAll(22),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      // 保持 filled=false：会话页使用 InputDecoration.collapsed，填充会破坏布局。
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: text.bodyMedium?.copyWith(color: p.secondaryText),
      labelStyle: text.bodyMedium?.copyWith(color: p.secondaryText),
      floatingLabelStyle: text.bodySmall?.copyWith(color: p.secondaryText),
      // 输入框统一去掉边框：所有状态均使用 InputBorder.none。
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DshRadius.bubble),
        side: BorderSide(color: p.divider),
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium?.copyWith(height: 1.5),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: DshSpace.x6,
        vertical: DshSpace.x6,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.background,
      modalBackgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: isDark ? Colors.black54 : Colors.black26,
      showDragHandle: true,
      dragHandleColor: p.tertiaryText.withValues(alpha: 0.5),
      dragHandleSize: const Size(36, 4),
      shape: const RoundedRectangleBorder(borderRadius: DshRadius.sheet),
      elevation: 0,
      modalElevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.foreground,
      contentTextStyle: text.bodyMedium?.copyWith(color: p.onForeground),
      insetPadding: const EdgeInsets.all(DshSpace.x4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DshRadius.input),
      ),
      elevation: 6,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.secondaryText,
      textColor: p.foreground,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
      minTileHeight: 48,
      contentPadding: const EdgeInsets.symmetric(horizontal: DshSpace.x5),
    ),
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.foreground,
      linearTrackColor: p.chipGray,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.foreground,
      selectionColor: p.accentBlue.withValues(alpha: 0.24),
      selectionHandleColor: p.accentBlue,
    ),
  );
}
