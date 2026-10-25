import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/theme.dart';

/// DSH 鲸鱼标志：SVG 渲染，按主题前景色着色（浅色为墨黑、深色为亮白），
/// 避免位图在深色背景下黑鲸不可见。
class DshLogo extends StatelessWidget {
  /// 标志高度；宽度缺省时按 SVG 原始比例自适应。
  final double height;

  /// 可用宽度框（传入时按 [BoxFit.contain] 收进框内），缺省不限制。
  final double? width;

  const DshLogo({super.key, required this.height, this.width});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icon/logo_mono.svg',
      width: width,
      height: height,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(context.dsh.foreground, BlendMode.srcIn),
      semanticsLabel: 'DSH',
    );
  }
}
