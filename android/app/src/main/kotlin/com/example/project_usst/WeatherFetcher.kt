package com.example.project_usst

import android.content.Context
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar

/**
 * 原生天气抓取：小组件刷新时直接在 Android 侧请求 Open-Meteo 并写盘。
 *
 * 为什么不继续走 Flutter 后台回调：那条路要经过
 * 广播 → WorkManager → 拉起 Flutter 引擎 → 后台 isolate，
 * 在部分国产系统（省电策略严格）上会被直接掐掉，表现为「点了刷新但天气不变」。
 * 这里退化成一次普通 HTTPS 请求 + JSON 解析，只要进程能起来就一定能跑。
 *
 * 规则与 Dart 侧 `WeatherService.summarize` 保持一致：只看当前小时及之后的降水，
 * 返回「正在降雨 · 至 15:00」「15:00 起降雨」这类一句话。
 */
object WeatherFetcher {
    private const val TAG = "WeatherFetcher"

    private const val USST_LAT = 31.2917
    private const val USST_LON = 121.5517

    private const val URL_TEMPLATE =
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s" +
            "&hourly=temperature_2m,precipitation_probability,precipitation,weather_code" +
            "&timezone=Asia%%2FShanghai&forecast_days=1"

    /** 抓取并写回 SharedPreferences；成功返回 true。调用方需要在后台线程执行。 */
    fun refresh(context: Context): Boolean {
        val prefs = HomeWidgetPlugin.getData(context)
        return try {
            val json = request()
            val hourly = json.optJSONObject("hourly") ?: return fail(prefs, "缺少 hourly")
            val times = hourly.optJSONArray("time") ?: return fail(prefs, "缺少 time")
            val temps = hourly.optJSONArray("temperature_2m") ?: return fail(prefs, "缺少温度")
            if (times.length() == 0 || temps.length() == 0) return fail(prefs, "逐小时数据为空")

            val probs = hourly.optJSONArray("precipitation_probability")
            val precips = hourly.optJSONArray("precipitation")
            val codes = hourly.optJSONArray("weather_code")

            var minTemp = Double.MAX_VALUE
            var maxTemp = -Double.MAX_VALUE
            for (i in 0 until temps.length()) {
                val t = temps.optDouble(i, Double.NaN)
                if (t.isNaN()) continue
                if (t < minTemp) minTemp = t
                if (t > maxTemp) maxTemp = t
            }
            if (minTemp == Double.MAX_VALUE) return fail(prefs, "温度全为空")

            val nowHour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            val upcoming = ArrayList<Int>()
            val past = ArrayList<Int>()
            var maxProb = 0
            var upcomingMaxProb = 0
            var snow = false

            for (i in 0 until times.length()) {
                val hour = parseHour(times.optString(i, "")) ?: continue
                val prob = probs?.optInt(i, 0) ?: 0
                val precip = precips?.optDouble(i, 0.0) ?: 0.0
                val code = codes?.optInt(i, 0) ?: 0
                if (prob > maxProb) maxProb = prob

                val wet = prob >= 40 || precip >= 0.1 || isRainOrSnow(code)
                if (!wet) continue
                if (hour < nowHour) {
                    past.add(hour)
                } else {
                    upcoming.add(hour)
                    if (prob > upcomingMaxProb) upcomingMaxProb = prob
                    if (isSnow(code)) snow = true
                }
            }

            val type = if (snow) "降雪" else "降雨"
            val hasUpcoming = upcoming.isNotEmpty()
            val window: String
            val umbrella: String
            when {
                hasUpcoming && upcoming.contains(nowHour) -> {
                    val end = upcoming.max()
                    window = "正在$type · 至 ${end + 1}:00"
                    umbrella = if (snow) "带伞防滑" else "带伞"
                }
                hasUpcoming -> {
                    val start = upcoming.min()
                    val ranges = groupContinuous(upcoming)
                    window = "${start}:00 起$type" + if (ranges.size > 1) "等" else ""
                    umbrella = "稍后带伞"
                }
                past.isNotEmpty() -> {
                    window = "今日后续无雨"
                    umbrella = ""
                }
                else -> {
                    window = "今日全天无雨"
                    umbrella = ""
                }
            }

            prefs.edit()
                .putString("weather_time_window", window)
                .putString("weather_temp_range", "${minTemp.toInt()}° ~ ${maxTemp.toInt()}°C")
                .putString("weather_umbrella_advice", umbrella)
                .putString(
                    "weather_probability",
                    if (hasUpcoming) "降水概率 $upcomingMaxProb%" else "全天干爽"
                )
                .putBoolean("weather_has_rain", hasUpcoming)
                .putString("weather_icon_type", if (hasUpcoming) (if (snow) "snow" else "rain") else "cloudy")
                .putLong("weather_synced_at", System.currentTimeMillis())
                .remove("weather_last_error")
                .apply()
            true
        } catch (t: Throwable) {
            Log.w(TAG, "天气抓取失败", t)
            fail(prefs, t.message ?: t.javaClass.simpleName)
        }
    }

    private fun request(): JSONObject {
        val url = URL(String.format(java.util.Locale.US, URL_TEMPLATE, USST_LAT, USST_LON))
        val conn = url.openConnection() as HttpURLConnection
        return try {
            conn.requestMethod = "GET"
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty("Accept", "application/json")
            if (conn.responseCode !in 200..299) {
                throw IllegalStateException("HTTP ${conn.responseCode}")
            }
            val body = conn.inputStream.bufferedReader().use { it.readText() }
            JSONObject(body)
        } finally {
            conn.disconnect()
        }
    }

    private fun fail(
        prefs: android.content.SharedPreferences,
        reason: String
    ): Boolean {
        prefs.edit()
            .putString("weather_last_error", reason)
            .putLong("weather_last_attempt_at", System.currentTimeMillis())
            .apply()
        return false
    }

    private fun parseHour(iso: String): Int? {
        // "2026-11-14T15:00"
        val idx = iso.indexOf('T')
        if (idx < 0 || iso.length < idx + 3) return null
        return iso.substring(idx + 1, idx + 3).toIntOrNull()
    }

    private fun isRainOrSnow(code: Int): Boolean =
        (code in 51..67) || (code in 71..86) || (code in 95..99)

    private fun isSnow(code: Int): Boolean =
        code == 71 || code == 73 || code == 75 || code == 77 || code == 85 || code == 86

    private fun groupContinuous(hours: List<Int>): List<IntRange> {
        val sorted = hours.distinct().sorted()
        if (sorted.isEmpty()) return emptyList()
        val out = ArrayList<IntRange>()
        var start = sorted.first()
        var end = start
        for (i in 1 until sorted.size) {
            if (sorted[i] == end + 1) {
                end = sorted[i]
            } else {
                out.add(start..end)
                start = sorted[i]
                end = start
            }
        }
        out.add(start..end)
        return out
    }
    /** 距离上次成功抓取超过 [minIntervalMs] 才抓一次，给 30 分钟的 onUpdate 用。 */
    fun refreshIfStale(context: Context, minIntervalMs: Long = 30 * 60 * 1000L) {
        val prefs = HomeWidgetPlugin.getData(context)
        val last = prefs.getLong("weather_synced_at", 0L)
        if (System.currentTimeMillis() - last < minIntervalMs) return
        Thread {
            try {
                if (refresh(context)) {
                    TodayScheduleWidgetProvider.updateAll(context)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "定期抓取异常", t)
            }
        }.start()
    }
}