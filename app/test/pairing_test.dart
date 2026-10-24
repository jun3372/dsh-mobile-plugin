import 'package:dsh_mobile/core/errors.dart';
import 'package:dsh_mobile/core/services/pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('标准局域网配对码', () {
    final payload = parsePairingPayload(
      'http://192.168.1.50:39081?token=Ab3xY9_-Qw',
    );
    expect(payload.origin.toString(), 'http://192.168.1.50:39081');
    expect(payload.token, 'Ab3xY9_-Qw');
  });

  test('https 隧道配对码', () {
    final payload = parsePairingPayload(
      'https://xxx.trycloudflare.com?token=%2Babc%3D',
    );
    expect(payload.origin.scheme, 'https');
    expect(payload.token, '+abc=');
  });

  test('首尾空白可容忍', () {
    final payload = parsePairingPayload('  http://10.0.0.2:39081?token=t1  \n');
    expect(payload.token, 't1');
  });

  test('非 http 协议拒绝', () {
    expect(
      () => parsePairingPayload('ftp://192.168.1.50:39081?token=t'),
      throwsA(isA<PairingException>()),
    );
  });

  test('缺 token 拒绝', () {
    expect(
      () => parsePairingPayload('http://192.168.1.50:39081'),
      throwsA(isA<PairingException>()),
    );
  });

  test('额外 query 参数拒绝（防误扫其他系统的二维码）', () {
    expect(
      () => parsePairingPayload('http://192.168.1.50:39081?token=t&x=1'),
      throwsA(isA<PairingException>()),
    );
    expect(
      () => parsePairingPayload('http://192.168.1.50:39081?x=1'),
      throwsA(isA<PairingException>()),
    );
  });

  test('空 token 拒绝', () {
    expect(
      () => parsePairingPayload('http://192.168.1.50:39081?token='),
      throwsA(isA<PairingException>()),
    );
  });

  test('带 fragment 或 userinfo 拒绝', () {
    expect(
      () => parsePairingPayload('http://192.168.1.50:39081?token=t#frag'),
      throwsA(isA<PairingException>()),
    );
    expect(
      () => parsePairingPayload('http://user:pass@192.168.1.50:39081?token=t'),
      throwsA(isA<PairingException>()),
    );
  });

  test('完全不是 URL 的内容拒绝', () {
    expect(
      () => parsePairingPayload('随便一串字'),
      throwsA(isA<PairingException>()),
    );
  });
}
