/// 输入区（composer）用到的宿主契约模型。
///
/// 字段名严格对齐 dsh 0.2.1-rc.2 的 typert 描述符与 owning package 类型：
/// commands/list、skills/list、fileReferences/list、
/// sessionReferenceResolver/candidates、permissionPresets/catalog、
/// fileUploads/upload、goals/*。
library;

/// `commands/list` 的一条宿主命令。`name` 为小写且不含前导斜杠。
class CommandDescriptor {
  final String name;
  final String description;
  final String? inputHint;
  final bool acceptsAttachments;
  final String? definitionId;

  const CommandDescriptor({
    required this.name,
    required this.description,
    this.inputHint,
    this.acceptsAttachments = false,
    this.definitionId,
  });

  /// 菜单里展示与插入都用带斜杠的形式。
  String get slash => '/$name';

  static CommandDescriptor fromJson(Map<String, dynamic> json) {
    final input = json['input'];
    return CommandDescriptor(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      inputHint: input is Map ? input['hint'] as String? : null,
      acceptsAttachments: input is Map && input['attachments'] == true,
      definitionId: json['definitionId'] as String?,
    );
  }
}

/// `commands/execute` 的回执。宿主未匹配到命令时返回 undefined，
/// 这里用 `CommandExecution.none` 表达「没有匹配」。
class CommandExecution {
  final bool matched;
  final bool ok;
  final String text;

  const CommandExecution({
    required this.matched,
    required this.ok,
    this.text = '',
  });

  const CommandExecution.none() : matched = false, ok = false, text = '';

  static CommandExecution fromValue(Object? value) {
    if (value is! Map) return const CommandExecution.none();
    final result = value['result'];
    if (result is! Map) return const CommandExecution(matched: true, ok: true);
    final kind = result['kind'];
    return CommandExecution(
      matched: true,
      ok: kind != 'error',
      text: result['text'] as String? ?? '',
    );
  }
}

/// `skills/list` 的一条技能。
class SkillEntry {
  final String name;
  final String description;
  final String? whenToUse;
  final bool modelInvocable;
  final String? path;

  const SkillEntry({
    required this.name,
    required this.description,
    this.whenToUse,
    this.modelInvocable = false,
    this.path,
  });

  static SkillEntry fromJson(Map<String, dynamic> json) => SkillEntry(
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    whenToUse: json['whenToUse'] as String?,
    modelInvocable: json['modelInvocable'] == true,
    path: json['path'] as String?,
  );
}

/// `fileReferences/list` 的候选：宿主只回 path 与 file/directory 两态。
class FileRefCandidate {
  final String path;
  final bool isDirectory;

  const FileRefCandidate({required this.path, required this.isDirectory});

  String get name {
    final trimmed = isDirectory && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }

  static FileRefCandidate fromJson(Map<String, dynamic> json) =>
      FileRefCandidate(
        path: json['path'] as String? ?? '',
        isDirectory: json['kind'] == 'directory',
      );
}

/// `sessionReferenceResolver/candidates` 的会话引用候选。
class SessionRefCandidate {
  /// 宿主给出的规范 mention 文本，形如 `@[label](dsh-session:…)`。
  final String mention;
  final String sessionId;
  final String label;
  final String? displayTitle;
  final String? cwd;
  final bool sameWorkspace;
  final int createdAt;

  const SessionRefCandidate({
    required this.mention,
    required this.sessionId,
    required this.label,
    this.displayTitle,
    this.cwd,
    this.sameWorkspace = false,
    this.createdAt = 0,
  });

  static SessionRefCandidate fromJson(Map<String, dynamic> json) =>
      SessionRefCandidate(
        mention: json['mention'] as String? ?? '',
        sessionId: json['sessionId'] as String? ?? '',
        label: json['label'] as String? ?? '',
        displayTitle: json['displayTitle'] as String?,
        cwd: json['cwd'] as String?,
        sameWorkspace: json['sameWorkspace'] == true,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// `permissionPresets/catalog` 的单个预设选项。
class PermissionPresetOption {
  /// 落笔时用 `commands/execute` 发 `/permission <value>`。
  final String value;
  final String name;
  final String? description;

  const PermissionPresetOption({
    required this.value,
    required this.name,
    this.description,
  });

  static PermissionPresetOption fromJson(Map<String, dynamic> json) =>
      PermissionPresetOption(
        value: json['value'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
      );
}

/// 权限预设目录。`defaultOptions` 是新会话默认目录，宿主可缺省。
class PermissionCatalog {
  final List<PermissionPresetOption> options;
  final List<PermissionPresetOption> defaultOptions;
  final String? defaultPreset;

  const PermissionCatalog({
    this.options = const [],
    this.defaultOptions = const [],
    this.defaultPreset,
  });

  static PermissionCatalog fromValue(Object? value) {
    if (value is! Map) return const PermissionCatalog();
    List<PermissionPresetOption> parse(Object? list) => [
      for (final item in list is List ? list : const [])
        if (item is Map<String, dynamic>) PermissionPresetOption.fromJson(item),
    ];
    return PermissionCatalog(
      options: parse(value['options']),
      defaultOptions: parse(value['defaultOptions']),
      defaultPreset: value['defaultPreset'] as String?,
    );
  }
}

/// `fileUploads/upload` / 原始上传路由的回执。
class UploadReceipt {
  /// 发送 prompt 时 `{type:"file", receiptId}` 只认这个 id。
  final String receiptId;
  final String attachmentId;
  final String name;
  final int bytes;

  const UploadReceipt({
    required this.receiptId,
    required this.attachmentId,
    required this.name,
    required this.bytes,
  });

  static UploadReceipt fromValue(Object? value) {
    if (value is! Map) {
      throw const FormatException('上传回执格式异常');
    }
    final receiptId = value['receiptId'];
    if (receiptId is! String || receiptId.isEmpty) {
      throw const FormatException('上传回执缺少 receiptId');
    }
    final file = value['file'];
    return UploadReceipt(
      receiptId: receiptId,
      attachmentId: file is Map ? file['attachmentId'] as String? ?? '' : '',
      name: file is Map ? file['name'] as String? ?? '' : '',
      bytes: file is Map ? (file['bytes'] as num?)?.toInt() ?? 0 : 0,
    );
  }
}

/// `goals/*` 的 CAS 引用：每次持久变更 revision 递增。
class GoalRef {
  final String id;
  final int revision;

  const GoalRef({required this.id, required this.revision});
}

/// 投影 `contextPressure`：占用环的数据源，单位为 token 数。
class ContextPressure {
  final int? pressureTokens;
  final int? projectedTokens;
  final int? contextWindow;

  const ContextPressure({
    this.pressureTokens,
    this.projectedTokens,
    this.contextWindow,
  });

  /// 与 Web 一致：优先用 projectedTokens，缺失时退回 pressureTokens。
  int? get usedTokens => projectedTokens ?? pressureTokens;

  double? get ratio {
    final window = contextWindow;
    final used = usedTokens;
    if (window == null || window <= 0 || used == null) return null;
    return (used / window).clamp(0.0, 1.0);
  }

  static ContextPressure? fromValue(Object? value) {
    if (value is! Map) return null;
    return ContextPressure(
      pressureTokens: (value['pressureTokens'] as num?)?.toInt(),
      projectedTokens: (value['projectedTokens'] as num?)?.toInt(),
      contextWindow: (value['contextWindow'] as num?)?.toInt(),
    );
  }
}
