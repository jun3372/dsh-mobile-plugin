/// 会话搜索命中项。
class SearchHit {
  final String sessionId;
  final String? title;
  final String? snippet;

  const SearchHit({required this.sessionId, this.title, this.snippet});

  static SearchHit fromJson(Map<String, dynamic> json) => SearchHit(
    sessionId: json['sessionId'] as String? ?? '',
    title: json['title'] as String?,
    snippet: json['snippet'] as String?,
  );
}

/// 可选的推理力度档位。
class ReasoningEffort {
  final String id;
  final String name;

  const ReasoningEffort({required this.id, required this.name});

  static ReasoningEffort fromJson(Map<String, dynamic> json) => ReasoningEffort(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );
}

/// 模型目录里的单个模型。
class ModelOption {
  final String id;
  final String name;
  final List<ReasoningEffort> efforts;

  const ModelOption({
    required this.id,
    required this.name,
    this.efforts = const [],
  });

  static ModelOption fromJson(Map<String, dynamic> json) {
    final reasoning = json['reasoning'];
    final efforts = reasoning is Map<String, dynamic>
        ? (reasoning['efforts'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(ReasoningEffort.fromJson)
              .toList()
        : <ReasoningEffort>[];
    return ModelOption(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      efforts: efforts,
    );
  }
}

/// 模型目录中的一个 provider 分组。
class ModelGroup {
  final String id;
  final String name;
  final List<ModelOption> models;

  const ModelGroup({
    required this.id,
    required this.name,
    required this.models,
  });

  static ModelGroup fromJson(Map<String, dynamic> json) => ModelGroup(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    models: (json['models'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ModelOption.fromJson)
        .toList(),
  );
}

/// session/modelCatalog 的返回。
class ModelCatalog {
  final String defaultProvider;
  final String defaultModel;
  final List<ModelGroup> groups;

  const ModelCatalog({
    required this.defaultProvider,
    required this.defaultModel,
    required this.groups,
  });

  static ModelCatalog fromJson(Map<String, dynamic> json) {
    final def = json['default'];
    String provider = '';
    String model = '';
    if (def is Map<String, dynamic>) {
      provider = def['provider'] as String? ?? '';
      model = def['model'] as String? ?? '';
    }
    return ModelCatalog(
      defaultProvider: provider,
      defaultModel: model,
      groups: (json['groups'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ModelGroup.fromJson)
          .toList(),
    );
  }
}

/// 单个问题选项。
class QuestionOption {
  final String label;
  final String? description;

  const QuestionOption({required this.label, this.description});

  static QuestionOption fromJson(Map<String, dynamic> json) => QuestionOption(
    label: json['label'] as String? ?? '',
    description: json['description'] as String?,
  );
}

/// 单个问题（ask() 内一题）。
class UserQuestion {
  final String id;
  final String question;
  final String? detail;
  final String? header;
  final List<QuestionOption> options;
  final bool multiSelect;

  /// 宿主呈现意图（0.2.x）：`plan-review` 表示这是 exit_plan_mode 的计划评审，
  /// [intentApprove] 为批准选项的 label，detail 携带计划 markdown 正文。
  final String? intentKind;
  final String? intentApprove;

  const UserQuestion({
    required this.id,
    required this.question,
    this.detail,
    this.header,
    this.options = const [],
    this.multiSelect = false,
    this.intentKind,
    this.intentApprove,
  });

  static UserQuestion fromJson(Map<String, dynamic> json) {
    final intent = json['intent'];
    return UserQuestion(
      id: json['id'] as String? ?? '',
      question: json['question'] as String? ?? '',
      detail: json['detail'] as String?,
      header: json['header'] as String?,
      options: (json['options'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(QuestionOption.fromJson)
          .toList(),
      multiSelect: json['multiSelect'] == true,
      intentKind: intent is Map ? intent['kind'] as String? : null,
      intentApprove: intent is Map ? intent['approve'] as String? : null,
    );
  }
}

/// 一次待应答的 ask() 调用（可含多个问题）。
class QuestionCall {
  final String callId;
  final List<UserQuestion> questions;

  /// 0.2.1 投影状态：open 仍可经 waterfall 应答，continued 需一元回填。
  final String state;

  const QuestionCall({
    required this.callId,
    required this.questions,
    this.state = 'open',
  });

  static QuestionCall fromJson(Map<String, dynamic> json) => QuestionCall(
    callId: json['callId'] as String? ?? '',
    questions: (json['questions'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(UserQuestion.fromJson)
        .toList(),
    state: json['state'] as String? ?? 'open',
  );
}

/// 会话级图片限制（来自 projections.imageLimits）。
/// 字段与 0.2.1 宿主 schema 全量对齐，宿主缺省时用其自身默认值。
class ImageLimits {
  final int maxImagesPerMessage;
  final int maxImageBytes;

  /// 一条消息所有图片的合计字节上限。
  final int maxMessageImageBytes;

  /// 单图像素总数上限。
  final int maxImagePixels;

  /// 单边像素上限。
  final int maxImageDimension;

  /// 宿主允许的 mediaType 白名单。
  final List<String> mediaTypes;

  const ImageLimits({
    this.maxImagesPerMessage = 20,
    this.maxImageBytes = 20 * 1024 * 1024,
    this.maxMessageImageBytes = 200 * 1024 * 1024,
    this.maxImagePixels = 64000000,
    this.maxImageDimension = 8192,
    this.mediaTypes = const [
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/gif',
    ],
  });

  bool acceptsMediaType(String mediaType) => mediaTypes.contains(mediaType);

  static ImageLimits fromJson(Map<String, dynamic> json) => ImageLimits(
    maxImagesPerMessage: (json['maxImagesPerMessage'] as num?)?.toInt() ?? 20,
    maxImageBytes: (json['maxImageBytes'] as num?)?.toInt() ?? 20 * 1024 * 1024,
    maxMessageImageBytes:
        (json['maxMessageImageBytes'] as num?)?.toInt() ?? 200 * 1024 * 1024,
    maxImagePixels: (json['maxImagePixels'] as num?)?.toInt() ?? 64000000,
    maxImageDimension: (json['maxImageDimension'] as num?)?.toInt() ?? 8192,
    mediaTypes: json['mediaTypes'] is List
        ? (json['mediaTypes'] as List).whereType<String>().toList()
        : const ['image/png', 'image/jpeg', 'image/webp', 'image/gif'],
  );
}
