package com.example.project_usst

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * 课表与气象 4x2 桌面小组件 Provider
 *
 * 左侧：日期与周次、天气与降雨时间段（雨伞决策，点击天气卡片就地静默刷新）
 * 右侧：可上下滑动的列表（支持「课表」与「待办作业」双模式，支持离线跨天自动感知与 X 天后下一次课预告）
 */
class TodayScheduleWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        try {
            val prefs = HomeWidgetPlugin.getData(context)
            performNativeScheduleRollover(context, prefs)
        } catch (t: Throwable) {
            Log.e(TAG, "onUpdate 原生跨天推演异常", t)
        }

        for (appWidgetId in appWidgetIds) {
            try {
                updateAppWidget(context, appWidgetManager, appWidgetId)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_course_list)
            } catch (t: Throwable) {
                Log.e(TAG, "更新小组件异常 (id: $appWidgetId)", t)
            }
        }
        super.onUpdate(context, appWidgetManager, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        try {
            val appWidgetManager = AppWidgetManager.getInstance(context)

            // 模式切换：课表 <-> 待办作业
            if (intent.action == ACTION_TOGGLE_VIEW_MODE) {
                val prefs = HomeWidgetPlugin.getData(context)
                val curMode = prefs.getString("widget_view_mode", "schedule") ?: "schedule"
                val newMode = if (curMode == "schedule") "todo" else "schedule"
                prefs.edit().putString("widget_view_mode", newMode).apply()

                val thisWidget = ComponentName(context, TodayScheduleWidgetProvider::class.java)
                val allIds = appWidgetManager.getAppWidgetIds(thisWidget)
                for (id in allIds) {
                    try {
                        updateAppWidget(context, appWidgetManager, id)
                        appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_course_list)
                    } catch (t: Throwable) {
                        Log.e(TAG, "切换模式刷新小组件异常 (id: $id)", t)
                    }
                }
                return
            }

            // 点击天气卡片触发就地刷新（方案 B）
            if (intent.action == ACTION_REFRESH_SCHEDULE) {
                val prefs = HomeWidgetPlugin.getData(context)
                // 1. 本地原生跨天推演立竿见影执行
                performNativeScheduleRollover(context, prefs)

                // 2. 界面即时刷新
                val thisWidget = ComponentName(context, TodayScheduleWidgetProvider::class.java)
                val allIds = appWidgetManager.getAppWidgetIds(thisWidget)
                for (id in allIds) {
                    try {
                        updateAppWidget(context, appWidgetManager, id)
                        appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_course_list)
                    } catch (t: Throwable) {
                        Log.e(TAG, "刷新小组件异常 (id: $id)", t)
                    }
                }

                // 3. 轻量级系统 Toast 提示用户
                try {
                    Toast.makeText(context, "理堂：正在刷新天气与课表...", Toast.LENGTH_SHORT).show()
                } catch (_: Throwable) {}

                // 4. 触发后台同步服务（通过 WorkManager / HomeWidgetBackgroundReceiver 静默拉取 Open-Meteo 天气）
                try {
                    val bgIntent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
                        action = "es.antonborri.home_widget.action.BACKGROUND"
                        data = Uri.parse("litang://refresh")
                    }
                    context.sendBroadcast(bgIntent)
                } catch (t: Throwable) {
                    Log.e(TAG, "触发后台同步广播失败", t)
                }
                return
            }

            if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
                val prefs = HomeWidgetPlugin.getData(context)
                performNativeScheduleRollover(context, prefs)

                val thisWidget = ComponentName(context, TodayScheduleWidgetProvider::class.java)
                val allIds = appWidgetManager.getAppWidgetIds(thisWidget)
                for (id in allIds) {
                    try {
                        updateAppWidget(context, appWidgetManager, id)
                        appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_course_list)
                    } catch (t: Throwable) {
                        Log.e(TAG, "广播更新小组件异常 (id: $id)", t)
                    }
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "onReceive 异常", t)
        }
    }

    companion object {
        private const val TAG = "TodayWidgetProvider"
        const val ACTION_REFRESH_SCHEDULE = "com.example.project_usst.ACTION_REFRESH_SCHEDULE"
        const val ACTION_TOGGLE_VIEW_MODE = "com.example.project_usst.ACTION_TOGGLE_VIEW_MODE"

        /** 课表里的一节：起止分钟（0 点起算）。 */
        private data class Period(val startMin: Int, val endMin: Int) {
            fun fmt(minute: Int): String =
                String.format(Locale.CHINA, "%02d:%02d", minute / 60, minute % 60)
        }

        /**
         * Flutter 侧写入的作息时间（`semester_period_times_json`，如 `["08:00-08:40", ...]`）。
         *
         * 13 节课的起止时间只在 `JwglSchedule.periods` 定义一次，小组件必须复用它。
         * 之前这里自己维护了一份 50 分钟一节的旧作息，导致小组件显示的时间和 App 里对不上。
         * 读不到（老版本装机还没写过这个 key）才退回下面的旧表。
         */
        private fun loadPeriods(prefs: SharedPreferences): List<Period> {
            try {
                val raw = prefs.getString("semester_period_times_json", "") ?: ""
                if (raw.isNotEmpty()) {
                    val array = JSONArray(raw)
                    val parsed = ArrayList<Period>(array.length())
                    for (i in 0 until array.length()) {
                        val parts = array.getString(i).split("-")
                        if (parts.size != 2) continue
                        val s = parts[0].split(":")
                        val e = parts[1].split(":")
                        if (s.size != 2 || e.size != 2) continue
                        val startHour = s[0].toIntOrNull() ?: continue
                        val startMinute = s[1].toIntOrNull() ?: continue
                        val endHour = e[0].toIntOrNull() ?: continue
                        val endMinute = e[1].toIntOrNull() ?: continue
                        parsed.add(
                            Period(
                                startMin = startHour * 60 + startMinute,
                                endMin = endHour * 60 + endMinute
                            )
                        )
                    }
                    if (parsed.size == LEGACY_PERIODS.size) return parsed
                    Log.w(TAG, "作息条目数不符（${parsed.size}），退回内置表")
                }
            } catch (t: Throwable) {
                Log.w(TAG, "读取作息时间失败，退回内置表", t)
            }
            return LEGACY_PERIODS
        }

        /** 老版本内置作息（50 分钟一节）。只在 Flutter 还没写入新表时兜底。 */
        private val LEGACY_PERIODS: List<Period> = listOf(
            Period(8 * 60, 8 * 60 + 40),
            Period(8 * 60 + 50, 9 * 60 + 30),
            Period(9 * 60 + 55, 10 * 60 + 35),
            Period(10 * 60 + 45, 11 * 60 + 25),
            Period(11 * 60 + 35, 12 * 60 + 15),
            Period(13 * 60, 13 * 60 + 40),
            Period(13 * 60 + 50, 14 * 60 + 30),
            Period(14 * 60 + 55, 15 * 60 + 35),
            Period(15 * 60 + 45, 16 * 60 + 25),
            Period(16 * 60 + 35, 17 * 60 + 15),
            Period(18 * 60, 18 * 60 + 40),
            Period(18 * 60 + 50, 19 * 60 + 30),
            Period(19 * 60 + 40, 20 * 60 + 20)
        )

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            try {
                val prefs = HomeWidgetPlugin.getData(context)

                val weekText = prefs.getString("today_week_text", "第 9 周") ?: "第 9 周"
                val dateText = prefs.getString("today_date_text", "11月01日") ?: "11月01日"
                val weekdayText = prefs.getString("today_weekday_text", "周日") ?: "周日"

                val weatherTimeWindow = prefs.getString("weather_time_window", "今日全天无雨") ?: "今日全天无雨"
                val weatherProbability = prefs.getString("weather_probability", "全天干爽") ?: "全天干爽"
                val umbrellaAdvice = prefs.getString("weather_umbrella_advice", "") ?: ""
                val tempRange = prefs.getString("weather_temp_range", "--° ~ --°C") ?: "--° ~ --°C"

                val mode = prefs.getString("widget_view_mode", "schedule") ?: "schedule"
                val daysAhead = prefs.getInt("schedule_days_ahead", 0)
                val defaultTitle = if (daysAhead == 0) "今日课表" else if (daysAhead == 1) "明日" else "${daysAhead}天后"
                val scheduleTitle = prefs.getString("schedule_title_text", defaultTitle) ?: defaultTitle
                val todoCount = prefs.getInt("todo_count", 0)

                val views = RemoteViews(context.packageName, R.layout.widget_today_schedule)

                // 1. 设置左侧栏文本
                views.setTextViewText(R.id.widget_week_text, weekText)
                views.setTextViewText(R.id.widget_date_text, dateText)
                views.setTextViewText(R.id.widget_weekday_text, weekdayText)

                views.setTextViewText(R.id.widget_weather_time, weatherTimeWindow)
                views.setTextViewText(R.id.widget_weather_probability, weatherProbability)
                // 当天后续没雨时 Dart 侧给空串，这里把整个胶囊隐藏，避免出现空胶囊
                if (umbrellaAdvice.isBlank()) {
                    views.setViewVisibility(R.id.widget_umbrella_advice, View.GONE)
                } else {
                    views.setViewVisibility(R.id.widget_umbrella_advice, View.VISIBLE)
                    views.setTextViewText(R.id.widget_umbrella_advice, umbrellaAdvice)
                }
                views.setTextViewText(R.id.widget_temp_range, tempRange)

                // 2. 根据当前模式设置右侧标题与切换按钮
                if (mode == "todo") {
                    views.setTextViewText(R.id.widget_right_title, "待办作业 ($todoCount)")
                    views.setTextViewText(R.id.widget_toggle_btn, "📅 看课表")
                    views.setTextViewText(R.id.widget_empty_title, "🎉 暂无未完成待办")
                    views.setTextViewText(R.id.widget_empty_sub, "作业均已完成，尽情放松 ☕")
                } else {
                    views.setTextViewText(R.id.widget_right_title, scheduleTitle)
                    views.setTextViewText(R.id.widget_toggle_btn, "📝 查待办")
                    views.setTextViewText(R.id.widget_empty_title, "✨ 近期均无课程")
                    views.setTextViewText(R.id.widget_empty_sub, "享受轻松大学时光 ☕")
                }

                // 3. 绑定模式切换按钮广播
                val toggleIntent = Intent(context, TodayScheduleWidgetProvider::class.java).apply {
                    action = ACTION_TOGGLE_VIEW_MODE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                val togglePending = PendingIntent.getBroadcast(
                    context,
                    appWidgetId,
                    toggleIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_toggle_btn, togglePending)

                // 4. 绑定右侧可滑动的 ListView 适配器
                val serviceIntent = Intent(context, TodayScheduleWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                }
                views.setRemoteAdapter(R.id.widget_course_list, serviceIntent)
                views.setEmptyView(R.id.widget_course_list, R.id.widget_course_empty)

                // 5. 点击左上角日期直达 App 课表
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                    data = Uri.parse("litang://schedule")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingLaunch = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_date_panel, pendingLaunch)
                views.setOnClickPendingIntent(R.id.widget_left_panel, pendingLaunch)
                views.setOnClickPendingIntent(R.id.widget_course_empty, pendingLaunch)

                // 6. 点击天气卡片触发就地静默刷新（方案 B）
                val refreshIntent = Intent(context, TodayScheduleWidgetProvider::class.java).apply {
                    action = ACTION_REFRESH_SCHEDULE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                val refreshPending = PendingIntent.getBroadcast(
                    context,
                    appWidgetId + 2000,
                    refreshIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_weather_panel, refreshPending)

                // 7. 为列表项设置可传递深层跳转 URI 的点击模板 (Android 12+ 需 FLAG_MUTABLE)
                val listTemplateIntent = Intent(context, MainActivity::class.java).apply {
                    action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val flagMutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_MUTABLE
                } else {
                    0
                }
                val pendingListTemplate = PendingIntent.getActivity(
                    context,
                    0,
                    listTemplateIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or flagMutable
                )
                views.setPendingIntentTemplate(R.id.widget_course_list, pendingListTemplate)

                // 8. 提交更新并通知列表数据重绘
                appWidgetManager.updateAppWidget(appWidgetId, views)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_course_list)
            } catch (t: Throwable) {
                Log.e(TAG, "updateAppWidget 内部执行异常", t)
            }
        }

        /**
         * 原生离线跨天推演：无需唤醒 Flutter 引擎即可在本地自动推演当前日期、教学周次与目标课程
         */
        private fun performNativeScheduleRollover(context: Context, prefs: SharedPreferences) {
            try {
                val week1MondayStr = prefs.getString("semester_week1_monday", "") ?: ""
                val allCoursesJsonStr = prefs.getString("semester_all_courses_json", "") ?: ""
                if (week1MondayStr.isEmpty() || allCoursesJsonStr.isEmpty()) {
                    return
                }

                val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA)
                val week1MondayDate = sdf.parse(week1MondayStr) ?: return

                val now = Calendar.getInstance()
                val nowTime = now.time

                val calWeek1 = Calendar.getInstance().apply {
                    time = week1MondayDate
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                val calToday = Calendar.getInstance().apply {
                    time = nowTime
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }

                val diffDays = ((calToday.timeInMillis - calWeek1.timeInMillis) / (1000 * 60 * 60 * 24)).toInt()
                val currentWeek = (diffDays / 7) + 1
                val totalWeeks = prefs.getInt("semester_total_weeks", 20)
                if (currentWeek < 1 || currentWeek > totalWeeks) {
                    return
                }

                val month = now.get(Calendar.MONTH) + 1
                val dayOfMonth = now.get(Calendar.DAY_OF_MONTH)
                val calDayOfWeek = now.get(Calendar.DAY_OF_WEEK)
                val dayIndex = if (calDayOfWeek == Calendar.SUNDAY) 6 else calDayOfWeek - 2
                val weekdaysArr = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")

                val dateText = String.format(Locale.CHINA, "%02d月%02d日", month, dayOfMonth)
                val weekdayText = weekdaysArr[dayIndex]
                val weekText = "第 $currentWeek 周"

                prefs.edit()
                    .putString("today_week_text", weekText)
                    .putString("today_date_text", dateText)
                    .putString("today_weekday_text", weekdayText)
                    .apply()

                val allCoursesArray = JSONArray(allCoursesJsonStr)
                data class NativeCourse(
                    val name: String,
                    val day: Int,
                    val start: Int,
                    val span: Int,
                    val room: String,
                    val teacher: String,
                    val weeks: Set<Int>,
                    val accentColor: String,
                    val bgColor: String,
                    val textColor: String
                )

                val allCourses = mutableListOf<NativeCourse>()
                for (i in 0 until allCoursesArray.length()) {
                    val obj = allCoursesArray.getJSONObject(i)
                    val weeksArr = obj.optJSONArray("weeks")
                    val weeksSet = mutableSetOf<Int>()
                    if (weeksArr != null) {
                        for (w in 0 until weeksArr.length()) {
                            weeksSet.add(weeksArr.getInt(w))
                        }
                    }
                    allCourses.add(
                        NativeCourse(
                            name = obj.optString("name", "未命名"),
                            day = obj.optInt("day", 0),
                            start = obj.optInt("start", 0),
                            span = obj.optInt("span", 1),
                            room = obj.optString("room", "待定教室"),
                            teacher = obj.optString("teacher", ""),
                            weeks = weeksSet,
                            accentColor = obj.optString("accentColor", "#1677FF"),
                            bgColor = obj.optString("bgColor", "#F7FAFC"),
                            textColor = obj.optString("textColor", "#1A202C")
                        )
                    )
                }

                val todayCourses = allCourses
                    .filter { it.day == dayIndex && it.weeks.contains(currentWeek) }
                    .sortedBy { it.start }

                // 作息时间由 Flutter 侧（JwglSchedule）统一提供，这里不再自己维护一份
                val periods = loadPeriods(prefs)

                val curHour = now.get(Calendar.HOUR_OF_DAY)
                val curMin = now.get(Calendar.MINUTE)
                val curMinuteOfDay = curHour * 60 + curMin

                val allPastToday = todayCourses.isNotEmpty() && todayCourses.all { c ->
                    val endSecIndex = (c.start + c.span - 1).coerceIn(0, periods.size - 1)
                    curMinuteOfDay > periods[endSecIndex].endMin
                }

                var daysAhead = 0
                var displayCourses = todayCourses

                if (todayCourses.isEmpty() || allPastToday) {
                    for (offset in 1..14) {
                        val futureCal = Calendar.getInstance().apply {
                            time = nowTime
                            add(Calendar.DAY_OF_YEAR, offset)
                        }
                        val futureCalToday = Calendar.getInstance().apply {
                            time = futureCal.time
                            set(Calendar.HOUR_OF_DAY, 0)
                            set(Calendar.MINUTE, 0)
                            set(Calendar.SECOND, 0)
                            set(Calendar.MILLISECOND, 0)
                        }
                        val futureDiffDays = ((futureCalToday.timeInMillis - calWeek1.timeInMillis) / (1000 * 60 * 60 * 24)).toInt()
                        val futureWeek = (futureDiffDays / 7) + 1
                        val futureDayOfWeek = futureCal.get(Calendar.DAY_OF_WEEK)
                        val futureDayIndex = if (futureDayOfWeek == Calendar.SUNDAY) 6 else futureDayOfWeek - 2

                        val futureCourses = allCourses
                            .filter { it.day == futureDayIndex && it.weeks.contains(futureWeek) }
                            .sortedBy { it.start }

                        if (futureCourses.isNotEmpty()) {
                            daysAhead = offset
                            displayCourses = futureCourses
                            break
                        }
                    }
                }

                val courseListJson = JSONArray()
                for (c in displayCourses) {
                    val startSec = c.start + 1
                    val endSec = c.start + c.span
                    val periodText = if (c.span > 1) "第 $startSec-$endSec 节" else "第 $startSec 节"

                    val startIdx = c.start.coerceIn(0, periods.size - 1)
                    val endIdx = (endSec - 1).coerceIn(0, periods.size - 1)
                    val timeRange =
                        "${periods[startIdx].fmt(periods[startIdx].startMin)}-${periods[endIdx].fmt(periods[endIdx].endMin)}"

                    // 与 App 内 _computeStatus 一致：已结课 / 进行中 / 距上课
                    val statusInfo = if (daysAhead > 0) {
                        "upcoming" to ""
                    } else {
                        val startMinute = periods[startIdx].startMin
                        val endMinute = periods[endIdx].endMin
                        when {
                            curMinuteOfDay > endMinute -> "past" to "已结课"
                            curMinuteOfDay >= startMinute ->
                                "ongoing" to "进行中 (剩${endMinute - curMinuteOfDay}m)"
                            startMinute - curMinuteOfDay in 1..45 ->
                                "upcoming" to "距上课${startMinute - curMinuteOfDay}m"
                            else -> "upcoming" to ""
                        }
                    }

                    val itemObj = JSONObject().apply {
                        put("name", c.name)
                        put("period", periodText)
                        put("time", timeRange)
                        put("room", c.room)
                        put("teacher", c.teacher)
                        put("accentColor", c.accentColor)
                        put("bgColor", c.bgColor)
                        put("textColor", c.textColor)
                        put("status", statusInfo.first)
                        put("statusTag", statusInfo.second)
                        put("linkUri", "litang://schedule")
                    }
                    courseListJson.put(itemObj)
                }

                val title = when (daysAhead) {
                    0 -> "今日课表"
                    1 -> "明日"
                    else -> "${daysAhead}天后"
                }

                prefs.edit()
                    .putInt("schedule_days_ahead", daysAhead)
                    .putBoolean("schedule_is_tomorrow", daysAhead == 1)
                    .putString("schedule_title_text", title)
                    .putString("courses_json", courseListJson.toString())
                    .apply()

            } catch (t: Throwable) {
                Log.e(TAG, "performNativeScheduleRollover 执行异常", t)
            }
        }
    }
}
