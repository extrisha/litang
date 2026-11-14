package com.example.project_usst

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * 4×1 紧凑版：一行显示「周次 + 当前/下一节课 + 天气」。
 *
 * 和 4×2 版共用 [WidgetData] 快照与 [WidgetBackground] 外观，但布局完全独立
 * ——RemoteViews 没有响应式，两种规格只能各写一套 XML。
 */
class TodayCompactWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        TodayScheduleWidgetProvider.performNativeScheduleRollover(context, prefs)
        for (id in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, id)
        }
        super.onUpdate(context, appWidgetManager, appWidgetIds)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetWeatherAlarms.cancelIfOrphaned(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == TodayScheduleWidgetProvider.ACTION_REFRESH_SCHEDULE) {
            updateAll(context)
            // 顺手触发一次后台同步（天气）
            try {
                val bgIntent = Intent(context, es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java).apply {
                    action = "es.antonborri.home_widget.action.BACKGROUND"
                    data = Uri.parse("litang://refresh")
                }
                context.sendBroadcast(bgIntent)
            } catch (_: Throwable) {
            }
        }
    }

    companion object {
        private const val TAG = "TodayCompactWidget"

        fun updateAll(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                val component = ComponentName(context, TodayCompactWidgetProvider::class.java)
                val prefs = HomeWidgetPlugin.getData(context)
                TodayScheduleWidgetProvider.performNativeScheduleRollover(context, prefs)
                for (id in manager.getAppWidgetIds(component)) {
                    updateAppWidget(context, manager, id)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "更新紧凑版小程序失败", t)
            }
        }

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            try {
                val prefs = HomeWidgetPlugin.getData(context)
                val views = RemoteViews(
                    context.packageName,
                    R.layout.widget_today_schedule_compact
                )

                val style = prefs.getString("widget_style", WidgetBackground.STYLE_GLASS)
                    ?: WidgetBackground.STYLE_GLASS
                val alpha = prefs.getInt("widget_alpha", 85)
                val theme = WidgetThemeHelper.themeOf(context)
                val night = WidgetThemeHelper.isNight(context, theme)
                val colors = WidgetThemeHelper.colors(context, theme)
                try {
                    val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
                    val widthDp = options.getInt(
                        AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250
                    ).toFloat().coerceAtLeast(120f)
                    val heightDp = options.getInt(
                        AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 60
                    ).toFloat().coerceAtLeast(40f)
                    views.setImageViewBitmap(
                        R.id.widget_background,
                        WidgetBackground.build(
                            context, style, alpha, night, widthDp, heightDp
                        )
                    )
                } catch (_: Throwable) {
                }

                val daysAhead = WidgetData.daysAhead(prefs)
                views.setTextViewText(
                    R.id.compact_week,
                    if (daysAhead > 0) "$daysAhead 天后" else WidgetData.weekText(prefs)
                )
                views.setTextColor(R.id.compact_week, colors.accentRed)
                views.setTextViewText(
                    R.id.compact_weekday,
                    if (daysAhead > 0) {
                        WidgetData.weekdayTextForOffset(daysAhead)
                    } else {
                        WidgetData.weekdayText(prefs)
                    }
                )
                views.setTextColor(R.id.compact_weekday, colors.textPrimary)

                val course = WidgetData.nextCourse(prefs)
                if (course == null) {
                    views.setTextViewText(R.id.compact_title, "今日已无课")
                    views.setTextViewText(R.id.compact_sub, "")
                } else {
                    // 4×1 宽度有限：只取开始时间（08:00-09:25 → 08:00），
                    // 正在上的课用「现在」代替时间
                    val start = course.time.substringBefore("-").trim()
                    val prefix = when {
                        course.status == "ongoing" && daysAhead == 0 -> "现在"
                        start.isEmpty() -> "现在"
                        else -> start
                    }
                    views.setTextViewText(
                        R.id.compact_title,
                        "$prefix ${course.name}".trim()
                    )
                    views.setTextViewText(
                        R.id.compact_sub,
                        listOf(course.room, course.teacher)
                            .filter { it.isNotBlank() }
                            .joinToString(" · ")
                    )
                }

                // 4×1 右侧：温度在上、降雨在下
                views.setTextViewText(
                    R.id.compact_temp,
                    prefs.getString("weather_temp_range", "--°~--°C") ?: "--°~--°C"
                )
                views.setTextColor(R.id.compact_temp, colors.textPrimary)
                views.setTextViewText(
                    R.id.compact_weather,
                    prefs.getString("weather_time_window", "今日无雨") ?: "今日无雨"
                )
                views.setTextColor(R.id.compact_weather, colors.textMuted)

                views.setTextColor(R.id.compact_title, colors.textPrimary)
                views.setTextColor(R.id.compact_sub, colors.textSecondary)

                val launch = Intent(context, MainActivity::class.java).apply {
                    action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                    data = Uri.parse("litang://schedule")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        PendingIntent.FLAG_IMMUTABLE
                    } else 0
                views.setOnClickPendingIntent(
                    R.id.widget_frame,
                    PendingIntent.getActivity(context, 0, launch, flags)
                )

                appWidgetManager.updateAppWidget(appWidgetId, views)
                WidgetScheduleAlarms.schedule(context)
            } catch (t: Throwable) {
                Log.e(TAG, "渲染紧凑版小程序失败 (id: $appWidgetId)", t)
            }
        }
    }
}
