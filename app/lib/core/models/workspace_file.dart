import 'dart:typed_data';

/// `workspaceFiles/list` 的目录列表模型。
///
/// 路径为**工作区相对路径**：根目录是空串，子项路径按 `/` 拼接；
/// 宿主以稳定的名称顺序返回，展示顺序由客户端决定。
enum WorkspaceEntryType { file, directory, other }

class WorkspaceEntry {
  /// 目录内 basename。
  final String name;
  final WorkspaceEntryType type;

  /// 仅普通文件且后端上报时存在。
  final int? size;

  const WorkspaceEntry({required this.name, required this.type, this.size});

  bool get isDirectory => type == WorkspaceEntryType.directory;

  static WorkspaceEntry fromJson(Map<String, dynamic> json) {
    final type = switch (json['type']) {
      'directory' => WorkspaceEntryType.directory,
      'file' => WorkspaceEntryType.file,
      _ => WorkspaceEntryType.other,
    };
    return WorkspaceEntry(
      name: json['name'] as String? ?? '',
      type: type,
      size: (json['size'] as num?)?.toInt(),
    );
  }
}

class WorkspaceDirectoryListing {
  /// 被列出的目录（工作区相对路径，根为空串）。
  final String path;
  final List<WorkspaceEntry> entries;

  /// 宿主条目上限裁掉了剩余子项。
  final bool truncated;

  const WorkspaceDirectoryListing({
    required this.path,
    required this.entries,
    required this.truncated,
  });

  static WorkspaceDirectoryListing fromValue(Object? value) {
    if (value is! Map) {
      return const WorkspaceDirectoryListing(
        path: '',
        entries: [],
        truncated: false,
      );
    }
    final rawEntries = value['entries'];
    return WorkspaceDirectoryListing(
      path: value['path'] as String? ?? '',
      entries: rawEntries is List
          ? [
              for (final raw in rawEntries)
                if (raw is Map<String, dynamic>) WorkspaceEntry.fromJson(raw),
            ]
          : const [],
      truncated: value['truncated'] == true,
    );
  }
}

/// `workspaceFiles/read` 的一页文本。
class WorkspaceFileText {
  /// 页内各行以 `\n` 连接，末尾不带终止符。
  final String text;

  /// 本页起始行（1 基）。
  final int offset;

  /// 本页行数；越过文件末尾时为 0。
  final int lines;

  /// 本页是否已包含文件最后一行。
  final bool eof;

  /// 完整文件字节数（后端上报时存在）。
  final int? bytes;

  const WorkspaceFileText({
    required this.text,
    required this.offset,
    required this.lines,
    required this.eof,
    this.bytes,
  });

  static WorkspaceFileText fromValue(Object? value) {
    if (value is! Map) {
      return const WorkspaceFileText(text: '', offset: 1, lines: 0, eof: true);
    }
    return WorkspaceFileText(
      text: value['text'] as String? ?? '',
      offset: (value['offset'] as num?)?.toInt() ?? 1,
      lines: (value['lines'] as num?)?.toInt() ?? 0,
      eof: value['eof'] != false,
      bytes: (value['bytes'] as num?)?.toInt(),
    );
  }
}

/// `workspaceFiles/readBytes` 的分片汇总（客户端按 1MB 循环读到 eof）。
class WorkspaceFileBytes {
  final Uint8List data;

  /// 宿主上报的完整文件字节数（未上报时为 null）。
  final int? totalBytes;

  /// 命中客户端预览上限，字节不完整（图片无法解码时按此提示）。
  final bool truncated;

  const WorkspaceFileBytes({
    required this.data,
    this.totalBytes,
    this.truncated = false,
  });

  int get length => data.length;
}
