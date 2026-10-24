import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_mobile/core/models/dsh_models.dart';
import 'package:dsh_mobile/core/services/api_client.dart';
import 'package:dsh_mobile/core/services/dsh_api.dart';
import 'package:dsh_mobile/widgets/composer/attachment_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 1x1 PNG，用于走通尺寸校验分支。
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Directory tempDir = Directory.systemTemp;

Future<String> writeFixture(String name, List<int> bytes) async {
  final file = File('${tempDir.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

final _pngBytes = base64Decode(_pngBase64);
final _gifBytes = Uint8List.fromList([
  0x47,
  0x49,
  0x46,
  0x38,
  0x39,
  0x61,
  ...List.filled(32, 0),
]);
final _webpBytes = Uint8List.fromList([
  0x52, 0x49, 0x46, 0x46, // RIFF
  0x00, 0x00, 0x00, 0x00,
  0x57, 0x45, 0x42, 0x50, // WEBP
  ...List.filled(32, 0),
]);

void main() {
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dsh-attachments');
  });
  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('sniffImageMediaType', () {
    test('四种宿主白名单格式按文件头识别', () {
      expect(sniffImageMediaType(Uint8List.fromList(_pngBytes)), 'image/png');
      expect(
        sniffImageMediaType(
          Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, ...List.filled(16, 0)]),
        ),
        'image/jpeg',
      );
      expect(sniffImageMediaType(Uint8List.fromList(_gifBytes)), 'image/gif');
      expect(sniffImageMediaType(Uint8List.fromList(_webpBytes)), 'image/webp');
    });

    test('未知格式返回 null，不再静默当 png', () {
      expect(
        sniffImageMediaType(Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04])),
        isNull,
      );
      expect(
        sniffImageMediaType(Uint8List.fromList([0x52, 0x49, 0x46, 0x46])),
        isNull,
      );
    });
  });

  group('图片校验走宿主 imageLimits 全量维度', () {
    AttachmentStore storeWith({ImageLimits limits = const ImageLimits()}) {
      return AttachmentStore(
        api: DshApi(ApiClient(origin: Uri.parse('http://h:1'), password: 'p')),
        sessionId: 's1',
        limits: limits,
      );
    }

    test('数量超限按宿主文案拒绝', () async {
      final store = storeWith(
        limits: const ImageLimits(maxImagesPerMessage: 1),
      );
      final path = await writeFixture('a.png', _pngBytes);
      expect(await store.addImages([path]), isNull);
      final rejection = await store.addImages([path]);
      expect(rejection?.message, '一条消息最多添加 1 张图片');
      expect(store.imageCount, 1);
    });

    test('单图字节超限拒绝', () async {
      final store = storeWith(limits: const ImageLimits(maxImageBytes: 8));
      final path = await writeFixture('big.png', _pngBytes);
      final rejection = await store.addImages([path]);
      expect(rejection?.message, contains('图片过大'));
    });

    test('非白名单 mediaType 拒绝', () async {
      final store = storeWith(
        limits: const ImageLimits(mediaTypes: ['image/png']),
      );
      final path = await writeFixture('a.gif', _gifBytes);
      final rejection = await store.addImages([path]);
      expect(rejection?.message, contains('image/gif'));
    });

    test('合计字节超限拒绝第二张', () async {
      final store = storeWith(
        limits: ImageLimits(maxMessageImageBytes: _pngBytes.length),
      );
      final path = await writeFixture('a.png', _pngBytes);
      expect(await store.addImages([path]), isNull);
      final rejection = await store.addImages([path]);
      expect(rejection?.message, '一条消息的图片合计超过上限');
    });

    test('无法识别的文件头直接拒绝', () async {
      final store = storeWith();
      final path = await writeFixture('note.txt', utf8.encode('hello'));
      final rejection = await store.addImages([path]);
      expect(rejection?.message, contains('仅支持 PNG'));
    });
  });

  group('文件：选择即上传、并发 2、进度、失败重试', () {
    test('FIFO 并发不超过 2，全部就绪后可发送', () async {
      var inFlight = 0;
      var peak = 0;
      final gates = <String, Completer<void>>{};
      final api = DshApi(
        ApiClient(
          origin: Uri.parse('http://h:1'),
          password: 'p',
          client: MockClient((request) async {
            if (request.url.path == '/_dsh_mobile/v1/login') {
              return http.Response(
                jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
                200,
              );
            }
            final name = request.url.queryParameters['name'] ?? '';
            inFlight++;
            peak = peak > inFlight ? peak : inFlight;
            gates[name] = Completer<void>();
            await gates[name]!.future;
            inFlight--;
            return http.Response(
              jsonEncode({
                'ok': true,
                'value': {
                  'receiptId': 'r-$name',
                  'file': {'attachmentId': 'a-$name', 'name': name, 'bytes': 5},
                },
              }),
              200,
            );
          }),
        ),
      );
      final store = AttachmentStore(api: api, sessionId: 's1');
      final paths = [
        for (final name in ['one', 'two', 'three'])
          await writeFixture(name, List.filled(5, 0x41)),
      ];

      await store.addFiles(paths);
      await pumpEventQueue();
      expect(peak, AttachmentStore.maxConcurrentUploads);
      expect(store.hasUploading, isTrue);
      expect(store.sendBlocker, '文件还在上传，请等待上传完成后发送');

      // 队列里第三条要等前两条腾出并发位才开始，逐轮放行。
      for (var round = 0; round < 3; round++) {
        for (final gate in gates.values.toList()) {
          if (!gate.isCompleted) gate.complete();
        }
        await pumpEventQueue();
      }
      expect(store.hasUploading, isFalse);
      expect(store.sendBlocker, isNull);
      final attachments = store.buildAttachments();
      expect(attachments, hasLength(3));
      expect(attachments!.map((item) => item.toContentItem()).toList(), [
        {'type': 'file', 'receiptId': 'r-one'},
        {'type': 'file', 'receiptId': 'r-two'},
        {'type': 'file', 'receiptId': 'r-three'},
      ]);
    });

    test('上传失败阻断发送，重试成功后放行', () async {
      var shouldFail = true;
      final api = DshApi(
        ApiClient(
          origin: Uri.parse('http://h:1'),
          password: 'p',
          client: MockClient((request) async {
            if (request.url.path == '/_dsh_mobile/v1/login') {
              return http.Response(
                jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
                200,
              );
            }
            if (shouldFail) {
              return http.Response(
                jsonEncode({
                  'ok': false,
                  'error': {'code': 'upload_rejected', 'message': '宿主拒绝'},
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'ok': true,
                'value': {
                  'receiptId': 'r-ok',
                  'file': {'attachmentId': 'a-ok', 'name': 'a.txt', 'bytes': 5},
                },
              }),
              200,
            );
          }),
        ),
      );
      final store = AttachmentStore(api: api, sessionId: 's1');
      final path = await writeFixture('a.txt', List.filled(5, 0x41));
      await store.addFiles([path]);
      await pumpEventQueue();
      expect(store.failed, hasLength(1));
      expect(store.sendBlocker, '有文件上传失败，请重试或移除');

      shouldFail = false;
      store.retry(store.failed.single);
      await pumpEventQueue();
      expect(store.failed, isEmpty);
      expect(store.buildAttachments()?.single.toContentItem(), {
        'type': 'file',
        'receiptId': 'r-ok',
      });
    });

    test('原始路由用 octet-stream 与 sessionId/name 查询参数', () async {
      http.Request? seen;
      final api = DshApi(
        ApiClient(
          origin: Uri.parse('http://h:1'),
          password: 'p',
          client: MockClient((request) async {
            if (request.url.path == '/_dsh_mobile/v1/login') {
              return http.Response(
                jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
                200,
              );
            }
            seen = request;
            return http.Response(
              jsonEncode({
                'ok': true,
                'value': {
                  'receiptId': 'r1',
                  'file': {'attachmentId': 'a1', 'name': 'a.txt', 'bytes': 3},
                },
              }),
              200,
            );
          }),
        ),
      );
      final store = AttachmentStore(api: api, sessionId: 's1');
      await store.addFiles([
        await writeFixture('a.txt', [1, 2, 3]),
      ]);
      await pumpEventQueue();
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/session/uploadFileBinary');
      expect(seen!.url.queryParameters['sessionId'], 's1');
      expect(seen!.url.queryParameters['name'], 'a.txt');
      expect(
        seen!.headers['content-type'],
        contains('application/octet-stream'),
      );
      expect(seen!.bodyBytes, [1, 2, 3]);
    });
  });

  group('图片与文件按选择顺序混排', () {
    test('buildAttachments 保持加入顺序', () async {
      final api = DshApi(
        ApiClient(
          origin: Uri.parse('http://h:1'),
          password: 'p',
          client: MockClient((request) async {
            if (request.url.path == '/_dsh_mobile/v1/login') {
              return http.Response(
                jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'ok': true,
                'value': {
                  'receiptId': 'r1',
                  'file': {'attachmentId': 'a1', 'name': 'doc.txt', 'bytes': 3},
                },
              }),
              200,
            );
          }),
        ),
      );
      final store = AttachmentStore(api: api, sessionId: 's1');
      final imagePath = await writeFixture('a.png', _pngBytes);
      final filePath = await writeFixture('doc.txt', [1, 2, 3]);
      await store.addImages([imagePath]);
      await store.addFiles([filePath]);
      await pumpEventQueue();

      final items = store.buildAttachments()!;
      expect(items, hasLength(2));
      expect(items.first, isA<PromptImage>());
      expect(items.last, isA<PromptFile>());
      expect(store.imageCount, 1);
      expect((items.first as PromptImage).mediaType, 'image/png');
      expect(items.last.toContentItem(), {'type': 'file', 'receiptId': 'r1'});
    });
  });

  group('惰性会话：新建会话页附件先选、会话后建', () {
    test('无会话时文件排队不发起上传，attachSession 后开泵', () async {
      final seen = <http.Request>[];
      final api = DshApi(
        ApiClient(
          origin: Uri.parse('http://h:1'),
          password: 'p',
          client: MockClient((request) async {
            if (request.url.path == '/_dsh_mobile/v1/login') {
              return http.Response(
                jsonEncode({'token': 't' * 43, 'expiresIn': 43200}),
                200,
              );
            }
            seen.add(request);
            return http.Response(
              jsonEncode({
                'ok': true,
                'value': {
                  'receiptId': 'r1',
                  'file': {'attachmentId': 'a1', 'name': 'a.txt', 'bytes': 3},
                },
              }),
              200,
            );
          }),
        ),
      );
      final store = AttachmentStore(api: api);
      expect(store.hasSession, isFalse);
      final path = await writeFixture('a.txt', [1, 2, 3]);
      await store.addFiles([path]);
      await pumpEventQueue();
      // 等会话阶段：不发起上传，但也不静默放行发送。
      expect(seen, isEmpty);
      expect(store.sendBlocker, '正在创建会话，请稍候…');

      store.attachSession('s9');
      await pumpEventQueue();
      expect(store.hasSession, isTrue);
      expect(store.sendBlocker, isNull);
      expect(seen, hasLength(1));
      expect(seen.single.url.queryParameters['sessionId'], 's9');
      expect(store.buildAttachments()?.single.toContentItem(), {
        'type': 'file',
        'receiptId': 'r1',
      });
    });

    test('图片不依赖会话，无会话也不阻断发送', () async {
      final api = DshApi(
        ApiClient(origin: Uri.parse('http://h:1'), password: 'p'),
      );
      final store = AttachmentStore(api: api);
      final path = await writeFixture('a.png', _pngBytes);
      expect(await store.addImages([path]), isNull);
      expect(store.sendBlocker, isNull);
    });
  });
}
