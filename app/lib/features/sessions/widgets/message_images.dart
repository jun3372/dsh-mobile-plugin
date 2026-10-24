import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/models/session_event.dart';
import '../../servers/servers_providers.dart';

/// 附件字节内存缓存（按 attachmentId；会话页生命周期内复用）。
final attachmentCacheProvider =
    NotifierProvider<AttachmentCacheNotifier, Map<String, Uint8List>>(
      AttachmentCacheNotifier.new,
    );

class AttachmentCacheNotifier extends Notifier<Map<String, Uint8List>> {
  @override
  Map<String, Uint8List> build() => const {};

  Future<Uint8List?> load(String sessionId, String attachmentId) async {
    final cached = state[attachmentId];
    if (cached != null) return cached;
    final api = ref.read(dshApiProvider);
    if (api == null) return null;
    try {
      final attachment = await api.attachment(
        sessionId: sessionId,
        attachmentId: attachmentId,
      );
      final bytes = base64Decode(attachment.base64Data);
      state = {...state, attachmentId: bytes};
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

/// 消息内图片行：宿主附件懒加载缩略图，点按全屏查看。
class MessageImages extends ConsumerStatefulWidget {
  final String sessionId;
  final List<TranscriptImage> images;

  const MessageImages({
    super.key,
    required this.sessionId,
    required this.images,
  });

  @override
  ConsumerState<MessageImages> createState() => _MessageImagesState();
}

class _MessageImagesState extends ConsumerState<MessageImages> {
  final _loaded = <String, Uint8List>{};
  final _failed = <String>{};

  @override
  void didUpdateWidget(MessageImages oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final image in widget.images) {
      final bytes = ref.read(attachmentCacheProvider)[image.attachmentId];
      if (bytes != null) _loaded[image.attachmentId] = bytes;
    }
  }

  void _ensureLoaded(TranscriptImage image) {
    if (image.isInline || _loaded.containsKey(image.attachmentId)) return;
    if (_failed.contains(image.attachmentId)) return;
    final cached = ref.read(attachmentCacheProvider)[image.attachmentId];
    if (cached != null) {
      _loaded[image.attachmentId] = cached;
      return;
    }
    ref
        .read(attachmentCacheProvider.notifier)
        .load(widget.sessionId, image.attachmentId)
        .then((bytes) {
          if (!mounted) return;
          setState(() {
            if (bytes == null) {
              _failed.add(image.attachmentId);
            } else {
              _loaded[image.attachmentId] = bytes;
            }
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    for (final image in widget.images) {
      _ensureLoaded(image);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final image in widget.images)
          _Thumbnail(
            image: image,
            bytes: image.isInline
                ? _decodeInline(image)
                : _loaded[image.attachmentId],
            failed: !image.isInline && _failed.contains(image.attachmentId),
            onTap: () => _openViewer(image),
          ),
      ],
    );
  }

  Uint8List? _decodeInline(TranscriptImage image) {
    final data = image.inlineBase64;
    if (data == null) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  void _openViewer(TranscriptImage image) {
    final bytes = image.isInline
        ? _loaded[image.attachmentId] ?? _decodeInline(image)
        : _loaded[image.attachmentId];
    if (bytes == null) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black87,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 24,
              right: 16,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final TranscriptImage image;
  final Uint8List? bytes;
  final bool failed;
  final VoidCallback onTap;

  const _Thumbnail({
    required this.image,
    required this.bytes,
    required this.failed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return GestureDetector(
      onTap: bytes == null ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DshRadius.leading),
        child: Container(
          width: 76,
          height: 76,
          color: p.background,
          alignment: Alignment.center,
          child: bytes != null
              ? Image.memory(bytes!, fit: BoxFit.cover, width: 76, height: 76)
              : failed
              ? Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: p.secondaryText,
                )
              : const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
        ),
      ),
    );
  }
}
