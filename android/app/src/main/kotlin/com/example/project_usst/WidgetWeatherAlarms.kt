package com.example.project_usst

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver

/**
 * 让小组件在后台也能定期换气：每 [INTERVAL_MS] 发给 HomeWidgetBackgroundReceiver
 * 一次 `litang://refresh` 广播，插件的后台 worker 会拉起 Flutter 的
 * `backgroundWidgetCallback` → `WidgetSyncService.syncTodayWidget(forceWeather: true)`。
 *
 * 为什么不用 WorkManager：那需要新加 `androidx.work` 依赖，而这里只是一个
 * 「定时发广播」的需求，AlarmManager 的 inexact repeating 足够，而且不引入
 * 新的构建依赖。Doze 下会顺延到设备醒来，天气晚几十分钟不影响使用。
 */
object WidgetWeatherAlarms {
    private const val TAG = "WidgetWeatherAlarms"
    private const val REQUEST_CODE = 4104

    /** 两小时一次：既不会停在几小时前，也不至于频繁唤醒。 */
    private const val INTERVAL_MS = 2 * 60 * 60 * 1000L

    fun schedule(context: Context) {
        try {
            val manager = context.getSystemService(AlarmManager::class.java) ?: return
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else 0
            manager.setInexactRepeating(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + INTERVAL_MS,
                INTERVAL_MS,
                pending(context, flags)
            )
        } catch (t: Throwable) {
            Log.w(TAG, "排天气周期刷新失败", t)
        }
    }

    /** 桌面上一块小组件都不剩时，停掉周期闹钟。 */
    fun cancelIfOrphaned(context: Context) {
        try {
            val manager = android.appwidget.AppWidgetManager.getInstance(context)
            val fourByTwo = manager.getAppWidgetIds(
                ComponentName(context, TodayScheduleWidgetProvider::class.java)
            ).size
            val fourByOne = manager.getAppWidgetIds(
                ComponentName(context, TodayCompactWidgetProvider::class.java)
            ).size
            if (fourByTwo == 0 && fourByOne == 0) {
                cancel(context)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "检查小组件残留失败", t)
        }
    }

    fun cancel(context: Context) {
        try {
            val manager = context.getSystemService(AlarmManager::class.java) ?: return
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else 0
            manager.cancel(pending(context, flags))
        } catch (t: Throwable) {
            Log.w(TAG, "取消天气周期刷新失败", t)
        }
    }

    private fun pending(context: Context, flags: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
                action = "es.antonborri.home_widget.action.BACKGROUND"
                data = Uri.parse("litang://refresh")
            },
            flags
        )
}
