package com.example.project_usst

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 为桌面小组件的右半区 ListView 提供数据的服务（支持课表与待办双模式，支持点击深层跳转）
 */
class TodayScheduleWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodayScheduleRemoteViewsFactory(applicationContext)
    }
}

class TodayScheduleRemoteViewsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private val itemList = ArrayList<ScheduleOrTodoItemData>()

    /** 「距上课」提示的提前量（分钟），由设置页写入，默认 45。 */
    private var upcomingMinutes: Int = 45

    /**
     * 列表里是几天后的课。大于 0 时 `startMin/endMin` 只代表钟点、不代表今天，
     * 不能拿当前时刻去比，否则未来某天的课会被标成「已结课」。
     */
    private var daysAhead: Int = 0

    /** 按「主题」设置取到的颜色；null 时回退系统深浅色。 */
    private var palette: WidgetColors? = null

    data class ScheduleOrTodoItemData(
        val name: String,
        val time: String,
        val room: String,
        val teacher: String,
        val accentColor: String,
        val status: String,
        val statusTag: String,
        val linkUri: String,
        // 课表条目的起止分钟（0 点起算），-1 表示待办或旧数据
        val startMin: Int = -1,
        val endMin: Int = -1
    )

    /** 用「当前时刻 + 起止分钟」现算状态，避免 30 分钟刷新周期导致标签陈旧。 */
    private fun liveStatus(item: ScheduleOrTodoItemData): Pair<String, String> {
        if (item.startMin < 0 || item.endMin < 0) {
            return item.status to item.statusTag
        }
        // 未来某天的课：钟点没有日期含义，直接用快照里的状态
        if (daysAhead > 0) {
            return item.status to item.statusTag
        }
        val cal = Calendar.getInstance()
        val nowMin = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        return when {
            nowMin > item.endMin -> "past" to "已结课"
            nowMin >= item.startMin -> "ongoing" to "进行中 (剩${item.endMin - nowMin}m)"
            item.startMin - nowMin in 1..upcomingMinutes -> "upcoming" to "距上课${item.startMin - nowMin}m"
            else -> "upcoming" to ""
        }
    }

    override fun onCreate() {
        loadData()
    }

    override fun onDataSetChanged() {
        loadData()
    }

    private fun loadData() {
        itemList.clear()
        try {
            val prefs = HomeWidgetPlugin.getData(context)
            val mode = prefs.getString("widget_view_mode", "schedule") ?: "schedule"
            upcomingMinutes = prefs.getInt("widget_upcoming_minutes", 45).coerceIn(0, 120)
            daysAhead = prefs.getInt("schedule_days_ahead", 0).coerceAtLeast(0)
            palette = WidgetThemeHelper.colors(context, WidgetThemeHelper.themeOf(context))
            val jsonKey = if (mode == "todo") "todos_json" else "courses_json"
            val jsonString = prefs.getString(jsonKey, null) ?: return
            val array = JSONArray(jsonString)

            // 今天的课一旦上完就不再出现在列表里（而不是淡化显示「已结课」）
            val nowMin = WidgetData.nowMinuteOfDay()
            val hideFinished = mode != "todo" && daysAhead == 0

            for (i in 0 until array.length()) {
                val obj: JSONObject = array.getJSONObject(i)
                val startMin = obj.optInt("startMin", -1)
                val endMin = obj.optInt("endMin", -1)
                if (hideFinished && startMin >= 0 && endMin in 0 until nowMin) {
                    continue
                }
                itemList.add(
                    ScheduleOrTodoItemData(
                        name = obj.optString("name", "未命名"),
                        time = obj.optString("time", obj.optString("period", "")),
                        room = obj.optString("room", ""),
                        teacher = obj.optString("teacher", ""),
                        accentColor = obj.optString("accentColor", "#1677FF"),
                        status = obj.optString("status", "upcoming"),
                        statusTag = obj.optString("statusTag", ""),
                        linkUri = obj.optString("linkUri", ""),
                        startMin = startMin,
                        endMin = endMin
                    )
                )
            }
        } catch (t: Throwable) {
            Log.e("TodayWidgetFactory", "解析列表数据异常", t)
        }
    }

    override fun onDestroy() {
        itemList.clear()
    }

    override fun getCount(): Int = itemList.size

    override fun getViewAt(position: Int): RemoteViews? {
        if (position < 0 || position >= itemList.size) {
            return null
        }

        try {
            val item = itemList[position]
            val colors = palette
                ?: WidgetThemeHelper.colors(context, WidgetTheme.SYSTEM)
            // 状态按渲染时刻现算（课表条目带 startMin/endMin），待办沿用推演时给的状态
            val (statusValue, statusTagText) = liveStatus(item)
            val views = RemoteViews(context.packageName, R.layout.widget_course_item)

            // 1. 设置主标题与时间/截止
            views.setTextViewText(R.id.item_course_name, item.name)
            views.setTextViewText(R.id.item_course_time, item.time)
            views.setTextViewText(R.id.item_course_room, item.room)
            views.setTextViewText(R.id.item_course_teacher, item.teacher)

            // 2. 动态设置左侧色条（课表莫兰迪色 / 待办紧急度色）
            try {
                val color = Color.parseColor(item.accentColor)
                views.setInt(R.id.item_accent_bar, "setColorFilter", color)
            } catch (_: Throwable) {
                views.setInt(R.id.item_accent_bar, "setColorFilter", Color.parseColor("#1677FF"))
            }

            // 3. 根据状态设置强调、临期或淡化
            when (statusValue) {
                "past" -> {
                    // 已结束
                    views.setTextColor(R.id.item_course_name, colors.statusPast)
                    views.setTextColor(R.id.item_course_room, colors.textFaint)
                    views.setTextColor(R.id.item_course_time, colors.textFaint)
                }
                "urgent" -> {
                    // 待办紧急临期（24小时内）
                    views.setTextColor(R.id.item_course_name, colors.textPrimary)
                    views.setTextColor(R.id.item_course_room, colors.textSecondary)
                    views.setTextColor(R.id.item_course_time, colors.statusUrgent)
                }
                "near" -> {
                    // 待办临近（3天内）
                    views.setTextColor(R.id.item_course_name, colors.textPrimary)
                    views.setTextColor(R.id.item_course_room, colors.textSecondary)
                    views.setTextColor(R.id.item_course_time, colors.statusNear)
                }
                else -> {
                    views.setTextColor(R.id.item_course_name, colors.textPrimary)
                    views.setTextColor(R.id.item_course_room, colors.textSecondary)
                    views.setTextColor(R.id.item_course_time, colors.textMuted)
                }
            }

            // 4. 状态角标（如 "进行中 (剩20m)" / "明日" / "临期" / "待办"）
            if (statusTagText.isNotEmpty()) {
                views.setViewVisibility(R.id.item_course_status, View.VISIBLE)
                views.setTextViewText(R.id.item_course_status, statusTagText)
                when (statusValue) {
                    "urgent" -> views.setTextColor(R.id.item_course_status, colors.statusUrgent)
                    "ongoing" -> views.setTextColor(R.id.item_course_status, colors.statusOngoing)
                    "past" -> views.setTextColor(R.id.item_course_status, colors.statusPast)
                    else -> views.setTextColor(R.id.item_course_status, colors.statusNear)
                }
            } else {
                views.setViewVisibility(R.id.item_course_status, View.GONE)
            }

            // 5. 点击列表项时的触发动作（将对应深层跳转 URI 填入 pendingIntentTemplate）
            val fillInIntent = Intent().apply {
                if (item.linkUri.isNotEmpty()) {
                    data = Uri.parse(item.linkUri)
                }
            }
            views.setOnClickFillInIntent(R.id.item_root, fillInIntent)

            return views
        } catch (t: Throwable) {
            Log.e("TodayWidgetFactory", "getViewAt 渲染异常", t)
            return null
        }
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
