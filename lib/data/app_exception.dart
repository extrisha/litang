/// 数据层统一的失败类型。
///
/// 背景：项目里同一个仓库并存四种失败表达方式，导致至少 7 处页面把「取不到」
/// 显示成「没有数据」：
///
/// | 写法 | 用在哪 | 后果 |
/// |---|---|---|
/// | 抛异常 | grades / rank / space_booking | 页面能区分 |
/// | 返回空列表 | fetchRooms（原）、chaoxing 课程详情（原） | 显示「暂无」 |
/// | 返回 null | UpdateService.check（原） | 显示「已是最新」 |
/// | 静默重试后仍空 | life_page 学习通分支（原） | 显示「暂无」 |
///
/// 现约定（写进 docs/refactor-backlog.md，新代码必须遵守）：
///
/// 1. `fetch*` / `get*` 这类**取数据**的方法，失败必须抛 [AppException]；
/// 2. 返回 `null` 只能表示「服务端确实没有这一项数据」；
/// 3. 返回空列表只能表示「确实没有条目」；
/// 4. 页面用 `AsyncStateView` 渲染 `loading / error / empty` 三态。
enum AppFailure {
  /// 未登录、会话过期、被服务端判为无权限（401/403，或网关把过期 token
  /// 判成的 400）
  auth,

  /// 连不上、超时、DNS 失败
  network,

  /// 拿到的内容不是预期格式（HTML 登录页、字段缺失、JSON 解析失败）
  parse,

  /// 服务端明确报错（5xx、业务错误码）
  server,

  /// 其它
  unknown,
}

/// 数据层失败。[message] 是可以直接展示给用户的人话。
class AppException implements Exception {
  const AppException(this.failure, this.message, [this.cause]);

  final AppFailure failure;
  final String message;

  /// 原始异常，仅用于日志。
  final Object? cause;

  /// 是否属于「重新登录就能解决」的问题。
  bool get needsRelogin => failure == AppFailure.auth;

  @override
  String toString() => message;
}
