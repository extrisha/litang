package com.example.project_usst

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import java.util.Calendar

/**
 * 让小组件在「上课 / 下课」的那一分钟自己刷新一次。
 *
 * 背景：`updatePeriodMillis` 最小 30 分钟且会被 Doze 推迟，光靠它的话
 * 「距上课 5m」可能在打完铃十分钟后还挂着。这里在每次更新时间算下一个节次
 * 边界，用 AlarmManager 定一个一分钟窗口的闹钟（不申请精确闹钟权限），
 * 到点广播 ACTION_REFRESH_SCHEDULE 触发一次重绘，并在重绘里继续排下一次。
 *
 * 一天最多 26 次（13 节 × 起止），加上午夜一次跨天，对电量可以忽略。
 */
object WidgetScheduleAlarms {
    private const val TAG = "WidgetScheduleAlarms"
    private const val REQUEST_CODE = 4102

    /** 零点后几分钟补一次跨天推演，避免「今日课表」在新的一天还挂着。 */
    private const val MIDNIGHT_OFFSET_MIN = 5

    fun schedule(context: Context) {
        try {
            val prefs = HomeWidgetPlugin.getData(context)
            val raw = prefs.getString("semester_period_times_json", "") ?: ""
            val boundaries = periodBoundaries(raw)
            if (boundaries.isEmpty()) return

            val now = Calendar.getInstance()
            val nowMs = now.timeInMillis
            val midnight = Calendar.getInstance().apply {
                timeInMillis = nowMs
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, MIDNIGHT_OFFSET_MIN)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis

            var next = midnight
            for (minute in boundaries) {
                val at = Calendar.getInstance().apply {
                    timeInMillis = nowMs
                    set(Calendar.HOUR_OF_DAY, minute / 60)
                    set(Calendar.MINUTE, minute % 60)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }.timeInMillis
                if (at > nowMs && at < next) {
                    next = at
                }
            }

            val manager = context.getSystemService(AlarmManager::class.java) ?: return
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            val pending = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                Intent(context, TodayScheduleWidgetProvider::class.java).apply {
                    action = TodayScheduleWidgetProvider.ACTION_REFRESH_SCHEDULE
                },
                flags
            )
            // 一分钟窗口：不申请 SCHEDULE_EXACT_ALARM，系统最多挪后一分钟
            manager.setWindow(AlarmManager.RTC_WAKEUP, next, 60_000L, pending)
        } catch (t: Throwable) {
            Log.w(TAG, "排下次到点刷新失败", t)
        }
    }

    /** 13 节的起止分钟（去重、升序）。 */
    private fun periodBoundaries(raw: String): List<Int> {
        if (raw.isEmpty()) return emptyList()
        val out = sortedSetOf<Int>()
        try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val parts = array.getString(i).split("-")
                if (parts.size != 2) continue
                for (part in parts) {
                    val hm = part.split(":")
                    if (hm.size != 2) continue
                    val hour = hm[0].toIntOrNull() ?: continue
                    val minute = hm[1].toIntOrNull() ?: continue
                    out.add(hour * 60 + minute)
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "读取作息失败，跳过到点刷新", t)
            return emptyList()
        }
        return out.toList()
    }
}
