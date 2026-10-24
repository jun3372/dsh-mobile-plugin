/// 草稿附件栏：可选 leading（如计划 chip）与附件按顺序进入同一条不换行横向栏。
///
/// 图片为「缩略图 + 图片 N + 移除圆钮」的紧凑卡片，文件为 240×52 卡片；
/// 上传中显示进度、失败显示重试，移除按钮常显。溢出时手势横滑。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'attachment_store.dart';
import 'photo_lightbox.dart';

class AttachmentRail extends StatelessWidget {
  final AttachmentStore store;
  final Widget? leading;

  const AttachmentRail({super.key, required this.store, this.leading});

  // 图片卡 36 缩略图 + 上下 6 + 边框 = 50；文件卡两行文字约 33 + 上下 6。
  static const _railHeight = 52.0;
  static const _thumb = 36.0;
  static const _fileCardWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    final lead = leading;
    final leadCount = lead == null ? 0 : 1;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.isEmpty && lead == null) return const SizedBox.shrink();
        return SizedBox(
          height: _railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            itemCount: leadCount + store.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index < leadCount) return Center(child: lead);
              final item = store.items[index - leadCount];
              if (!item.isImage) return _FileCard(item: item, store: store);
              final imageNo = store.items
                  .take(index - leadCount)
                  .where((e) => e.isImage)
                  .length;
              return _ImageTile(
                item: item,
                store: store,
                label: '图片 ${imageNo + 1}',
                onTap: () => _openLightbox(context, index - leadCount),
              );
            },
          ),
        );
      },
    );
  }

  /// 草稿图片直接从文件读原图，避免缩略图尺寸被缓存复用。
  Future<void> _openLightbox(BuildContext context, int index) async {
    final images = store.items.where((item) => item.isImage).toList();
    final target = store.items[index];
    final loaded = <PhotoFrame>[];
    for (final image in images) {
      Uint8List? bytes;
      try {
        bytes = await File(image.path).readAsBytes();
      } catch (_) {
        bytes = null;
      }
      loaded.add(
        PhotoFrame(
          bytes: bytes,
          label: image.name,
          placeholder: Text(
            image.name,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }
    if (!context.mounted) return;
    final position = images.indexOf(target);
    return showPhotoLightbox(
      context,
      frames: loaded,
      initialIndex: position < 0 ? 0 : position,
    );
  }
}

class _ImageTile extends StatelessWidget {
  final DraftAttachment item;
  final AttachmentStore store;
  final String label;
  final VoidCallback onTap;

  const _ImageTile({
    required this.item,
    required this.store,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(DshRadius.codeBlock),
        border: Border.all(color: p.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DshRadius.thumb),
              child: Image.file(
                File(item.path),
                width: AttachmentRail._thumb,
                height: AttachmentRail._thumb,
                fit: BoxFit.cover,
                cacheWidth: 256,
                errorBuilder: (_, _, _) => SizedBox(
                  width: AttachmentRail._thumb,
                  height: AttachmentRail._thumb,
                  child: ColoredBox(
                    color: p.chipGray,
                    child: const Icon(Icons.image_outlined, size: 18),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: context.dshText.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => store.remove(item),
            child: CircleAvatar(
              radius: 10,
              backgroundColor: p.foreground,
              child: Icon(Icons.close_rounded, size: 12, color: p.onForeground),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final DraftAttachment item;
  final AttachmentStore store;

  const _FileCard({required this.item, required this.store});

  @override
  Widget build(BuildContext context) {
    final p = context.dsh;
    final failed = item.uploadState == DraftUploadState.failed;
    final uploading = item.uploadState == DraftUploadState.uploading;
    return Container(
      width: AttachmentRail._fileCardWidth,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(DshRadius.codeBlock),
        border: Border.all(color: p.divider),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        p.accentBlue,
                        p.accentBlue.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                  child: const SizedBox(width: 26, height: 26),
                ),
                if (uploading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: item.progress > 0 ? item.progress : null,
                      color: Colors.white,
                    ),
                  )
                else if (failed)
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    tooltip: '上传失败，点击重试',
                    onPressed: () => store.retry(item),
                    icon: Icon(Icons.refresh_rounded, color: p.dangerRed),
                  )
                else
                  const Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  failed
                      ? '${item.extensionLabel} · ${item.sizeLabel} · 上传失败'
                      : uploading
                      ? '${item.extensionLabel} · ${item.sizeLabel} · ${(item.progress * 100).round()}%'
                      : '${item.extensionLabel} · ${item.sizeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.dshText.labelSmall?.copyWith(
                    color: failed ? p.dangerRed : p.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => store.remove(item),
            child: CircleAvatar(
              radius: 10,
              backgroundColor: p.foreground,
              child: Icon(Icons.close_rounded, size: 12, color: p.onForeground),
            ),
          ),
        ],
      ),
    );
  }
}
