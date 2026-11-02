import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/app_exception.dart';
import 'package:project_usst/data/auth/cas_client.dart';
import 'package:project_usst/data/jwc/rank_api.dart';
import 'package:project_usst/data/jwc/space_booking_api.dart';
import 'package:project_usst/services/dorm_electricity_service.dart';

/// 锁定「所有业务异常都是 AppException 子类」这个约定：
/// 页面只需要一套 `catch (AppException e) => e.message`，
/// 不用为每种业务失败各写一个 catch 分支。
void main() {
  test('CAS 登录失败归为 auth', () {
    const e = CasLoginException('密码错误');
    expect(e, isA<AppException>());
    expect(e.failure, AppFailure.auth);
    expect(e.message, '密码错误');
    expect(e.needsRelogin, isTrue);
  });

  test('专业排名失败归为 server，且不需要重登', () {
    const e = RankException('排名数据解析失败');
    expect(e.failure, AppFailure.server);
    expect(e.needsRelogin, isFalse);
  });

  test('空间预约按 authRelated 分到 auth / server', () {
    final auth = SpaceBookingException('登录已失效', authRelated: true);
    expect(auth.failure, AppFailure.auth);
    expect(auth.authRelated, isTrue);
    expect(auth.needsRelogin, isTrue);

    final other = SpaceBookingException('房间列表解析失败');
    expect(other.failure, AppFailure.server);
    expect(other.authRelated, isFalse);
  });

  test('宿舍电费失败也是 AppException', () {
    const e = DormElectricityException('查询失败');
    expect(e, isA<AppException>());
    expect(e.message, '查询失败');
  });
}
