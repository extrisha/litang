import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/lms/todo_api.dart';

class _Client extends CasClient {
  _Client(this.userId);
  final String userId;
  int indexRequests = 0;
  bool failIndex = false;
  final List<String> coursePaths = [];

  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    if (uri.path == '/user/index') {
      indexRequests++;
      await Future<void>.delayed(Duration.zero);
      if (failIndex) throw StateError('offline');
      return Response(
        requestOptions: RequestOptions(path: uri.toString()),
        statusCode: 200,
        data: '<input id="userId" value="$userId">',
      );
    }
    coursePaths.add(uri.path);
    return Response(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: 200,
      data: '{"courses":[]}',
    );
  }
}

void main() {
  test('换账号使用新会话的用户 ID，同一会话合并用户页读取', () async {
    final a = _Client('user-a');
    final b = _Client('user-b');
    await Future.wait([
      LmsApi(a).fetchCourseInfos(),
      LmsApi(a).fetchCourseInfos(),
      LmsApi(b).fetchCourseInfos(),
    ]);
    expect(a.indexRequests, 1);
    expect(b.indexRequests, 1);
    expect(a.coursePaths, everyElement('/api/users/user-a/courses'));
    expect(b.coursePaths, ['/api/users/user-b/courses']);
  });

  test('读取用户页失败不缓存失败 Future，下一次能够恢复', () async {
    final client = _Client('recovered')..failIndex = true;
    await expectLater(LmsApi(client).fetchCourseInfos(), throwsException);
    client.failIndex = false;
    await LmsApi(client).fetchCourseInfos();
    expect(client.indexRequests, 2);
    expect(client.coursePaths, ['/api/users/recovered/courses']);
  });
}
