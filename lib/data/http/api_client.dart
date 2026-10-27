import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 全局共享的 HTTP 客户端。
///
/// 统一三件事（之前它们散落在各个 service 里各写一份）：
///
/// 1. **超时**：默认 8s 连接 / 12s 接收；上传等长耗时请求用 [longRunning]。
/// 2. **重试**：只对幂等请求（GET/HEAD/OPTIONS/PUT）和网络类错误重试，
///    最多 2 次，指数退避。POST 一律不重试，避免重复提交。
/// 3. **日志**：仅 debug 生效，只打 method/path/status/耗时，
///    **不打印 query 和 body**，避免把 token、密码写进日志。
///
/// 用法：
/// ```dart
/// final resp = await ApiClient.dio.get<List<dynamic>>('https://.../api/list');
/// ```
///
/// 注意：需要手动处理重定向的场景（例如 CAS 登录要逐跳收集 cookie），
/// 请在 `Options` 里显式设置 `followRedirects: false`。
class ApiClient {
  ApiClient._();

  static final Dio _default = _build(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
  );

  static final Dio _longRunning = _build(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 120),
  );

  /// 普通接口。
  static Dio get dio => _default;

  /// 上传、导出、大文件等长耗时请求。
  static Dio get longRunning => _longRunning;

  static Dio _build({
    required Duration connectTimeout,
    required Duration receiveTimeout,
  }) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: receiveTimeout,
        // 4xx 不抛异常，交给调用方判断（与项目现有代码的约定一致）
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final retry = _RetryInterceptor();
    dio.interceptors.add(retry);
    retry.attach(dio);

    if (kDebugMode) {
      dio.interceptors.add(_LogInterceptor());
    }
    return dio;
  }
}

/// 只重试幂等请求 + 网络类错误。
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor();

  /// 最多重试 2 次（共 3 次请求）。
  static const int maxAttempts = 2;

  /// 首次退避 350ms，之后翻倍。
  static const Duration baseDelay = Duration(milliseconds: 350);

  static const Set<String> _idempotent = {'GET', 'HEAD', 'OPTIONS', 'PUT'};

  Dio? _dio;

  void attach(Dio dio) => _dio = dio;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final method = options.method.toUpperCase();
    final attempt = (options.extra[_kAttempt] as int?) ?? 0;

    if (!_idempotent.contains(method) ||
        attempt >= maxAttempts ||
        !_isRetryable(err)) {
      return handler.next(err);
    }

    final delay = baseDelay * pow(2, attempt).toDouble();
    await Future<void>.delayed(delay);

    options.extra[_kAttempt] = attempt + 1;
    try {
      final response = await _dio!.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static const String _kAttempt = 'api_retry_attempt';

  bool _isRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        return status >= 500 && status < 600;
      default:
        return false;
    }
  }
}

/// 调试日志：只打路径，不打 query / body。
class _LogInterceptor extends Interceptor {
  static const String _kStart = 'api_request_start_us';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_kStart] = DateTime.now().microsecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, err.response?.statusCode, error: err.type.name);
    handler.next(err);
  }

  void _log(RequestOptions options, int? status, {String? error}) {
    final start = options.extra[_kStart] as int?;
    final cost = start == null
        ? ''
        : ' ${(DateTime.now().microsecondsSinceEpoch - start) ~/ 1000}ms';
    final tail = error == null ? '' : ' ($error)';
    debugPrint(
      '[HTTP] ${options.method} ${options.uri.path} '
      '-> ${status ?? 'ERR'}$cost$tail',
    );
  }
}
