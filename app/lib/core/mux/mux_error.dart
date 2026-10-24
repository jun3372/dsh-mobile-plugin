import '../errors.dart';

/// mux 逻辑流失败（服务端 `error` 帧 / 连接层故障）。
///
/// [details] 仅用于内部诊断，禁止直接展示给用户或写入日志。
class MuxError {
  final String code;
  final String message;
  final Object? details;

  const MuxError(this.code, this.message, {this.details});

  static MuxError? fromValue(Object? value) {
    if (value is! Map) return null;
    final code = value['code'];
    final message = value['message'];
    if (code is! String || message is! String) return null;
    return MuxError(code, message, details: value['details']);
  }

  /// 面向用户的等价异常；不透传可能包含内部细节的 message。
  ServerException toException() {
    final friendly = switch (code) {
      'gateway/cancelled' => '请求已取消',
      'gateway/internal' => '会话连接出现异常，正在恢复',
      'session/not-found' => '会话不存在或已被删除',
      'authentication_required' => '登录已过期，请重新绑定',
      _ => message.trim().isEmpty ? '请求失败（$code）' : message,
    };
    return ServerException(friendly, code: code);
  }
}
