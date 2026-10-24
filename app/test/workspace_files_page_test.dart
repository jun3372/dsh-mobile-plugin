import 'dart:convert';

import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/core/services/api_client.dart';
import 'package:dsh_mobile/core/services/dsh_api.dart';
import 'package:dsh_mobile/features/servers/servers_providers.dart';
import 'package:dsh_mobile/features/sessions/workspace_files_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response okRpc(Object? value) => http.Response(
    jsonEncode({
      'type': 'server-response',
      'rpcId': 'x',
      'result': {'ok': true, 'value': value},
    }),
    200,
  );

  testWidgets('按目录浏览：根目录展示子项，点文件夹进入下一层', (tester) async {
    final api = DshApi(
      ApiClient(
        origin: Uri.parse('http://host:39081'),
        password: 'pw',
        client: MockClient((request) async {
          if (request.url.path == '/_dsh_mobile/v1/login') {
            return http.Response(
              jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
              200,
            );
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final args = (body['payload'] as Map)['args'] as Map;
          if (request.url.path == '/api/workspaceFiles/read') {
            return okRpc({
              'offset': 1,
              'text': '# README\n\nworkspace preview',
              'lines': 3,
              'eof': true,
              'bytes': 24,
            });
          }
          final path = args['path'] as String? ?? '';
          if (path.isEmpty || path == '.') {
            return okRpc({
              'path': '',
              'entries': [
                {'name': 'lib', 'type': 'directory'},
                {'name': 'README.md', 'type': 'file', 'size': 1536},
                {'name': 'link', 'type': 'other'},
              ],
              'truncated': false,
            });
          }
          return okRpc({
            'path': 'lib',
            'entries': [
              {'name': 'main.dart', 'type': 'file', 'size': 2048},
            ],
            'truncated': true,
          });
        }),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dshApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: buildDshTheme(Brightness.light),
          home: const WorkspaceFilesPage(sessionId: 's1', cwd: '/repo'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('repo'), findsOneWidget);
    expect(find.text('/repo'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('/repo/lib'), findsOneWidget);
    expect(find.text('条目过多，仅显示前 1 项'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();

    expect(find.text('/repo/README.md'), findsOneWidget);
    expect(find.textContaining('workspace preview'), findsOneWidget);
  });
}
