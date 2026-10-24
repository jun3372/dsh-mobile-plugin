import '../errors.dart';

/// 配对二维码解析结果：origin 不含 path/query，token 即访问密码。
class PairingPayload {
  final Uri origin;
  final String token;

  const PairingPayload({required this.origin, required this.token});
}

/// 解析 `<origin>?token=<password>` 形态的配对二维码（镜像 lib/service.js 生成规则，fail-closed）。
PairingPayload parsePairingPayload(String raw) {
  final Uri uri;
  try {
    uri = Uri.parse(raw.trim());
  } on FormatException {
    throw const PairingException('无法识别的二维码内容');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw const PairingException('仅支持 http/https 地址的配对码');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const PairingException('配对码地址格式不正确');
  }
  if (uri.fragment.isNotEmpty) {
    throw const PairingException('配对码地址格式不正确');
  }
  final query = uri.queryParameters;
  if (query.isEmpty) {
    throw const PairingException('二维码缺少访问令牌');
  }
  if (query.length != 1 || !query.containsKey('token')) {
    throw const PairingException('配对码地址格式不正确');
  }
  final token = query['token'];
  if (token == null || token.isEmpty) {
    throw const PairingException('二维码缺少访问令牌');
  }
  final origin = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );
  if (origin.host.isEmpty) {
    throw const PairingException('配对码地址缺少主机名');
  }
  return PairingPayload(origin: origin, token: token);
}
