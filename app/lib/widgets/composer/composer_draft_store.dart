/// 输入草稿按会话持久化：文本 + 附件路径，重启/切会话后恢复。
///
/// 对齐 dsh Web 的 `dsh-client-ui-composer` 草稿存储（Web 按 sessionId 存 localStorage，
/// App 侧用 SharedPreferences）。存储结构带版本号，读到时对未知版本或坏数据
/// 一律返回空草稿而不是抛错；文件已不存在时只丢弃该附件，保留文本。
library;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 已持久化的一次草稿。
class StoredComposerDraft {
  final String text;
  final List<String> imagePaths;
  final List<String> filePaths;

  const StoredComposerDraft({
    this.text = '',
    this.imagePaths = const [],
    this.filePaths = const [],
  });

  bool get isEmpty =>
      text.trim().isEmpty && imagePaths.isEmpty && filePaths.isEmpty;
}

class ComposerDraftStore {
  static const _version = 1;
  static const _prefix = 'composer.draft.';
  static const _modeKey = 'composer.send-mode';

  final SharedPreferences prefs;

  const ComposerDraftStore(this.prefs);

  String _key(String sessionId) => '$_prefix$sessionId';

  StoredComposerDraft? read(String sessionId) {
    final raw = prefs.getString(_key(sessionId));
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      clear(sessionId);
      return null;
    }
    if (decoded is! Map) {
      clear(sessionId);
      return null;
    }
    if ((decoded['v'] as num?)?.toInt() != _version) return null;
    final text = decoded['text'];
    final attachments = decoded['attachments'];
    final existing = <String, String>{};
    if (attachments is List) {
      for (final item in attachments.whereType<Map>()) {
        final path = item['path'];
        if (path is! String || path.isEmpty) continue;
        if (!File(path).existsSync()) continue;
        existing[path] = item['image'] == true ? 'image' : 'file';
      }
    }
    return StoredComposerDraft(
      text: text is String ? text : '',
      imagePaths: existing.entries
          .where((entry) => entry.value == 'image')
          .map((entry) => entry.key)
          .toList(),
      filePaths: existing.entries
          .where((entry) => entry.value == 'file')
          .map((entry) => entry.key)
          .toList(),
    );
  }

  void write(
    String sessionId, {
    required String text,
    required List<String> imagePaths,
    required List<String> filePaths,
  }) {
    if (text.trim().isEmpty && imagePaths.isEmpty && filePaths.isEmpty) {
      clear(sessionId);
      return;
    }
    final payload = {
      'v': _version,
      'text': text,
      'attachments': [
        for (final path in imagePaths) {'path': path, 'image': true},
        for (final path in filePaths) {'path': path, 'image': false},
      ],
    };
    prefs.setString(_key(sessionId), jsonEncode(payload));
  }

  void clear(String sessionId) => prefs.remove(_key(sessionId));

  /// 运行中补位方式偏好（queue / steer），跨会话共享，与 Web 一致。
  String readSendMode() {
    final value = prefs.getString(_modeKey);
    return value == 'steer' ? 'steer' : 'queue';
  }

  void writeSendMode(String mode) =>
      prefs.setString(_modeKey, mode == 'steer' ? 'steer' : 'queue');
}
