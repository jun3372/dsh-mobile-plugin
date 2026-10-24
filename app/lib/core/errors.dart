/// 应用统一异常体系：文案面向用户，禁止携带密码/token 等敏感值。
sealed class AppException implements Exception {
  final String userMessage;
  final String? code;

  const AppException(this.userMessage, {this.code});

  @override
  String toString() => userMessage;
}

/// 连不上、超时等网络层故障。
class NetworkException extends AppException {
  const NetworkException(super.userMessage, {super.code});
}

/// 认证失败：密码错误、尝试过多、会话过期。
class AuthException extends AppException {
  const AuthException(super.userMessage, {super.code, this.retryAfterSeconds});

  final int? retryAfterSeconds;
}

/// 服务端错误：5xx、协议不符、上游不可用。
class ServerException extends AppException {
  const ServerException(super.userMessage, {super.code});
}

/// 配对二维码解析或校验失败。
class PairingException extends AppException {
  const PairingException(super.userMessage, {super.code});
}
