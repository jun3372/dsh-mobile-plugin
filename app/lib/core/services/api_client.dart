import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mime/mime.dart';

import '../errors.dart';

/// GET /_dsh_mobile/v1/info 的返回（无鉴权，用于绑定前校验）。
class GatewayInfo {
  final String protocol;
  final String instanceId;
  final String? publicKey;
  final String mode;

  const GatewayInfo({
    required this.protocol,
    required this.instanceId,
    this.publicKey,
    required this.mode,
  });

  bool get isDshMobile => protocol == 'dsh-mobile/1';
}

/// multipart 二进制 RPC 的结果：附件字节 + 同次响应的 `value` 元数据
/// （`offset` / `eof` / `bytes` 等，`data` 本身是 null 占位）。
class RpcBytesResult {
  final Uint8List data;
  final Map<String, dynamic> value;

  const RpcBytesResult({required this.data, required this.value});

  int get offset => (value['offset'] as num?)?.toInt() ?? 0;

  bool get eof => value['eof'] != false;

  int? get totalBytes => (value['bytes'] as num?)?.toInt();
}

const _loginTimeout = Duration(seconds: 8);
const _requestTimeout = Duration(seconds: 20);
const _uploadTimeout = Duration(minutes: 5);
const _preExpiryMargin = Duration(minutes: 5);

/// 网关客户端：login 换 token + 透明代理请求。每个服务端一个实例。
class ApiClient {
  final Uri origin;
  final String password;
  final http.Client _http;
  String? _token;
  DateTime? _expiresAt;
  Future<void>? _refreshing;

  ApiClient({required this.origin, required this.password, http.Client? client})
    : _http =
          client ??
          IOClient(
            // keep-alive 复用在 ohos 上会撞上服务端已关闭的陈旧连接导致请求
            // 挂死（login 阶段卡住不返回），让空闲连接尽快关闭、每次走新连接。
            HttpClient()..idleTimeout = const Duration(milliseconds: 200),
          );

  bool get hasToken => _token != null;

  DateTime? get tokenExpiresAt => _expiresAt;

  /// 供 WebSocket 握手使用的当前 token（必要时先登录/刷新）。
  Future<String> authToken({bool forceRefresh = false}) async {
    if (forceRefresh) clearToken();
    await _ensureToken();
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const AuthException('登录已过期，请重新绑定', code: 'authentication_required');
    }
    return token;
  }

  /// 释放底层 HTTP 连接；页面销毁或切换服务端时调用。
  void close() => _http.close();

  void clearToken() {
    _token = null;
    _expiresAt = null;
    _refreshing = null;
  }

  Future<GatewayInfo> fetchInfo() async {
    final decoded = _decodeBody(
      await _guarded(
        () => _http
            .get(origin.resolve('/_dsh_mobile/v1/info'))
            .timeout(_loginTimeout),
      ),
      allowErrorBody: true,
    );
    return GatewayInfo(
      protocol: decoded['protocol'] as String? ?? '',
      instanceId: decoded['instanceId'] as String? ?? '',
      publicKey: decoded['publicKey'] as String?,
      mode: decoded['mode'] as String? ?? 'lan',
    );
  }

  /// 用保存的密码换取 Bearer token；401/429 转 AuthException，不自动重试。
  Future<void> login() async {
    final response = await _guarded(
      () => _http
          .post(
            origin.resolve('/_dsh_mobile/v1/login'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'password': password}),
          )
          .timeout(_loginTimeout),
    );
    if (response.statusCode == 429) {
      final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
      throw AuthException(
        retryAfter != null && retryAfter > 0
            ? '尝试次数过多，约 ${retryAfter ~/ 60 + 1} 分钟后可重试'
            : '尝试次数过多，请稍后再试',
        code: 'too_many_attempts',
        retryAfterSeconds: retryAfter,
      );
    }
    final decoded = _decodeBody(response);
    final token = decoded['token'];
    final expiresIn = (decoded['expiresIn'] as num?)?.toInt();
    if (response.statusCode != 200 || token is! String || token.isEmpty) {
      throw const AuthException('访问密码不正确', code: 'invalid_password');
    }
    _token = token;
    _expiresAt = expiresIn == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresIn));
  }

  /// typert RPC：POST /api/`<method>`，信封 {"type":"client-request",...}。
  /// 401 时用密码重登一次并重放一次；仍失败抛 AuthException。
  Future<dynamic> rpc(
    String method, {
    required Map<String, Object?> args,
  }) async {
    final response = await _rpcResponse(method, args);
    final decoded = _decodeBody(response);
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      throw const ServerException('服务端响应格式异常', code: 'invalid_response');
    }
    if (result['ok'] == true) return result['value'];
    _throwRpcFailure(result);
  }

  /// 二进制 RPC：宿主把 `Uint8Array` 结果放进 multipart/form-data 的附件分片，
  /// `value.data` 是 null 占位。这里取第一个附件（当前只有 readBytes 使用）。
  Future<RpcBytesResult> rpcBytes(
    String method, {
    required Map<String, Object?> args,
  }) async {
    final response = await _rpcResponse(method, args);
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().startsWith('multipart/form-data')) {
      // 错误或空结果仍是 JSON 信封。
      final decoded = _decodeBody(response);
      final result = decoded['result'];
      if (result is Map<String, dynamic> && result['ok'] == true) {
        return RpcBytesResult(
          data: Uint8List(0),
          value: result['value'] is Map<String, dynamic>
              ? result['value'] as Map<String, dynamic>
              : const {},
        );
      }
      _throwRpcFailure(result);
    }
    final boundary = _multipartBoundary(contentType);
    if (boundary == null) {
      throw const ServerException('服务端响应格式异常', code: 'invalid_response');
    }
    final parts = await MimeMultipartTransformer(
      boundary,
    ).bind(Stream.value(response.bodyBytes)).toList();
    final fields = <String, List<int>>{};
    Map<String, dynamic>? envelope;
    for (final part in parts) {
      final name = _partName(part.headers['content-disposition']);
      if (name == null) continue;
      final bytes = await part.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      if (name == 'metadata') {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map<String, dynamic>) envelope = decoded;
      } else {
        fields[name] = bytes;
      }
    }
    final result = envelope?['result'];
    if (result is Map<String, dynamic> && result['ok'] == true) {
      final value = result['value'] is Map<String, dynamic>
          ? result['value'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final attachments = envelope?['attachments'];
      if (attachments is List) {
        for (final attachment in attachments) {
          if (attachment is! Map) continue;
          final part = attachment['part'];
          if (part is! String) continue;
          final data = fields[part];
          if (data != null) {
            return RpcBytesResult(data: Uint8List.fromList(data), value: value);
          }
        }
      }
      return RpcBytesResult(data: Uint8List(0), value: value);
    }
    _throwRpcFailure(result);
  }

  /// 统一发送 RPC 信封并在 401 时重登重放一次。
  Future<http.Response> _rpcResponse(
    String method,
    Map<String, Object?> args,
  ) async {
    Future<http.Response?> attempt() async {
      final response = await _guarded(
        () => _http
            .post(
              origin.resolve('/api/$method'),
              headers: {
                'content-type': 'application/json',
                if (_token != null) 'authorization': 'Bearer ${_token!}',
              },
              body: jsonEncode({
                'type': 'client-request',
                'rpcId': newRpcId(),
                'method': method,
                'payload': {'args': args},
              }),
            )
            .timeout(_requestTimeout),
      );
      return response.statusCode == 401 ? null : response;
    }

    await _ensureToken();
    final first = await attempt();
    if (first != null) return first;
    // 401：重登一次后重放一次。
    clearToken();
    await login();
    final second = await attempt();
    if (second != null) return second;
    throw const AuthException('登录已过期，请重新绑定', code: 'authentication_required');
  }

  Never _throwRpcFailure(Object? result) {
    final error = result is Map<String, dynamic> ? result['error'] : null;
    final code = error is Map<String, dynamic>
        ? error['code'] as String?
        : null;
    final message = error is Map<String, dynamic>
        ? error['message'] as String?
        : null;
    throw ServerException(message ?? '请求失败（$code）', code: code);
  }

  String? _multipartBoundary(String contentType) {
    final match = RegExp(
      r'boundary=(?:"([^"]+)"|([^;]+))',
      caseSensitive: false,
    ).firstMatch(contentType);
    final value = match?.group(1) ?? match?.group(2);
    return value?.trim();
  }

  String? _partName(String? disposition) {
    if (disposition == null) return null;
    return RegExp(r'name="([^"]+)"').firstMatch(disposition)?.group(1);
  }

  /// 原始文件上传路由：`POST /api/session/uploadFileBinary?sessionId=&name=`，
  /// body 为 application/octet-stream 原始字节（与 Web 端 Blob 上传同一路由）。
  /// 分片写入 sink 以回报字节进度；401 时与 rpc 一样重登并重放一次。
  Future<Map<String, dynamic>> uploadFileBinary({
    required String sessionId,
    required List<int> bytes,
    String? name,
    void Function(int sent, int total)? onProgress,
  }) async {
    Future<({bool unauthorized, Map<String, dynamic> body})> attempt() async {
      final query = <String, String>{'sessionId': sessionId};
      if (name != null && name.isNotEmpty) query['name'] = name;
      final uri = Uri(
        path: '/api/session/uploadFileBinary',
        queryParameters: query,
      );
      final request = http.StreamedRequest('POST', origin.resolveUri(uri))
        ..headers.addAll({
          'content-type': 'application/octet-stream',
          'content-length': '${bytes.length}',
          if (_token != null) 'authorization': 'Bearer ${_token!}',
        });
      // 分片写入 sink。进度是「已交给请求体」的字节数，不是链路真实吞吐，
      // 够用于进度条；每片让出事件循环，避免大文件独占当前 isolate。
      final total = bytes.length;
      const chunk = 64 * 1024;
      final writing = Future<void>(() async {
        for (var offset = 0; offset < total; offset += chunk) {
          final end = offset + chunk < total ? offset + chunk : total;
          request.sink.add(bytes.sublist(offset, end));
          onProgress?.call(end, total);
          await Future<void>.delayed(Duration.zero);
        }
        await request.sink.close();
      });
      http.StreamedResponse streamed;
      try {
        streamed = await _guarded(
          () => _http.send(request).timeout(_uploadTimeout),
        );
      } catch (error) {
        // 请求已失败：无人消费请求体，写体任务只能丢弃，否则 close 悬挂。
        unawaited(writing.catchError((Object _) {}));
        throw error is AppException
            ? error
            : const NetworkException('上传失败，请重试');
      }
      await writing.catchError((Object _) {});
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401) {
        return (unauthorized: true, body: const <String, dynamic>{});
      }
      return (unauthorized: false, body: _decodeBody(response));
    }

    await _ensureToken();
    final first = await attempt();
    if (!first.unauthorized) return first.body;
    clearToken();
    await login();
    final second = await attempt();
    if (!second.unauthorized) return second.body;
    throw const AuthException('登录已过期，请重新绑定', code: 'authentication_required');
  }

  Future<void> _ensureToken() {
    final expiresAt = _expiresAt;
    final needsRefresh =
        _token == null ||
        (expiresAt != null &&
            expiresAt.difference(DateTime.now()) < _preExpiryMargin);
    if (!needsRefresh) return Future.value();
    return _refreshing ??= login().whenComplete(() => _refreshing = null);
  }

  Future<T> _guarded<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on TimeoutException {
      throw const NetworkException('连接超时，请检查网络与服务端状态');
    } on http.ClientException catch (e) {
      throw NetworkException('网络连接失败（${e.message}）');
    } on AppException {
      rethrow;
    } catch (e) {
      if (e is AppException) rethrow;
      throw const NetworkException('网络连接失败');
    }
  }

  Map<String, dynamic> _decodeBody(
    http.Response response, {
    bool allowErrorBody = false,
  }) {
    final Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic>) {
        throw const ServerException('服务端响应格式异常', code: 'invalid_response');
      }
      decoded = value;
    } on FormatException {
      throw const ServerException('服务端响应格式异常', code: 'invalid_response');
    }
    if (response.statusCode >= 400) {
      final code = decoded['error'] as String?;
      if (allowErrorBody) return decoded;
      final message = switch (code) {
        'invalid_password' => '访问密码不正确',
        'too_many_attempts' => '尝试次数过多，请稍后再试',
        'authentication_required' => '登录已过期，请重新绑定',
        'upstream_unavailable' => '服务端宿主不可用',
        'restricted_path' => '该路径不允许通过网关访问',
        _ => '请求被拒绝（${code ?? response.statusCode}）',
      };
      if (code == 'invalid_password' ||
          code == 'too_many_attempts' ||
          code == 'authentication_required') {
        throw AuthException(message, code: code);
      }
      throw ServerException(message, code: code);
    }
    return decoded;
  }
}

/// 本地生成的 uuid v4（rpcId / requestId 用）。
String newRpcId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
