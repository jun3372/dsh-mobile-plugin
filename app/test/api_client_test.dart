import 'dart:convert';

import 'package:dsh_mobile/core/errors.dart';
import 'package:dsh_mobile/core/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetchInfo 解析 info 字段', () async {
    final client = ApiClient(
      origin: Uri.parse('http://host:39081'),
      password: 'pw',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'protocol': 'dsh-mobile/1',
            'instanceId': 'abc123',
            'mode': 'lan',
            'publicKey': 'pk',
          }),
          200,
        );
      }),
    );
    final info = await client.fetchInfo();
    expect(info.isDshMobile, isTrue);
    expect(info.instanceId, 'abc123');
    expect(info.mode, 'lan');
  });

  test('login 成功保存 token', () async {
    http.Request? captured;
    final client = ApiClient(
      origin: Uri.parse('http://host:39081'),
      password: 'pw',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'protocol': 'dsh-mobile/1',
            'instanceId': 'x',
            'token': 't' * 43,
            'expiresIn': 43200,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.login();
    expect(client.hasToken, isTrue);
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['password'], 'pw');
  });

  test('login 密码错误抛 AuthException，文案不含密码', () async {
    const password = 'secret-password-xyz';
    final client = ApiClient(
      origin: Uri.parse('http://host:39081'),
      password: password,
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'error': 'invalid_password'}), 401),
      ),
    );
    try {
      await client.login();
      fail('应抛出 AuthException');
    } on AuthException catch (e) {
      expect(e.code, 'invalid_password');
      expect(e.toString(), isNot(contains(password)));
    }
  });

  test('login 429 带 Retry-After', () async {
    final client = ApiClient(
      origin: Uri.parse('http://host:39081'),
      password: 'pw',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'too_many_attempts'}),
          429,
          headers: {'retry-after': '600'},
        ),
      ),
    );
    try {
      await client.login();
      fail('应抛出 AuthException');
    } on AuthException catch (e) {
      expect(e.retryAfterSeconds, 600);
      expect(e.toString(), contains('尝试次数过多'));
    }
  });

  test('rpc 使用 typert 信封并返回 value', () async {
    http.Request? captured;
    final client = ApiClient(
      origin: Uri.parse('http://host:39081'),
      password: 'pw',
      client: MockClient((request) async {
        if (request.url.path == '/_dsh_mobile/v1/login') {
          return http.Response(
            jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
            200,
          );
        }
        captured = request;
        return http.Response(
          jsonEncode({
            'type': 'server-response',
            'rpcId': 'whatever',
            'result': {
              'ok': true,
              'value': {'items': []},
            },
          }),
          200,
        );
      }),
    );
    final value = await client.rpc('session/list', args: {'_request': {}});
    expect(value, {'items': []});
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['type'], 'client-request');
    expect(body['method'], 'session/list');
    expect((body['payload'] as Map)['args'], {'_request': {}});
    expect(body['rpcId'], isA<String>());
    expect(captured!.url.path, '/api/session/list');
    expect(captured!.headers['authorization'], 'Bearer ${'t' * 43}');
  });

  test('rpc ok:false 转为 ServerException', () async {
    final client = ApiClient(
      origin: Uri.parse('http://host:39081'),
      password: 'pw',
      client: MockClient((request) async {
        if (request.url.path == '/_dsh_mobile/v1/login') {
          return http.Response(
            jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'type': 'server-response',
            'rpcId': 'x',
            'result': {
              'ok': false,
              'error': {
                'code': 'gateway/arguments-invalid',
                'message': 'bad args',
                'details': {},
              },
            },
          }),
          200,
        );
      }),
    );
    expect(
      () => client.rpc('session/list', args: {'_request': {}}),
      throwsA(isA<ServerException>()),
    );
  });

  test('rpc 401 时重登一次并重放', () async {
    var rpcCalls = 0;
    var loginCalls = 0;
    final client = ApiClient(
      origin: Uri.parse('http://host:39081'),
      password: 'pw',
      client: MockClient((request) async {
        if (request.url.path == '/_dsh_mobile/v1/login') {
          loginCalls++;
          return http.Response(
            jsonEncode({'token': 't$loginCalls' * 21, 'expiresIn': 43200}),
            200,
          );
        }
        rpcCalls++;
        if (rpcCalls == 1) {
          return http.Response(
            jsonEncode({'error': 'authentication_required'}),
            401,
          );
        }
        return http.Response(
          jsonEncode({
            'type': 'server-response',
            'rpcId': 'x',
            'result': {'ok': true, 'value': 42},
          }),
          200,
        );
      }),
    );
    final value = await client.rpc('session/list', args: {'_request': {}});
    expect(value, 42);
    expect(loginCalls, 2);
    expect(rpcCalls, 2);
  });

  test('连接失败转 NetworkException', () async {
    final client = ApiClient(
      origin: Uri.parse('http://host:39081'),
      password: 'pw',
      client: MockClient((_) async => throw http.ClientException('refused')),
    );
    expect(() => client.fetchInfo(), throwsA(isA<NetworkException>()));
  });
}
