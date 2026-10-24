import 'dart:convert';

import 'package:dsh_mobile/app/theme.dart';
import 'package:dsh_mobile/core/services/api_client.dart';
import 'package:dsh_mobile/core/services/dsh_api.dart';
import 'package:dsh_mobile/features/servers/servers_providers.dart';
import 'package:dsh_mobile/features/sessions/workspace_file_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 取预览区实际渲染的富文本：SelectableText 把 span 交给内部
/// EditableText 的 controller（_TextSpanEditingController），
/// 3.41 的渲染层已不再有 RichText，只能从 controller 反查。
InlineSpan _previewSpan(WidgetTester tester) {
  final finder = find.byType(EditableText);
  final EditableText editable = tester.widget(finder);
  return editable.controller.buildTextSpan(
    context: tester.element(finder),
    withComposing: false,
  );
}

/// 展开富文本 span 树，返回 (文本片段, 生效颜色)，用于断言着色。
List<(String, Color?)> _colors(InlineSpan root) {
  final out = <(String, Color?)>[];
  void walk(InlineSpan span, Color? inherited) {
    if (span is! TextSpan) return;
    final color = span.style?.color ?? inherited;
    if (span.text != null && span.text!.isNotEmpty) {
      out.add((span.text!, color));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, color);
    }
  }

  walk(root, null);
  return out;
}

void main() {
  http.Response okRpc(Object? value) => http.Response(
    jsonEncode({
      'type': 'server-response',
      'rpcId': 'x',
      'result': {'ok': true, 'value': value},
    }),
    200,
  );

  DshApi apiWith(Future<http.Response> Function(http.Request) handler) =>
      DshApi(
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
            return handler(request);
          }),
        ),
      );

  Widget wrap(DshApi api, Widget page) => ProviderScope(
    overrides: [dshApiProvider.overrideWithValue(api)],
    child: MaterialApp(theme: buildDshTheme(Brightness.light), home: page),
  );

  testWidgets('代码文件：等宽渲染并带行号、行数与路径', (tester) async {
    final api = apiWith(
      (_) async => okRpc({
        'offset': 1,
        'text': 'void main() {\n  runApp();\n}',
        'lines': 3,
        'eof': true,
        'bytes': 32,
      }),
    );

    await tester.pumpWidget(
      wrap(
        api,
        const WorkspaceFilePreviewPage(
          sessionId: 's1',
          cwd: '/repo',
          path: 'lib/main.dart',
          name: 'main.dart',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('/repo/lib/main.dart'), findsOneWidget);
    expect(find.textContaining('void main()'), findsOneWidget);
    expect(find.textContaining('runApp();'), findsOneWidget);
    expect(find.text('已显示全部 3 行'), findsOneWidget);

    // 语法高亮：void 走关键字色，整体不止两种颜色。
    final colored = _colors(_previewSpan(tester));
    expect(
      colored.where((c) => c.$1 == 'void' && c.$2 == const Color(0xFF9A38B5)),
      isNotEmpty,
      reason: '未高亮：$colored',
    );
    expect(colored.map((c) => c.$2).toSet().length, greaterThan(2));
  });

  testWidgets('图片文件：走 readBytes 并以内置解码器展示', (tester) async {
    const boundary = 'img-boundary';
    // 1×1 透明 PNG。
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
      'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    final api = apiWith((_) async {
      final metadata = jsonEncode({
        'type': 'server-response',
        'rpcId': 'x',
        'result': {
          'ok': true,
          'value': {
            'offset': 0,
            'data': null,
            'eof': true,
            'bytes': png.length,
          },
        },
        'attachments': [
          {
            'path': ['data'],
            'codec': 'bytes',
            'part': 'bytes-0',
          },
        ],
      });
      final body = <int>[
        ...utf8.encode('--$boundary\r\n'),
        ...utf8.encode(
          'content-disposition: form-data; name="metadata"\r\n'
          'content-type: application/json\r\n\r\n',
        ),
        ...utf8.encode(metadata),
        ...utf8.encode('\r\n--$boundary\r\n'),
        ...utf8.encode(
          'content-disposition: form-data; name="bytes-0"\r\n'
          'content-type: application/octet-stream\r\n\r\n',
        ),
        ...png,
        ...utf8.encode('\r\n--$boundary--\r\n'),
      ];
      return http.Response.bytes(
        body,
        200,
        headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
      );
    });

    await tester.pumpWidget(
      wrap(
        api,
        const WorkspaceFilePreviewPage(
          sessionId: 's1',
          cwd: '/repo',
          path: 'assets/logo.png',
          name: 'logo.png',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('logo.png'), findsOneWidget);
    expect(find.text('/repo/assets/logo.png'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('PNG · ${png.length} B'), findsOneWidget);
  });

  testWidgets('代码高亮：未知扩展名退回纯文本，行号仍然对齐', (tester) async {
    final api = apiWith(
      (_) async => okRpc({
        'offset': 1,
        'text': 'first line\nsecond line',
        'lines': 2,
        'eof': true,
        'bytes': 22,
      }),
    );

    await tester.pumpWidget(
      wrap(
        api,
        const WorkspaceFilePreviewPage(
          sessionId: 's1',
          cwd: '/repo',
          path: 'notes.unknown',
          name: 'notes.unknown',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('first line'), findsOneWidget);
    expect(find.textContaining('second line'), findsOneWidget);
    expect(find.text('已显示全部 2 行'), findsOneWidget);
    final colors = _colors(_previewSpan(tester));
    // 没有高亮片段，只有正文色与行号色。
    expect(colors.map((c) => c.$2).toSet().length, lessThan(3));
  });

  testWidgets('二进制文件：不渲染乱码，提示不可预览', (tester) async {
    final api = apiWith(
      (_) async => okRpc({
        'offset': 1,
        'text': 'PK\u0000\u0001binary',
        'lines': 1,
        'eof': true,
        'bytes': 9,
      }),
    );

    await tester.pumpWidget(
      wrap(
        api,
        const WorkspaceFilePreviewPage(
          sessionId: 's1',
          cwd: '/repo',
          path: 'assets/fixture.zip',
          name: 'fixture.zip',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('该文件类型暂不支持预览'), findsOneWidget);
    expect(find.textContaining('binary'), findsNothing);
  });
}
