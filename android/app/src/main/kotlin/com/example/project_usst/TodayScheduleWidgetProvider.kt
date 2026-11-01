package com.example.project_usst

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * 课表与气象 4x2 桌面小组件 Provider
 *
 * 左侧：日期与周次、天气与降雨时间段（雨伞决策）
 * 右侧：可上下滑动的列表（支持「课表」与「待办作业」双模式，支持点击直达详情页）
 */
class TodayScheduleWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            try {
                updateAppWidget(context, appWidgetManager, appWidgetId)
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

            if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE ||
                intent.action == ACTION_REFRESH_SCHEDULE
            ) {
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
                val umbrellaAdvice = prefs.getString("weather_umbrella_advice", "无需带伞 🌤") ?: "无需带伞 🌤"
                val tempRange = prefs.getString("weather_temp_range", "--° ~ --°C") ?: "--° ~ --°C"

                val mode = prefs.getString("widget_view_mode", "schedule") ?: "schedule"
                val isTomorrow = prefs.getBoolean("schedule_is_tomorrow", false)
                val todoCount = prefs.getInt("todo_count", 0)

                val views = RemoteViews(context.packageName, R.layout.widget_today_schedule)

                // 1. 设置左侧栏文本
                views.setTextViewText(R.id.widget_week_text, weekText)
                views.setTextViewText(R.id.widget_date_text, dateText)
                views.setTextViewText(R.id.widget_weekday_text, weekdayText)

                views.setTextViewText(R.id.widget_weather_time, weatherTimeWindow)
                views.setTextViewText(R.id.widget_weather_probability, weatherProbability)
                views.setTextViewText(R.id.widget_umbrella_advice, umbrellaAdvice)
                views.setTextViewText(R.id.widget_temp_range, tempRange)

                // 2. 根据当前模式设置右侧标题与切换按钮
                if (mode == "todo") {
                    views.setTextViewText(R.id.widget_right_title, "待办作业 ($todoCount)")
                    views.setTextViewText(R.id.widget_toggle_btn, "📅 看课表")
                    views.setTextViewText(R.id.widget_empty_title, "🎉 暂无未完成待办")
                    views.setTextViewText(R.id.widget_empty_sub, "作业均已完成，尽情放松 ☕")
                } else {
                    val title = if (isTomorrow) "明日" else "今日课表"
                    views.setTextViewText(R.id.widget_right_title, title)
                    views.setTextViewText(R.id.widget_toggle_btn, "📝 查待办")
                    views.setTextViewText(R.id.widget_empty_title, "✨ 今日与明日均无课")
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

                // 5. 点击小组件左侧或空白处直接拉起应用（直达课表）
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
                views.setOnClickPendingIntent(R.id.widget_left_panel, pendingLaunch)
                views.setOnClickPendingIntent(R.id.widget_course_empty, pendingLaunch)

                // 6. 为列表项设置可传递深层跳转 URI 的点击模板 (Android 12+ 需 FLAG_MUTABLE)
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

                // 7. 提交更新并通知列表数据重绘
                appWidgetManager.updateAppWidget(appWidgetId, views)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_course_list)
            } catch (t: Throwable) {
                Log.e(TAG, "updateAppWidget 内部执行异常", t)
            }
        }
    }
}
