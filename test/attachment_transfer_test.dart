import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/attachment_cache.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/upload_file.dart';

class ChunkFile extends XFile {
  ChunkFile(this.size) : super('virtual');
  int size;
  int reads = 0;
  @override
  Future<int> length() async => size;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    reads++;
    final chunk = Uint8List(64 * 1024);
    for (var remaining = size; remaining > 0; remaining -= chunk.length) {
      yield remaining >= chunk.length ? chunk : Uint8List(remaining);
    }
  }
}

class StreamAdapter implements HttpClientAdapter {
  StreamAdapter(this.response);
  final ResponseBody Function(RequestOptions options) response;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async => response(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('litang-attachment-test-');
    AttachmentCache.directoryOverride = () async => temp;
  });
  tearDown(() async {
    await AttachmentCache.clear();
    AttachmentCache.directoryOverride = null;
    await temp.delete(recursive: true);
  });

  test('同名文件按账号、附件和版本区分；并发读取只下载一次', () async {
    String key(String account, String id, [String version = '']) =>
        AttachmentCache.key(
          source: 'tron',
          account: account,
          attachmentId: id,
          version: version,
        );
    var calls = 0;
    Future<String> load(String account, String id, [String version = '']) =>
        AttachmentCache.download(
          key: key(account, id, version),
          name: '实验报告.pdf',
          receive: (path, token) async {
            calls++;
            await File(path).writeAsString('$account/$id/$version');
          },
        );
    final paths = await Future.wait([
      load('A', '1'),
      load('A', '1'),
      load('A', '2'),
      load('B', '1'),
      load('A', '1', 'v2'),
    ]);
    expect(calls, 4);
    expect(paths[0], paths[1]);
    expect(paths.toSet(), hasLength(4));
    expect(await File(paths[2]).readAsString(), 'A/2/');
    await load('A', '1');
    expect(calls, 4);
  });

  test('下载失败或清缓存不会留下半文件，重试可以成功', () async {
    final begun = Completer<void>();
    final key = AttachmentCache.key(
      source: 'tron',
      account: 'A',
      attachmentId: '1',
    );
    final operation = AttachmentCache.download(
      key: key,
      name: 'a.pdf',
      receive: (path, token) async {
        await File(path).writeAsString('partial');
        begun.complete();
        throw await token.whenCancel;
      },
    );
    final failed = expectLater(operation, throwsA(isA<DioException>()));
    await begun.future;
    await AttachmentCache.clear();
    await failed;
    expect(await AttachmentCache.size(), 0);
    expect(
      await Directory('${temp.path}/downloads').list(recursive: true).toList(),
      isEmpty,
    );
    final path = await AttachmentCache.download(
      key: key,
      name: 'a.pdf',
      receive: (path, token) async {
        await File(path).writeAsString('complete');
      },
    );
    expect(await File(path).readAsString(), 'complete');
  });

  test('过期文件重新读取；下载异常不破坏已有完整文件', () async {
    final key = AttachmentCache.key(
      source: 'tron',
      account: 'A',
      attachmentId: '1',
    );
    final path = await AttachmentCache.download(
      key: key,
      name: 'x.pdf',
      receive: (path, token) async {
        await File(path).writeAsString('old');
      },
    );
    await File(path).setLastModified(DateTime(2020));
    await expectLater(
      AttachmentCache.download(
        key: key,
        name: 'x.pdf',
        receive: (path, token) async {
          await File(path).writeAsString('half');
          throw StateError('offline');
        },
      ),
      throwsStateError,
    );
    expect(await File(path).readAsString(), 'old');
    expect(await File('$path.part').exists(), isFalse);
    final refreshed = await AttachmentCache.download(
      key: key,
      name: 'x.pdf',
      receive: (part, token) async {
        await File(part).writeAsString('new');
        expect(await File(path).readAsString(), 'old');
      },
    );
    expect(refreshed, path);
    expect(await File(path).readAsString(), 'new');
    expect(await File('$path.part').exists(), isFalse);
  });

  test('50 MiB 上传校验不读内容，Multipart 按 64 KiB 分块消费', () async {
    final file = ChunkFile(UploadFile.maxSingleBytes);
    final selected = UploadFile(
      file: file,
      name: 'large.bin',
      length: file.size,
    );
    await UploadFile.validateAll([selected, selected]);
    expect(file.reads, 0);
    expect(UploadFile.selectionError(1, UploadFile.maxTotalBytes), isNotNull);
    var count = 0;
    var largest = 0;
    await for (final bytes in selected.multipart().finalize()) {
      count += bytes.length;
      if (bytes.length > largest) largest = bytes.length;
    }
    expect(count, 50 * 1024 * 1024);
    expect(largest, lessThanOrEqualTo(64 * 1024));
    file.size++;
    await expectLater(UploadFile.validateAll([selected]), throwsStateError);
  });

  test('附件 HTTP 流处理重定向、进度和截断，拒绝登录 HTML', () async {
    final dio = Dio(
      BaseOptions(followRedirects: false, validateStatus: (_) => true),
    );
    dio.httpClientAdapter = StreamAdapter((request) {
      if (request.path == '/start') {
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['/file'],
          },
        );
      }
      return ResponseBody(
        Stream.fromIterable([
          Uint8List.fromList([1, 2]),
          Uint8List.fromList([3, 4]),
        ]),
        200,
        headers: {
          'content-length': ['4'],
          'content-type': ['application/pdf'],
        },
      );
    });
    final client = CasClient(dio: dio);
    final path = '${temp.path}/stream.pdf';
    var progress = 0;
    await client.downloadFile(
      Uri.parse('https://school.test/start'),
      path,
      onReceiveProgress: (current, total) {
        progress = current;
      },
    );
    expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
    expect(progress, 4);
    dio.httpClientAdapter = StreamAdapter(
      (_) => ResponseBody.fromString(
        'short',
        200,
        headers: {
          'content-length': ['100'],
        },
      ),
    );
    await expectLater(
      client.downloadFile(Uri.parse('https://school.test/file'), path),
      throwsStateError,
    );
    expect(await File(path).exists(), isFalse);
    dio.httpClientAdapter = StreamAdapter(
      (_) => ResponseBody.fromString(
        '<html>login</html>',
        200,
        headers: {
          'content-type': ['text/html'],
        },
      ),
    );
    await expectLater(
      client.downloadFile(Uri.parse('https://school.test/file'), path),
      throwsStateError,
    );
  });
}
