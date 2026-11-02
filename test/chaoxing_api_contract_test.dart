import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/app_exception.dart';
import 'package:project_usst/data/chaoxing/chaoxing_client.dart';
import 'package:project_usst/data/chaoxing/chaoxing_course_detail.dart';

/// 契约回归：抓到的页面其实是登录页 / 空页时，必须抛 [AppException]，
/// 不能返回空列表——否则页面会显示「暂无章节/暂无作业/暂无考试」，
/// 把「登录失效」伪装成「没有内容」。
class _FakeClient extends ChaoxingClient {
  _FakeClient(this.html);

  final String html;

  @override
  Future<Response<dynamic>> getPage(
    Uri uri, {
    Map<String, String>? headers,
  }) async => Response<dynamic>(
    requestOptions: RequestOptions(path: uri.toString()),
    statusCode: 200,
    data: html,
  );
}

void main() {
  const course = ChaoxingCourse(
    courseId: '1',
    classId: '2',
    cpi: '3',
    name: '测试课程',
    teacher: '老师',
  );

  test('抓到登录页时抛 auth 类异常', () async {
    final api = ChaoxingCourseDetailApi(
      _FakeClient(
        '<html><a href="https://passport2.chaoxing.com/login">请登录</a></html>',
      ),
    );
    await expectLater(
      api.fetchChapters(course),
      throwsA(
        isA<AppException>().having(
          (e) => e.failure,
          'failure',
          AppFailure.auth,
        ),
      ),
    );
  });

  test('抓到空页面时抛 parse 类异常', () async {
    final api = ChaoxingCourseDetailApi(_FakeClient('   '));
    await expectLater(
      api.fetchExams(course),
      throwsA(
        isA<AppException>().having(
          (e) => e.failure,
          'failure',
          AppFailure.parse,
        ),
      ),
    );
  });

  test('正常页面不会被误判（空考试列表照常返回）', () async {
    final api = ChaoxingCourseDetailApi(
      _FakeClient('<html><body><div class="exam-list"></div></body></html>'),
    );
    final exams = await api.fetchExams(course);
    expect(exams, isEmpty);
  });
}
