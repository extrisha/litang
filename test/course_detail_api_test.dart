import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/lms/course_detail_api.dart';

/// 只回固定 JSON 的假客户端：不发网络请求，专用来锁定解析逻辑。
class _FakeCasClient extends CasClient {
  _FakeCasClient(this.routes);

  /// key 是请求路径，value 是接口返回的 JSON 文本。
  final Map<String, String> routes;

  @override
  Future<Response<String>> getApi(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final body = routes[uri.path];
    if (body == null) {
      // 模拟接口 404 / 会话失效：调用方必须自己兜住
      throw StateError('未预置响应：${uri.path}');
    }
    return Response<String>(
      requestOptions: RequestOptions(path: uri.path),
      statusCode: 200,
      data: body,
    );
  }
}

Map<String, String> _routes({
  String activities = '{"activities":[]}',
  String modules = '{"modules":[]}',
  String bulletins = '{"bulletins":[]}',
  String exams = '{"exams":[]}',
  Map<String, String> extra = const <String, String>{},
}) {
  return <String, String>{
    '/api/courses/42/activities': activities,
    '/api/courses/42/modules': modules,
    '/api/courses/42/bulletins': bulletins,
    '/api/courses/42/exams': exams,
    ...extra,
  };
}

void main() {
  test('homework 活动要进作业列表，且不能混进章节', () async {
    final api = TronCourseDetailApi(
      _FakeCasClient(
        _routes(
          activities:
              '{"activities":['
              '{"id":101,"type":"homework","title":"第二章计算作业",'
              '"end_time":"2026-10-25T13:59:00Z",'
              '"data":{"description":"<p>完成第二章习题</p>"}},'
              '{"id":102,"type":"material","module_id":"m1","title":"课件",'
              '"data":{"description":"第一章"}}'
              ']}',
          modules: '{"modules":[{"id":"m1","name":"模块一"}]}',
        ),
      ),
    );

    final detail = await api.fetch('42');

    expect(detail.homeworks, hasLength(1));
    final homework = detail.homeworks.single;
    expect(homework.id, 101);
    expect(homework.title, '第二章计算作业');
    expect(homework.description, '完成第二章习题');
    // yyyy-MM-dd HH:mm
    expect(homework.deadline.length, 16);
    expect(homework.deadline.substring(0, 10), '2026-10-25');
    expect(detail.chapters.map((c) => c.title), <String>['课件']);
  });

  test('截止时间只写在 data 里也能取到', () async {
    final api = TronCourseDetailApi(
      _FakeCasClient(
        _routes(
          activities:
              '{"activities":[{"id":9,"type":"homework","title":"周报",'
              '"data":{"description":"写周报","end_time":"2026-11-01T15:00:00Z"}}]}',
        ),
      ),
    );

    final detail = await api.fetch('42');

    expect(detail.homeworks.single.deadline.length, 16);
    expect(detail.homeworks.single.deadline.substring(0, 10), '2026-11-01');
  });

  test('论坛进讨论、考试两边都不进、视频进章节', () async {
    final api = TronCourseDetailApi(
      _FakeCasClient(
        _routes(
          activities:
              '{"activities":['
              '{"id":1,"type":"forum","title":"提问贴","forum_count":3},'
              '{"id":2,"type":"exam","title":"期中测验"},'
              '{"id":3,"type":"online_video","title":"第一讲",'
              '"data":{"publish_time":"2026-09-10T08:00:00Z"}}'
              ']}',
        ),
      ),
    );

    final detail = await api.fetch('42');

    expect(detail.discussions.single.title, '提问贴');
    expect(detail.discussions.single.replies, 3);
    expect(detail.chapters.single.title, '第一讲');
    expect(detail.chapters.single.typeLabel, '视频');
    expect(detail.chapters.single.publishTime.length, 16);
    expect(detail.homeworks, isEmpty);
  });

  test('某场考试的分数接口失败，不影响整张列表', () async {
    final api = TronCourseDetailApi(
      _FakeCasClient(
        _routes(
          exams:
              '{"exams":['
              '{"id":7,"title":"期末考试","start_time":"2027-01-05T09:00:00Z",'
              '"end_time":"2027-01-05T11:00:00Z","is_closed":true},'
              '{"id":8,"title":"小测","is_started":true}'
              ']}',
          extra: <String, String>{
            '/api/exams/7/submissions': '{"exam_score":88.5}',
            // 8 号考试故意不预置响应，应该降级成"没分数"而不是抛错
          },
        ),
      ),
    );

    final detail = await api.fetch('42');

    expect(detail.exams, hasLength(2));
    expect(detail.exams.first.title, '期末考试');
    expect(detail.exams.first.status, '已结束');
    expect(detail.exams.first.score, 88.5);
    expect(detail.exams.last.status, '进行中');
    expect(detail.exams.last.score, isNull);
  });

  test('公告 uploads 里的 .rar 会被解析成附件', () async {
    final api = TronCourseDetailApi(
      _FakeCasClient(
        _routes(
          bulletins:
              '{"bulletins":[{"title":"第7周10月19日开始上课",'
              '"content":"<p>分组名单见附件</p>","created_at":"2026-10-19T08:00:00Z",'
              '"uploads":[{"id":29627219,"name":"26271分组.rar","size":2048}]}]}',
        ),
      ),
    );

    final detail = await api.fetch('42');

    final announcement = detail.announcements.single;
    expect(announcement.title, '第7周10月19日开始上课');
    expect(announcement.attachments.single.name, '26271分组.rar');
    expect(announcement.attachments.single.id, 29627219);
    expect(announcement.attachments.single.size, 2048);
  });
}
