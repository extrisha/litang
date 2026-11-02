/// 异步请求代次守卫。
///
/// 页面里「先发的请求后到」会让旧结果覆盖新状态（切换日期、切换账号、
/// 下拉刷新与切页并发）。用法：
///
/// ```dart
/// final token = _guard.begin();
/// final data = await fetch();
/// if (!_guard.isCurrent(token)) return; // 已经有更新的请求了，丢弃本次结果
/// setState(() => _data = data);
/// ```
class RequestGuard {
  int _current = 0;

  /// 开始新一轮请求，返回本次请求的代号。之前所有未完成的请求随之失效。
  int begin() => ++_current;

  /// 该代号是否仍是「最新一次」请求。
  bool isCurrent(int token) => token == _current;

  /// 主动让所有在途请求失效（例如页面销毁前）。
  void invalidate() => _current++;
}
