/// 取路径末段作为文件夹名（兼容 Windows 反斜杠与末尾分隔符）。
String? folderNameOf(String? path) {
  if (path == null || path.isEmpty) return null;
  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
  if (trimmed.isEmpty) return null;
  final idx = trimmed.lastIndexOf(RegExp(r'[\\/]'));
  return idx >= 0 && idx + 1 < trimmed.length
      ? trimmed.substring(idx + 1)
      : trimmed;
}

/// 容错解析时间：毫秒时间戳（num）或 ISO 字符串，均缺失时返回 null。
DateTime? _parseSessionTime(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

/// session/list 返回的会话摘要（fromJson 容错：缺字段落默认值）。
class SessionSummary {
  final String sessionId;
  final String? title;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool running;
  final bool blank;
  final bool agentAvailable;
  final String? cwd;
  final int? asOfSeq;

  /// 宿主 session/list 的 origin；子任务会话为 `subagent`。
  final String? origin;

  const SessionSummary({
    required this.sessionId,
    this.title,
    this.createdAt,
    this.updatedAt,
    this.running = false,
    this.blank = false,
    this.agentAvailable = false,
    this.cwd,
    this.asOfSeq,
    this.origin,
  });

  /// 子任务（子代理）会话只属于父会话，首页/归档等列表不单独展示。
  bool get isSubagent => origin == 'subagent';

  /// cwd 末段，用作文件夹分组名（兼容 Windows 反斜杠路径）。
  String? get folderName => folderNameOf(cwd);

  SessionSummary copyWith({
    String? title,
    DateTime? updatedAt,
    bool? running,
    bool? blank,
    bool? agentAvailable,
    String? cwd,
    int? asOfSeq,
  }) {
    return SessionSummary(
      sessionId: sessionId,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      running: running ?? this.running,
      blank: blank ?? this.blank,
      agentAvailable: agentAvailable ?? this.agentAvailable,
      cwd: cwd ?? this.cwd,
      asOfSeq: asOfSeq ?? this.asOfSeq,
      origin: origin,
    );
  }

  static SessionSummary fromJson(Map<String, dynamic> json) {
    final projections = json['projections'];
    String? title;
    int? asOfSeq;
    if (projections is Map<String, dynamic>) {
      asOfSeq = (projections['asOfSeq'] as num?)?.toInt();
      final values = projections['values'];
      if (values is Map<String, dynamic>) {
        title = values['title'] as String?;
      }
    }
    return SessionSummary(
      sessionId: json['sessionId'] as String? ?? '',
      title: title,
      createdAt: _parseSessionTime(json['createdAt']),
      updatedAt: _parseSessionTime(json['updatedAt']),
      running: json['running'] == true,
      blank: json['blank'] == true,
      agentAvailable: json['agentAvailable'] == true,
      cwd: json['cwd'] as String?,
      asOfSeq: asOfSeq,
      origin: json['origin'] as String?,
    );
  }
}
