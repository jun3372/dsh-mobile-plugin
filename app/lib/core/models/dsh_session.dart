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

/// session/list 返回的会话摘要（fromJson 容错：缺字段落默认值）。
class SessionSummary {
  final String sessionId;
  final String? title;
  final DateTime? updatedAt;
  final bool running;
  final bool blank;
  final bool agentAvailable;
  final String? cwd;
  final int? asOfSeq;

  const SessionSummary({
    required this.sessionId,
    this.title,
    this.updatedAt,
    this.running = false,
    this.blank = false,
    this.agentAvailable = false,
    this.cwd,
    this.asOfSeq,
  });

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
      updatedAt: updatedAt ?? this.updatedAt,
      running: running ?? this.running,
      blank: blank ?? this.blank,
      agentAvailable: agentAvailable ?? this.agentAvailable,
      cwd: cwd ?? this.cwd,
      asOfSeq: asOfSeq ?? this.asOfSeq,
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
      updatedAt: json['updatedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['updatedAt'] as num).toInt(),
            )
          : null,
      running: json['running'] == true,
      blank: json['blank'] == true,
      agentAvailable: json['agentAvailable'] == true,
      cwd: json['cwd'] as String?,
      asOfSeq: asOfSeq,
    );
  }
}
