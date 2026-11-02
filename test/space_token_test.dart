import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/jwc/space_booking_api.dart';

/// 回归测试：token 提前刷新余量。
///
/// 原来是固定 600 秒。服务端 `expires` 只有 900 秒时，可用窗口只剩 300 秒
/// （5 分钟），挂机一会儿就失效；`expires` ≤ 600 时更是「签发即过期」，
/// 每次调用都要重走一遍 CAS 登录。
void main() {
  SpaceBookingApi apiWith({
    required int expiresInSeconds,
    required Duration elapsed,
  }) {
    final api = SpaceBookingApi()
      ..accessToken =
          'not-a-jwt' // 非 JWT，强制走 tokenObtainedAt 分支
      ..tokenExpiresInSeconds = expiresInSeconds
      ..tokenObtainedAt = DateTime.now().subtract(elapsed);
    return api;
  }

  test('900 秒寿命的 token 在第 8 分钟仍然可用', () {
    // 旧逻辑：900 - 600 = 300 秒，480 > 300 会被判失效 → 又登录一次
    final api = apiWith(
      expiresInSeconds: 900,
      elapsed: const Duration(minutes: 8),
    );
    expect(api.isTokenValid, isTrue);
  });

  test('900 秒寿命的 token 在临近过期（第 790 秒）时判定需要刷新', () {
    // 余量 = clamp(900 * 0.2 = 180, 15, 120) = 120，可用 780 秒
    final api = apiWith(
      expiresInSeconds: 900,
      elapsed: const Duration(seconds: 790),
    );
    expect(api.isTokenValid, isFalse);
  });

  test('长寿命 token 的余量被夹在 120 秒，不会无限扩大', () {
    final api = apiWith(
      expiresInSeconds: 7200,
      elapsed: const Duration(seconds: 7200 - 121),
    );
    expect(api.isTokenValid, isTrue);

    final expired = apiWith(
      expiresInSeconds: 7200,
      elapsed: const Duration(seconds: 7200 - 119),
    );
    expect(expired.isTokenValid, isFalse);
  });

  test('短寿命 token 至少留 15 秒余量', () {
    final api = apiWith(
      expiresInSeconds: 40, // 40 * 0.2 = 8 → 夹到 15
      elapsed: const Duration(seconds: 20),
    );
    expect(api.isTokenValid, isTrue);

    final expired = apiWith(
      expiresInSeconds: 40,
      elapsed: const Duration(seconds: 30),
    );
    expect(expired.isTokenValid, isFalse);
  });

  test('没有 token 时一律无效', () {
    final api = SpaceBookingApi();
    expect(api.isTokenValid, isFalse);
  });
}
