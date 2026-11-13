package com.example.project_usst

import android.content.SharedPreferences
import org.json.JSONArray
import java.util.Calendar

/**
 * 两种规格（4×2 / 4×1）共用的取数逻辑。
 *
 * 数据都来自 Flutter 侧写进 SharedPreferences 的快照：`courses_json` 是
 * `performNativeScheduleRollover` 推演出来的「今天（或下一次有课那天）」列表，
 * 每条带 `startMin/endMin`，所以这里只做筛选，不重复解析课表。
 */
object WidgetData {
    /** 4×1 卡片要显示的那一节。 */
    data class NextCourse(
        val name: String,
        val time: String,
        val room: String,
        val teacher: String,
        val status: String,
        val startMin: Int,
        val endMin: Int
    )

    fun nowMinuteOfDay(): Int {
        val cal = Calendar.getInstance()
        return cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
    }

    /**
     * 当前应该显示的那一节：优先「正在上」，其次「今天还没开始的最近一节」。
     * 全都上完了返回 null（卡片显示「今日已无课」）。
     */
    fun nextCourse(prefs: SharedPreferences): NextCourse? {
        val raw = prefs.getString("courses_json", "") ?: ""
        if (raw.isEmpty()) return null
        return try {
            val array = JSONArray(raw)
            val now = nowMinuteOfDay()
            val all = ArrayList<NextCourse>(array.length())
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                val start = obj.optInt("startMin", -1)
                val end = obj.optInt("endMin", -1)
                if (start < 0 || end < 0) continue // 待办条目没有节次
                all.add(
                    NextCourse(
                        name = obj.optString("name", "课程"),
                        time = obj.optString("time", ""),
                        room = obj.optString("room", ""),
                        teacher = obj.optString("teacher", ""),
                        status = obj.optString("status", "upcoming"),
                        startMin = start,
                        endMin = end
                    )
                )
            }
            if (all.isEmpty()) return null
            all.sortBy { it.startMin }
            val ongoing = all.firstOrNull { now in it.startMin..it.endMin }
            val upcoming = all.firstOrNull { it.startMin > now }
            // 未来某天的列表整份都是「还没上」的，取第一节；
            // 今天的列表如果全上完了就返回 null，卡片显示「今日已无课」。
            return if (daysAhead(prefs) > 0) upcoming ?: all.firstOrNull()
            else ongoing ?: upcoming
        } catch (_: Throwable) {
            null
        }
    }

    /** 4×1 左上角的「第 N 周」。 */
    fun weekText(prefs: SharedPreferences): String =
        prefs.getString("today_week_text", "第 1 周") ?: "第 1 周"

    /** 4×1 左下角的「周五」。 */
    fun weekdayText(prefs: SharedPreferences): String =
        prefs.getString("today_weekday_text", "周一") ?: "周一"

    /** 列表里显示的是几天后的课（0 = 今天）。 */
    fun daysAhead(prefs: SharedPreferences): Int =
        prefs.getInt("schedule_days_ahead", 0).coerceAtLeast(0)

    /** 当前列表里的课程条数（`courses_json` 的长度）。 */
    fun courseCount(prefs: SharedPreferences): Int {
        val raw = prefs.getString("courses_json", "") ?: ""
        if (raw.isEmpty()) return 0
        return try {
            JSONArray(raw).length()
        } catch (_: Throwable) {
            0
        }
    }

    /**
     * 右栏头部那一句天气：`15:00 起降雨 · 带伞`。
     *
     * Dart 侧的伞具文案带 emoji（`出门带伞 ☔`），小组件不放图标，所以这里
     * 收成「带伞 / 稍后带伞」两个短词，保证一行放得下。
     */
    fun weatherLine(timeWindow: String, umbrellaAdvice: String): String {
        val base = timeWindow.trim().ifEmpty { "今日无雨" }
        val umbrella = when {
            umbrellaAdvice.isBlank() -> ""
            umbrellaAdvice.contains("稍后") -> "稍后带伞"
            else -> "带伞"
        }
        return if (umbrella.isEmpty()) base else "$base · $umbrella"
    }

    /**
     * 偏移 [daysAhead] 天之后是周几。
     *
     * 卡片上的日期永远写「今天」，而列表在有课的那天之前可能显示的是未来某天
     * 的课，必须把目标那天也标出来，否则周六看到周一的三节课很容易被当成
     * 今天要上。
     */
    fun weekdayTextForOffset(daysAhead: Int): String {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_YEAR, daysAhead)
        val index = if (cal.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY) {
            6
        } else {
            cal.get(Calendar.DAY_OF_WEEK) - 2
        }
        return arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")[index]
    }
}
