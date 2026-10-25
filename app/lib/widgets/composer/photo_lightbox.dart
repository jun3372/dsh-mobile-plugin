/// 原图灯箱：与 Web 的文档级灯箱一致，支持遮罩点击、关闭按钮与翻页，
/// 关闭后把焦点交还打开者（由路由弹出行为保证）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 一张灯箱图片。
class PhotoFrame {
  final Uint8List? bytes;
  final String? label;

  /// 加载中/失败时由调用方给占位 widget。
  final Widget? placeholder;

  const PhotoFrame({this.bytes, this.label, this.placeholder});
}

/// 打开灯箱；返回时焦点回到调用处的焦点域。
Future<void> showPhotoLightbox(
  BuildContext context, {
  required List<PhotoFrame> frames,
  int initialIndex = 0,
}) {
  final index = initialIndex.clamp(0, frames.length - 1);
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) => _Lightbox(frames: frames, initialIndex: index),
  );
}

class _Lightbox extends StatefulWidget {
  final List<PhotoFrame> frames;
  final int initialIndex;

  const _Lightbox({required this.frames, required this.initialIndex});

  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.frames.length > 1;
    return Dialog.fullscreen(
      backgroundColor: Colors.black87,
      child: Stack(
        children: [
          // 遮罩点击关闭（与 Web「按遮罩关闭」等价）。
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned.fill(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.frames.length,
              itemBuilder: (context, index) {
                final frame = widget.frames[index];
                final bytes = frame.bytes;
                return Center(
                  child: bytes != null
                      ? InteractiveViewer(
                          maxScale: 6,
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        )
                      : (frame.placeholder ??
                            const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 32,
                            )),
                );
              },
            ),
          ),
          if (multi)
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: _Counter(
                  controller: _controller,
                  total: widget.frames.length,
                ),
              ),
            ),
          Positioned(
            top: 24,
            right: 16,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: '关闭',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final PageController controller;
  final int total;

  const _Counter({required this.controller, required this.total});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final page = (controller.page ?? 0).round() + 1;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(DshRadius.pill),
          ),
          child: Text(
            '$page / $total',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        );
      },
    );
  }
}
