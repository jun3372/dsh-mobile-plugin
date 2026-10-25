import 'dart:typed_data';

import '../errors.dart';
import '../models/composer_models.dart';
import '../models/dsh_models.dart';
import '../models/dsh_session.dart';
import '../models/goal_info.dart';
import '../models/plan_state.dart';
import '../models/queued_message.dart';
import '../models/session_event.dart';
import '../models/todo_item.dart';
import '../models/workspace_file.dart';
import 'api_client.dart';

/// session/projections 读取结果（0.2.1 三态：
/// null / sequenced / migration-required）。
class SessionProjections {
  final int asOfSeq;
  final Map<String, Object?> values;
  final bool migrationRequired;

  const SessionProjections({
    required this.asOfSeq,
    this.values = const {},
    this.migrationRequired = false,
  });

  static SessionProjections fromValue(
    int asOfSeq,
    Map<String, Object?>? values,
  ) {
    values ??= const {};
    return SessionProjections(asOfSeq: asOfSeq, values: values);
  }

  static SessionProjections fromRpc(Object? value) {
    if (value is! Map) return const SessionProjections(asOfSeq: 0);
    if (value['kind'] == 'migration-required') {
      final values = value['values'];
      return SessionProjections(
        asOfSeq: 0,
        values: values is Map ? Map<String, Object?>.from(values) : const {},
        migrationRequired: true,
      );
    }
    if (value['kind'] == 'sequenced' || value.containsKey('asOfSeq')) {
      final values = value['values'];
      return fromValue(
        (value['asOfSeq'] as num?)?.toInt() ?? 0,
        values is Map ? Map<String, Object?>.from(values) : null,
      );
    }
    return const SessionProjections(asOfSeq: 0);
  }

  String? get title => values['title'] as String?;

  GoalInfo? get goal => GoalInfo.fromValue(values['goal']);

  PlanState? get plan => PlanState.fromValue(values['plan']);

  List<TodoItem> get todos => TodoItem.listFromValue(values['todos']);

  List<QueuedMessage> get queuedMessages =>
      QueuedMessage.listFromValue(values['inbox']);

  List<QuestionCall> get questionCalls {
    final questions = values['userQuestions'];
    if (questions is! Map) return const [];
    final active = questions['active'];
    if (active is! List) return const [];
    return [
      for (final raw in active)
        if (raw is Map) QuestionCall.fromJson(Map<String, dynamic>.from(raw)),
    ];
  }

  ImageLimits get imageLimits {
    final limits = values['imageLimits'];
    return limits is Map
        ? ImageLimits.fromJson(Map<String, dynamic>.from(limits))
        : const ImageLimits();
  }

  /// 上下文占用（占用环数据源）；宿主未挂相关插件时为 null。
  ContextPressure? get contextPressure =>
      ContextPressure.fromValue(values['contextPressure']);

  /// 投影 permissions 是只读的，仅回 `{currentValue}`；
  /// 变更只能通过 `/permission <value>` 命令落笔。
  String? get permissionPreset {
    final permissions = values['permissions'];
    if (permissions is! Map) return null;
    return permissions['currentValue'] as String?;
  }

  String? get selectedProvider => _selected?['provider'] as String?;

  String? get selectedModel => _selected?['model'] as String?;

  Map? get _selected {
    final selection = values['modelSelection'];
    if (selection is! Map) return null;
    final next = selection['next'];
    if (next is Map) return next;
    final last = selection['lastUsed'];
    return last is Map ? last : null;
  }
}

/// DSH 宿主业务 API（typert RPC）。端点与参数名集中在此，协议变更只改这里。
/// 参数名均已对照 0.2.1-rc.2 的 typert 描述符核对。
class DshApi {
  final ApiClient _client;

  DshApi(this._client);

  /// 全部可见会话（含已归档，归档过滤由调用方用 archivedSessionIds 完成）。
  Future<List<SessionSummary>> listSessions() async {
    final value = await _client.rpc(
      'session/list',
      args: {'_request': <String, Object?>{}},
    );
    final items = _field(value, 'items');
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SessionSummary.fromJson)
        .toList();
  }

  Future<SessionProjections> projections(String sessionId) async {
    final value = await _client.rpc(
      'session/projections',
      args: {
        'request': {'sessionId': sessionId},
      },
    );
    return SessionProjections.fromRpc(value);
  }

  /// 读取会话历史页。[throughSeq] 传 follow snapshot 的 cursor。
  Future<SessionHistoryPage> page(
    String sessionId, {
    required int throughSeq,
    int? beforeSeq,
    int maxMessages = 80,
    Map<String, Object?>? turnWindow,
  }) async {
    final request = <String, Object?>{
      'address': {'kind': 'session', 'sessionId': sessionId},
      'throughSeq': throughSeq,
      'maxMessages': maxMessages,
      'beforeSeq': ?beforeSeq,
      'turnWindow': ?turnWindow,
    };
    final value = await _client.rpc('session/page', args: {'request': request});
    final records = _field(value, 'records');
    return SessionHistoryPage(
      events: SessionWireEvent.fromRecords(records),
      hasMore: _field(value, 'hasMore') == true,
    );
  }

  /// 新建会话（宿主会复用可复用的空白会话）。
  ///
  /// [workspaceId] 与 [cwd] 二选一：宿主按 workspaceId 建会话时会同时把
  /// 会话挂到该工作区名下；只传 cwd 的会话不会进入工作区（DSH 显示为未分组）。
  Future<String> createSession({String? workspaceId, String? cwd}) async {
    if (workspaceId != null && cwd != null) {
      throw ArgumentError('createSession 只能指定 workspaceId 或 cwd');
    }
    final value = await _client.rpc(
      'session/create',
      args: {
        'request': {
          'workspaceId': ?workspaceId,
          if (cwd != null && cwd.isNotEmpty) 'cwd': cwd,
        },
      },
    );
    final sessionId = _field(value, 'sessionId');
    if (sessionId is! String || sessionId.isEmpty) {
      throw const ServerException('创建会话失败', code: 'invalid_response');
    }
    return sessionId;
  }

  /// 发送消息；[requestId] 由客户端生成并保留，用于持久消息回显对账。
  /// content 只允许 text / image / file 三项，附件按选择顺序排在正文之后。
  Future<void> prompt({
    required String sessionId,
    required String requestId,
    required String text,
    List<PromptAttachment> attachments = const [],
    String mode = 'queue',
    String? clientTimeZone,
  }) async {
    await _client.rpc(
      'session/prompt',
      args: {
        'request': {
          'requestId': requestId,
          'sessionId': sessionId,
          'mode': mode,
          'content': [
            if (text.trim().isNotEmpty) {'type': 'text', 'text': text},
            for (final attachment in attachments) attachment.toContentItem(),
          ],
          'clientTimeZone': ?clientTimeZone,
        },
      },
    );
  }

  Future<void> cancel(String sessionId) async {
    await _client.rpc(
      'session/cancel',
      args: {
        'request': {'sessionId': sessionId},
      },
    );
  }

  /// 重命名会话，返回新标题。
  Future<String> rename(String sessionId, String title) async {
    final value = await _client.rpc(
      'session/rename',
      args: {
        'request': {'sessionId': sessionId, 'title': title},
      },
    );
    final newTitle = _field(value, 'title');
    return newTitle is String ? newTitle : title;
  }

  /// 会话内容搜索（宿主可能禁用搜索索引，错误会带服务端原因抛出）。
  Future<List<SearchHit>> search(String query) async {
    final value = await _client.rpc(
      'session/search',
      args: {
        'request': {'query': query},
      },
    );
    final items = _field(value, 'items');
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SearchHit.fromJson)
        .toList();
  }

  /// 归档会话，返回宿主编译的完整已归档 id 集合。
  Future<List<String>> archive(String sessionId) async {
    final value = await _client.rpc(
      'workspace/archiveSession',
      args: {
        'request': {'sessionId': sessionId, 'stopActivity': true},
      },
    );
    return _stringList(value, 'archivedSessionIds');
  }

  Future<List<String>> unarchive(String sessionId) async {
    final value = await _client.rpc(
      'workspace/unarchiveSession',
      args: {
        'request': {'sessionId': sessionId},
      },
    );
    return _stringList(value, 'archivedSessionIds');
  }

  /// 从当前历史分叉出新会话，返回新 sessionId。
  Future<String> fork(String sessionId, {int? atSeq}) async {
    final value = await _client.rpc(
      'session/fork',
      args: {
        'request': {'sessionId': sessionId, 'atSeq': ?atSeq},
      },
    );
    final newId = _field(value, 'sessionId');
    if (newId is! String || newId.isEmpty) {
      throw const ServerException('分叉会话失败', code: 'invalid_response');
    }
    return newId;
  }

  /// 模型目录。
  Future<ModelCatalog> modelCatalog() async {
    final value = await _client.rpc(
      'session/modelCatalog',
      args: <String, Object?>{},
    );
    if (value is! Map<String, dynamic>) {
      throw const ServerException('模型目录获取失败', code: 'invalid_response');
    }
    return ModelCatalog.fromJson(value);
  }

  /// 选择会话级模型。[reasoningEffort] 可空。
  Future<void> selectModel({
    required String sessionId,
    required String provider,
    required String model,
    String? reasoningEffort,
  }) async {
    await _client.rpc(
      'session/selectModel',
      args: {
        'request': {
          'sessionId': sessionId,
          'provider': provider,
          'model': model,
          'reasoningEffort': ?reasoningEffort,
        },
      },
    );
  }

  /// 应答已经离开 waterfall 窗口的提问（projection 中 state=continued）。
  Future<void> answerQuestions({
    required String sessionId,
    required String callId,
    required List<QuestionAnswer> answers,
  }) async {
    await _client.rpc(
      'userQuestions/answer',
      args: {
        'agentId': sessionId,
        'callId': callId,
        'answer': {
          'answers': [
            for (final answer in answers)
              {
                'id': answer.questionId,
                'selected': answer.selected,
                if (answer.custom != null && answer.custom!.isNotEmpty)
                  'custom': answer.custom,
              },
          ],
        },
      },
    );
  }

  /// 回填一次 `$events` waterfall（审批 / 窗口内提问）。
  Future<void> eventsResult({
    required String clientId,
    required String eventId,
    required Map<String, Object?> outcome,
  }) async {
    await _client.rpc(
      '\$events/result',
      args: {'clientId': clientId, 'eventId': eventId, 'outcome': outcome},
    );
  }

  /// 读取会话历史中的一张图片附件，返回 base64 字节与尺寸元数据。
  Future<SessionAttachment> attachment({
    required String sessionId,
    required String attachmentId,
  }) async {
    final value = await _client.rpc(
      'session/attachment',
      args: {
        'request': {'sessionId': sessionId, 'attachmentId': attachmentId},
      },
    );
    final info = _field(value, 'attachment');
    final data = _field(value, 'data');
    if (info is! Map || data is! String || data.isEmpty) {
      throw const ServerException('附件读取失败', code: 'invalid_response');
    }
    return SessionAttachment(
      attachmentId: info['attachmentId'] is String
          ? info['attachmentId'] as String
          : attachmentId,
      mediaType: info['mediaType'] is String
          ? info['mediaType'] as String
          : 'image/png',
      width: (info['width'] as num?)?.toInt() ?? 0,
      height: (info['height'] as num?)?.toInt() ?? 0,
      name: info['name'] as String?,
      base64Data: data,
    );
  }

  /// 修改一条仍在排队的消息；[action] 为 `{'kind':'edit','content':[...]}`、
  /// `{'kind':'remove'}` 或 `{'kind':'steer'}`（立即发送）。
  Future<void> updateQueueItem({
    required String sessionId,
    required String itemId,
    required Map<String, Object?> action,
  }) async {
    await _client.rpc(
      'session/updateQueue',
      args: {
        'request': {'sessionId': sessionId, 'itemId': itemId, 'action': action},
      },
    );
  }

  /// 列出宿主注册的斜杠命令（descriptor 参数名就是 `agentId`）。
  Future<List<CommandDescriptor>> commands({required String sessionId}) async {
    final value = await _client.rpc(
      'commands/list',
      args: {'agentId': sessionId},
    );
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(CommandDescriptor.fromJson)
        .where((command) => command.name.isNotEmpty)
        .toList();
  }

  /// 执行一条命令行。Web 侧同样用它落权限预设与计划模式：
  /// `/permission workspace-write`、`/plan off`；未匹配时宿主返回 undefined。
  Future<CommandExecution> executeCommand({
    required String sessionId,
    required String line,
    List<PromptAttachment> attachments = const [],
  }) async {
    final value = await _client.rpc(
      'commands/execute',
      args: {
        'agentId': sessionId,
        'line': line,
        'submittedAttachments': [
          for (final attachment in attachments) attachment.toContentItem(),
        ],
      },
    );
    return CommandExecution.fromValue(value);
  }

  /// 切换尚未开始的会话所用的 Agent 预设（descriptor: agentPresets/select）。
  Future<void> selectAgentPreset({
    required String sessionId,
    required String presetId,
  }) async {
    await _client.rpc(
      'agentPresets/select',
      args: {'agentId': sessionId, 'agentPreset': presetId},
    );
  }

  /// 技能目录，供 `/` 菜单的技能分组。
  Future<List<SkillEntry>> skills({required String sessionId}) async {
    final value = await _client.rpc(
      'skills/list',
      args: {
        'request': {'sessionId': sessionId},
      },
    );
    final items = _field(value, 'skills');
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SkillEntry.fromJson)
        .where((skill) => skill.name.isNotEmpty)
        .toList();
  }

  /// `@` 文件引用候选；[query] 是 `@` 或 `@"` 之后的路径文本，
  /// 引号只是客户端语法，服务端按裸串排序。
  Future<List<FileRefCandidate>> fileReferenceCandidates({
    required String sessionId,
    required String query,
  }) async {
    final value = await _client.rpc(
      'fileReferences/list',
      args: {'agentId': sessionId, 'query': query},
    );
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(FileRefCandidate.fromJson)
        .where((item) => item.path.isNotEmpty)
        .toList();
  }

  /// `workspaceFiles/list`：列出会话工作区内某个目录的直属子项。
  /// [path] 为工作区相对路径；根目录传 `.`（宿主拒绝空串）。
  Future<WorkspaceDirectoryListing> listWorkspaceDirectory({
    required String sessionId,
    String path = '',
  }) async {
    final value = await _client.rpc(
      'workspaceFiles/list',
      args: {'workspaceFileScopeId': sessionId, 'path': path},
    );
    return WorkspaceDirectoryListing.fromValue(value);
  }

  /// `workspaceFiles/read`：读取一页文本。[offset] 为 1 基行号。
  Future<WorkspaceFileText> readWorkspaceFile({
    required String sessionId,
    required String path,
    int offset = 1,
    int limit = 1000,
  }) async {
    final value = await _client.rpc(
      'workspaceFiles/read',
      args: {
        'workspaceFileScopeId': sessionId,
        'path': path,
        'range': {'offset': offset, 'limit': limit},
      },
    );
    return WorkspaceFileText.fromValue(value);
  }

  /// 图片预览上限；超过则直接拒绝，避免为了看一张图拉爆内存。
  static const _bytePreviewCap = 16 * 1024 * 1024;
  static const _byteChunk = 1024 * 1024;

  /// `readBytes` 第三个参数的线上名：新宿主（0.1.5-rc.2）叫 `range`，
  /// 旧宿主叫 `options`。首次按 `range` 发，撞到描述符不匹配再切换并记住，
  /// 同一台服务端只探测一次。
  String _bytesRangeField = 'range';

  /// `workspaceFiles/readBytes`：宿主单次最多回 2MB，这里按 1MB 分片
  /// 循环读到 eof。二进制走 multipart 附件（见 ApiClient.rpcBytes）。
  Future<WorkspaceFileBytes> readWorkspaceFileBytes({
    required String sessionId,
    required String path,
  }) async {
    final builder = BytesBuilder(copy: false);
    var offset = 0;
    int? totalBytes;
    while (true) {
      final page = await _readBytesPage(sessionId, path, offset);
      totalBytes ??= page.totalBytes;
      final total = totalBytes;
      if (total != null && total > _bytePreviewCap) {
        throw ServerException(
          '文件过大（约 ${(total / (1024 * 1024)).toStringAsFixed(1)} MB），暂不支持预览',
          code: 'workspace-file/too-large',
        );
      }
      builder.add(page.data);
      if (page.eof || page.data.isEmpty) break;
      offset = page.offset + page.data.length;
      if (builder.length >= _bytePreviewCap) {
        return WorkspaceFileBytes(
          data: builder.takeBytes(),
          totalBytes: total,
          truncated: true,
        );
      }
    }
    return WorkspaceFileBytes(
      data: builder.takeBytes(),
      totalBytes: totalBytes,
    );
  }

  Future<RpcBytesResult> _readBytesPage(
    String sessionId,
    String path,
    int offset,
  ) async {
    Map<String, Object?> args(String field) => {
      'workspaceFileScopeId': sessionId,
      'path': path,
      field: {'offset': offset, 'length': _byteChunk},
    };
    try {
      return await _client.rpcBytes(
        'workspaceFiles/readBytes',
        args: args(_bytesRangeField),
      );
    } on ServerException catch (e) {
      final wantsOptions =
          _bytesRangeField == 'range' &&
          e.userMessage.contains('do not match the descriptor') &&
          e.userMessage.contains('options');
      if (!wantsOptions) rethrow;
      _bytesRangeField = 'options';
      return _client.rpcBytes(
        'workspaceFiles/readBytes',
        args: args('options'),
      );
    }
  }

  /// `@` 会话引用候选；mention 用宿主给的规范形式。
  Future<List<SessionRefCandidate>> sessionReferenceCandidates({
    required String sessionId,
    required String query,
  }) async {
    final value = await _client.rpc(
      'sessionReferenceResolver/candidates',
      args: {'agentId': sessionId, 'query': query},
    );
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map(SessionRefCandidate.fromJson)
        .where((item) => item.mention.isNotEmpty)
        .toList();
  }

  /// 权限预设目录（无参数）。应用预设只能走 `/permission <value>` 命令。
  Future<PermissionCatalog> permissionCatalog() async {
    final value = await _client.rpc(
      'permissionPresets/catalog',
      args: const {},
    );
    return PermissionCatalog.fromValue(value);
  }

  /// 上传一个待发送文件，得到 `receiptId`；prompt 里以
  /// `{type:'file', receiptId}` 引用，选择即上传而非发送时上传。
  ///
  /// 原始路由回的是 RemoteResult 信封（`{ok, value}` / `{ok:false, error}`），
  /// HTTP 200 携带业务失败是常态，必须按 ok 判定——与 rpc 同一套规则。
  Future<UploadReceipt> uploadFile({
    required String sessionId,
    required List<int> bytes,
    required String name,
    void Function(int sent, int total)? onProgress,
  }) async {
    final body = await _client.uploadFileBinary(
      sessionId: sessionId,
      bytes: bytes,
      name: name,
      onProgress: onProgress,
    );
    if (body['ok'] != true) {
      final error = body['error'];
      final code = error is Map ? error['code'] as String? : null;
      final message = error is Map ? error['message'] as String? : null;
      throw ServerException(message ?? '文件上传失败', code: code);
    }
    try {
      return UploadReceipt.fromValue(body['value']);
    } on FormatException {
      throw const ServerException('文件上传失败', code: 'invalid_response');
    }
  }

  /// 新建目标，返回 CAS 引用。
  Future<GoalRef> createGoal({
    required String sessionId,
    required String objective,
    int? maxGoalRounds,
  }) async {
    final value = await _client.rpc(
      'goals/create',
      args: {
        'agentId': sessionId,
        'request': {'objective': objective, 'maxGoalRounds': ?maxGoalRounds},
      },
    );
    return _goalRefOf(value, fallbackRevision: 1);
  }

  /// 改目标正文/轮数上限；[ref] 必须是当前 revision，否则宿主按 CAS 拒绝。
  Future<void> editGoal({
    required String sessionId,
    required GoalRef ref,
    String? objective,
    int? maxGoalRounds,
  }) async {
    await _client.rpc(
      'goals/edit',
      args: {
        'agentId': sessionId,
        'ref': {'id': ref.id, 'revision': ref.revision},
        'request': {'objective': ?objective, 'maxGoalRounds': ?maxGoalRounds},
      },
    );
  }

  Future<void> pauseGoal({required String sessionId, required GoalRef ref}) =>
      _goalTransition('goals/pause', sessionId, ref);

  Future<void> resumeGoal({required String sessionId, required GoalRef ref}) =>
      _goalTransition('goals/resume', sessionId, ref);

  Future<void> completeGoal({
    required String sessionId,
    required GoalRef ref,
  }) => _goalTransition('goals/complete', sessionId, ref);

  /// 清除目标（写入 tombstone，revision 递增）。
  Future<void> clearGoal({
    required String sessionId,
    required GoalRef ref,
  }) async {
    await _client.rpc(
      'goals/clear',
      args: {
        'agentId': sessionId,
        'ref': {'id': ref.id, 'revision': ref.revision},
      },
    );
  }

  Future<void> _goalTransition(
    String method,
    String sessionId,
    GoalRef ref,
  ) async {
    await _client.rpc(
      method,
      args: {
        'agentId': sessionId,
        'ref': {'id': ref.id, 'revision': ref.revision},
      },
    );
  }

  GoalRef _goalRefOf(Object? value, {required int fallbackRevision}) {
    if (value is Map) {
      final ref = value['ref'];
      if (ref is Map) {
        final id = ref['id'];
        if (id is String && id.isNotEmpty) {
          return GoalRef(
            id: id,
            revision: (ref['revision'] as num?)?.toInt() ?? fallbackRevision,
          );
        }
      }
      final id = value['id'];
      if (id is String && id.isNotEmpty) {
        return GoalRef(
          id: id,
          revision: (value['revision'] as num?)?.toInt() ?? fallbackRevision,
        );
      }
    }
    throw const ServerException('目标操作失败', code: 'invalid_response');
  }

  /// 注册（或幂等解析）一个指向已有目录的工作区。
  Future<WorkspaceInfo> createWorkspace(String path) async {
    final value = await _client.rpc(
      'workspace/create',
      args: {
        'request': {'path': path},
      },
    );
    return _workspaceOf(value);
  }

  /// 删除工作区注册（保留目录文件与会话）。
  Future<void> deleteWorkspace(String workspaceId) async {
    await _client.rpc(
      'workspace/delete',
      args: {
        'request': {'workspaceId': workspaceId},
      },
    );
  }

  /// 重命名工作区，返回新标题。
  Future<String> renameWorkspace(String workspaceId, String title) async {
    final value = await _client.rpc(
      'workspace/rename',
      args: {
        'request': {'workspaceId': workspaceId, 'title': title},
      },
    );
    return _workspaceOf(value).title;
  }

  /// 把工作区移到 [beforeWorkspaceId] 之前；为 null 时移到末尾，返回新顺序。
  Future<List<String>> moveWorkspaceBefore({
    required String workspaceId,
    String? beforeWorkspaceId,
  }) async {
    final value = await _client.rpc(
      'workspace/insertBefore',
      args: {
        'request': {
          'workspaceId': workspaceId,
          'beforeWorkspaceId': ?beforeWorkspaceId,
        },
      },
    );
    return _stringList(value, 'workspaceIds');
  }

  /// 把会话移到工作区内 [beforeSessionId] 之前；为 null 时移到最前。
  Future<void> moveSessionBefore({
    required String workspaceId,
    required String sessionId,
    String? beforeSessionId,
  }) async {
    await _client.rpc(
      'workspace/insertSessionBefore',
      args: {
        'request': {
          'workspaceId': workspaceId,
          'sessionId': sessionId,
          'beforeSessionId': ?beforeSessionId,
        },
      },
    );
  }

  /// 宿主桌面是否支持远程打开工作区路径。
  Future<bool> canOpenWorkspacePath() async {
    final value = await _client.rpc(
      'session/canOpenWorkspacePath',
      args: <String, Object?>{},
    );
    return value == true;
  }

  /// 在宿主桌面打开一个路径；[reveal] 为 true 时在文件管理器中定位。
  Future<void> openWorkspacePath(String path, {bool reveal = false}) async {
    await _client.rpc(
      'session/openWorkspacePath',
      args: {
        'request': {'path': path, if (reveal) 'action': 'reveal'},
      },
    );
  }

  /// 未配置默认模型时让宿主选择首个可用账号模型。
  Future<void> initializeDefaultModel() async {
    await _client.rpc(
      'session/initializeDefaultModel',
      args: <String, Object?>{},
    );
  }
}

/// session/attachment 返回的一张图片。
class SessionAttachment {
  final String attachmentId;
  final String mediaType;
  final int width;
  final int height;
  final String? name;
  final String base64Data;

  const SessionAttachment({
    required this.attachmentId,
    required this.mediaType,
    required this.width,
    required this.height,
    required this.base64Data,
    this.name,
  });
}

/// workspace/create 等返回的工作区信息。
class WorkspaceInfo {
  final String workspaceId;
  final String path;
  final String title;

  const WorkspaceInfo({
    required this.workspaceId,
    required this.path,
    required this.title,
  });

  static WorkspaceInfo fromValue(Object? value) {
    if (value is! Map) {
      return const WorkspaceInfo(workspaceId: '', path: '', title: '');
    }
    return WorkspaceInfo(
      workspaceId: value['workspaceId'] is String
          ? value['workspaceId'] as String
          : '',
      path: value['path'] is String ? value['path'] as String : '',
      title: value['title'] is String ? value['title'] as String : '',
    );
  }
}

WorkspaceInfo _workspaceOf(Object? value) =>
    WorkspaceInfo.fromValue(_field(value, 'workspace'));

/// prompt content 里的一个附件项。宿主只接受 image（内联字节）与
/// file（先上传得到的 receiptId）两种附件。
sealed class PromptAttachment {
  const PromptAttachment();

  Map<String, Object?> toContentItem();
}

class PromptImage extends PromptAttachment {
  final String mediaType;
  final String base64Data;
  final String? name;

  const PromptImage({
    required this.mediaType,
    required this.base64Data,
    this.name,
  });

  @override
  Map<String, Object?> toContentItem() => {
    'type': 'image',
    'mediaType': mediaType,
    'data': base64Data,
    if (name != null) 'name': name,
  };
}

/// 已上传文件；content 项只带 receiptId，不带 name/mediaType。
class PromptFile extends PromptAttachment {
  final String receiptId;

  /// 仅用于本地展示（附件栏与重试），不会进入 content。
  final String name;
  final int bytes;

  const PromptFile({
    required this.receiptId,
    required this.name,
    this.bytes = 0,
  });

  @override
  Map<String, Object?> toContentItem() => {
    'type': 'file',
    'receiptId': receiptId,
  };
}

/// 单个问题的应答。
class QuestionAnswer {
  final String questionId;
  final List<String> selected;
  final String? custom;

  const QuestionAnswer({
    required this.questionId,
    this.selected = const [],
    this.custom,
  });
}

Object? _field(Object? value, String name) =>
    value is Map<String, dynamic> ? value[name] : null;

List<String> _stringList(Object? value, String name) {
  final items = _field(value, name);
  if (items is! List) return const [];
  return items.whereType<String>().toList();
}
