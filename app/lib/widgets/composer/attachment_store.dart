/// 草稿附件存储：图片与文件按选择顺序混排，文件选择即上传。
///
/// 对齐 dsh Web 的 `dsh-client-ui-attachment` + `dsh-attachment-local`：
/// - 图片在发送时才内联为 content 的 image 项，选择阶段只做校验；
/// - 文件选择即上传（`/api/session/uploadFileBinary`），后台 FIFO、
///   默认并发 2、按字节回报进度、失败可点击重试、未就绪阻断发送；
/// - 校验用宿主 `imageLimits` 的全量维度：数量、单图字节、合计字节、
///   像素总数、单边尺寸、mediaType 白名单。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/models/dsh_models.dart';
import '../../core/services/dsh_api.dart';

/// 文件上传状态（图片没有该状态，发送时才编码）。
enum DraftUploadState { uploading, ready, failed }

class DraftAttachment {
  final String id;
  final String path;
  final String name;
  final int bytes;
  final bool isImage;

  /// 仅图片有：由文件头嗅探得到，不再静默回落 png。
  String? mediaType;

  DraftUploadState uploadState;
  double progress;
  String? receiptId;
  String? error;

  DraftAttachment({
    required this.id,
    required this.path,
    required this.name,
    required this.bytes,
    required this.isImage,
    this.mediaType,
    this.uploadState = DraftUploadState.uploading,
    this.progress = 0,
    this.receiptId,
    this.error,
  });

  /// 大写扩展名，用于文件卡展示（与 Web 的文件卡一致）。
  String get extensionLabel {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'FILE';
    return name.substring(dot + 1).toUpperCase();
  }

  String get sizeLabel {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()}KB';
    return '$bytes B';
  }
}

/// 一次校验的拒绝原因（用宿主的错误语义回文案）。
class AttachmentRejection {
  final String message;
  const AttachmentRejection(this.message);
}

class AttachmentStore extends ChangeNotifier {
  final DshApi api;

  /// 会话 id；新建会话页在会话创建前为 null，文件上传排队等待
  /// [attachSession] 后再开泵。
  String? _sessionId;

  /// 与 Web 的 `maxConcurrentFileUploads` 默认值一致。
  static const maxConcurrentUploads = 2;

  final List<DraftAttachment> _items = [];
  ImageLimits limits;
  int _runningUploads = 0;
  final List<DraftAttachment> _pendingUploads = [];
  int _sequence = 0;

  AttachmentStore({
    required this.api,
    String? sessionId,
    this.limits = const ImageLimits(),
  }) : _sessionId = sessionId;

  String? get sessionId => _sessionId;

  bool get hasSession => _sessionId != null;

  /// 建会话后补挂 id（新建会话页：附件先选、会话后建），并开泵积压上传。
  void attachSession(String id) {
    if (_sessionId == id) return;
    _sessionId = id;
    _pumpUploads();
  }

  List<DraftAttachment> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  int get imageCount => _items.where((item) => item.isImage).length;

  void updateLimits(ImageLimits next) => limits = next;

  List<DraftAttachment> get failed => _items
      .where((item) => item.uploadState == DraftUploadState.failed)
      .toList();

  bool get hasUploading =>
      _items.any((item) => item.uploadState == DraftUploadState.uploading);

  /// 发送前的阻断原因；null 表示可以发送。
  String? get sendBlocker {
    if (failed.isNotEmpty) return '有文件上传失败，请重试或移除';
    if (_items.any((item) => !item.isImage && item.receiptId == null)) {
      // 会话尚未创建（新建会话页）：文件在等会话，而不是等上传。
      if (!hasSession) return '正在创建会话，请稍候…';
      return '文件还在上传，请等待上传完成后发送';
    }
    return null;
  }

  /// 添加图片：只校验并内联等待发送，不上传。
  Future<AttachmentRejection?> addImages(List<String> paths) async {
    String? firstRejection;
    for (final path in paths) {
      final rejection = await _addImage(path);
      if (rejection != null) firstRejection ??= rejection.message;
    }
    return firstRejection == null ? null : AttachmentRejection(firstRejection);
  }

  Future<AttachmentRejection?> _addImage(String path) async {
    final file = File(path);
    final int bytes;
    try {
      bytes = await file.length();
    } catch (_) {
      return const AttachmentRejection('读取图片失败');
    }
    if (imageCount >= limits.maxImagesPerMessage) {
      return AttachmentRejection('一条消息最多添加 ${limits.maxImagesPerMessage} 张图片');
    }
    if (bytes > limits.maxImageBytes) {
      return AttachmentRejection(
        '图片过大（上限 ${(limits.maxImageBytes / 1024 / 1024).round()}MB）',
      );
    }
    final Uint8List head;
    try {
      head = await _readHead(file, 4096);
    } catch (_) {
      return const AttachmentRejection('读取图片失败');
    }
    final mediaType = sniffImageMediaType(head);
    if (mediaType == null) {
      return const AttachmentRejection('仅支持 PNG、JPG、WebP、GIF 格式的图片');
    }
    if (!limits.acceptsMediaType(mediaType)) {
      return AttachmentRejection('当前宿主不接受 $mediaType 图片');
    }
    final totalImageBytes = _items
        .where((item) => item.isImage)
        .fold<int>(0, (sum, item) => sum + item.bytes);
    if (totalImageBytes + bytes > limits.maxMessageImageBytes) {
      return AttachmentRejection('一条消息的图片合计超过上限');
    }
    if (await _exceedsDimensions(head, bytes)) {
      return AttachmentRejection('图片尺寸超出上限（单边 ${limits.maxImageDimension}px）');
    }
    _items.add(
      DraftAttachment(
        id: 'draft-${++_sequence}',
        path: path,
        name: _baseName(path),
        bytes: bytes,
        isImage: true,
        mediaType: mediaType,
        uploadState: DraftUploadState.ready,
        progress: 1,
      ),
    );
    notifyListeners();
    return null;
  }

  /// 解码头部拿宽高；解码不了就跳过尺寸校验（宿主仍会做最终校验）。
  Future<bool> _exceedsDimensions(Uint8List head, int bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(head);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      final exceeded =
          width > limits.maxImageDimension ||
          height > limits.maxImageDimension ||
          width * height > limits.maxImagePixels;
      image.dispose();
      codec.dispose();
      return exceeded;
    } catch (_) {
      return false;
    }
  }

  /// 添加文件：排队上传，得到 receiptId 后才能随 prompt 发出。
  Future<void> addFiles(List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      final int bytes;
      try {
        bytes = await file.length();
      } catch (_) {
        continue;
      }
      final item = DraftAttachment(
        id: 'draft-${++_sequence}',
        path: path,
        name: _baseName(path),
        bytes: bytes,
        isImage: false,
      );
      _items.add(item);
      _pendingUploads.add(item);
      notifyListeners();
    }
    _pumpUploads();
  }

  void _pumpUploads() {
    if (!hasSession) return;
    final id = _sessionId!;
    while (_runningUploads < maxConcurrentUploads &&
        _pendingUploads.isNotEmpty) {
      final item = _pendingUploads.removeAt(0);
      _runningUploads++;
      unawaited(_upload(item, id));
    }
  }

  Future<void> _upload(DraftAttachment item, String sessionId) async {
    item.uploadState = DraftUploadState.uploading;
    item.progress = 0;
    item.error = null;
    notifyListeners();
    try {
      final bytes = await File(item.path).readAsBytes();
      final receipt = await api.uploadFile(
        sessionId: sessionId,
        bytes: bytes,
        name: item.name,
        onProgress: (sent, total) {
          item.progress = total == 0 ? 1 : sent / total;
          notifyListeners();
        },
      );
      item.receiptId = receipt.receiptId;
      item.uploadState = DraftUploadState.ready;
      item.progress = 1;
    } catch (error) {
      item.uploadState = DraftUploadState.failed;
      item.error = error is Exception ? error.toString() : '上传失败';
    } finally {
      _runningUploads--;
      notifyListeners();
      _pumpUploads();
    }
  }

  /// 失败重试：与 Web 一致从头重传，不支持断点续传。
  void retry(DraftAttachment item) {
    if (item.isImage || item.uploadState != DraftUploadState.failed) return;
    _pendingUploads.insert(0, item);
    _pumpUploads();
  }

  /// 发送失败后按原顺序恢复附件：已上传的文件保留 receiptId，不重传。
  void restore(List<DraftAttachment> items) {
    if (items.isEmpty) return;
    for (final item in items) {
      _items.add(item);
      if (!item.isImage && item.receiptId == null) {
        item.uploadState = DraftUploadState.uploading;
        _pendingUploads.add(item);
      }
    }
    notifyListeners();
    _pumpUploads();
  }

  void remove(DraftAttachment item) {
    _items.remove(item);
    _pendingUploads.remove(item);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _pendingUploads.clear();
    notifyListeners();
  }

  /// 按选择顺序产出 prompt content 附件项；未就绪时返回 null。
  List<PromptAttachment>? buildAttachments() {
    if (sendBlocker != null) return null;
    return [
      for (final item in _items)
        if (item.isImage)
          PromptImage(
            mediaType: item.mediaType ?? 'image/png',
            base64Data: base64Encode(File(item.path).readAsBytesSync()),
            name: item.name,
          )
        else if (item.receiptId case final receiptId?)
          PromptFile(receiptId: receiptId, name: item.name, bytes: item.bytes),
    ];
  }

  static String _baseName(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }
}

/// 由文件头魔数判定 mediaType；无法识别返回 null（而不是当成 png）。
String? sniffImageMediaType(Uint8List head) {
  bool at(int index, List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      if (head.length <= index + i || head[index + i] != bytes[i]) {
        return false;
      }
    }
    return true;
  }

  if (at(0, [0x89, 0x50, 0x4e, 0x47])) return 'image/png';
  if (at(0, [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (at(0, [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  // 部分 HEIC/AVIF 容器同样以 RIFF....WEBP 之外形式开头，一律拒绝。
  return null;
}

Future<Uint8List> _readHead(File file, int maxBytes) async {
  final raf = await file.open();
  try {
    final length = await raf.length();
    return await raf.read(length < maxBytes ? length : maxBytes);
  } finally {
    await raf.close();
  }
}
