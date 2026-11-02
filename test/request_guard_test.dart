import 'package:flutter_test/flutter_test.dart';

import 'package:project_usst/data/request_guard.dart';

void main() {
  test('只有最新一次请求有效', () {
    final guard = RequestGuard();

    final first = guard.begin();
    expect(guard.isCurrent(first), isTrue);

    final second = guard.begin();
    expect(guard.isCurrent(second), isTrue);
    // 先发的那次在第二次 begin 之后就失效了，回来的结果必须丢弃
    expect(guard.isCurrent(first), isFalse);
  });

  test('invalidate 之后在途请求全部失效', () {
    final guard = RequestGuard();
    final token = guard.begin();
    guard.invalidate();
    expect(guard.isCurrent(token), isFalse);

    // 后续 begin 仍然可用
    final next = guard.begin();
    expect(guard.isCurrent(next), isTrue);
  });
}
