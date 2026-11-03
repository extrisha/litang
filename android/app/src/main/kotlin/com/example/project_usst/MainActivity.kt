package com.example.project_usst

import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 学习通「网页登录」用：把内嵌 WebView 登录后的 cookie 交回 Dart 侧。
 *
 * webview_flutter 4.x 没有读 cookie 的 API，httpOnly 的会话 cookie 用
 * document.cookie 也拿不到，所以只能走一层平台通道读系统 CookieManager。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "litang/web_cookies")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> {
                        val urls = call.argument<List<String>>("urls") ?: emptyList<String>()
                        // CookieManager 只能在主线程访问
                        Handler(Looper.getMainLooper()).post {
                            try {
                                val manager = CookieManager.getInstance()
                                manager.setAcceptCookie(true)
                                val out = HashMap<String, String>()
                                for (url in urls) {
                                    val raw = manager.getCookie(url)
                                    if (!raw.isNullOrEmpty()) {
                                        out[url] = raw
                                    }
                                }
                                result.success(out)
                            } catch (e: Exception) {
                                result.error("cookie_read_failed", e.message, null)
                            }
                        }
                    }

                    "clear" -> {
                        Handler(Looper.getMainLooper()).post {
                            try {
                                CookieManager.getInstance().removeAllCookies(null)
                                CookieManager.getInstance().flush()
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("cookie_clear_failed", e.message, null)
                            }
                        }
                    }

                    // 写入 cookie。
                    //
                    // 为什么要自己写：webview_flutter 的 WebViewCookieManager
                    // 只能拼 name=value; path=/，**设不了 Domain 属性**，于是
                    // `.usst.edu.cn` 这类父域 cookie 会被绑成 host-only，
                    // 跳去 ids6.usst.edu.cn 的 CAS 那一跳就拿不到 CASTGC，
                    // 用户必然要在网页里重新登录一次（还会顶掉 App 的会话）。
                    // 这里直接走系统 CookieManager，可以带上 Domain。
                    "write" -> {
                        @Suppress("UNCHECKED_CAST")
                        val cookies = call.argument<List<Map<String, String>>>("cookies")
                            ?: emptyList<Map<String, String>>()
                        Handler(Looper.getMainLooper()).post {
                            try {
                                val manager = CookieManager.getInstance()
                                manager.setAcceptCookie(true)
                                var count = 0
                                for (entry in cookies) {
                                    val url = entry["url"]
                                    val cookie = entry["cookie"]
                                    if (url.isNullOrEmpty() || cookie.isNullOrEmpty()) continue
                                    manager.setCookie(url, cookie)
                                    count++
                                }
                                manager.flush()
                                result.success(count)
                            } catch (e: Exception) {
                                result.error("cookie_write_failed", e.message, null)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
