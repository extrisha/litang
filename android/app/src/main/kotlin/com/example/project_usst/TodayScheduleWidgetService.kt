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

    data class ScheduleOrTodoItemData(
        val name: String,
        val time: String,
        val room: String,
        val teacher: String,
        val accentColor: String,
        val status: String,
        val statusTag: String,
        val linkUri: String
    )

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
            val jsonKey = if (mode == "todo") "todos_json" else "courses_json"
            val jsonString = prefs.getString(jsonKey, null) ?: return
            val array = JSONArray(jsonString)

            for (i in 0 until array.length()) {
                val obj: JSONObject = array.getJSONObject(i)
                itemList.add(
                    ScheduleOrTodoItemData(
                        name = obj.optString("name", "未命名"),
                        time = obj.optString("time", obj.optString("period", "")),
                        room = obj.optString("room", ""),
                        teacher = obj.optString("teacher", ""),
                        accentColor = obj.optString("accentColor", "#1677FF"),
                        status = obj.optString("status", "upcoming"),
                        statusTag = obj.optString("statusTag", ""),
                        linkUri = obj.optString("linkUri", "")
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
            val views = RemoteViews(context.packageName, R.layout.widget_course_item)

            // 1. 设置主标题与时间/截止
            views.setTextViewText(R.id.item_course_name, item.name)
            views.setTextViewText(R.id.item_course_time, item.time)
            views.setTextViewText(R.id.item_course_room, item.room)
            views.setTextViewText(R.id.item_course_teacher, item.teacher)

            // 2. 动态设置左侧色条（课表莫兰迪色 / 待办紧急度色）
            try {
                val color = Color.parseColor(item.accentColor)
                views.setInt(R.id.item_accent_bar, "setBackgroundColor", color)
            } catch (_: Throwable) {
                views.setInt(R.id.item_accent_bar, "setBackgroundColor", Color.parseColor("#1677FF"))
            }

            // 3. 根据状态设置强调、临期或淡化
            when (item.status) {
                "past" -> {
                    // 已结束
                    views.setTextColor(R.id.item_course_name, Color.parseColor("#A0AEC0"))
                    views.setTextColor(R.id.item_course_room, Color.parseColor("#CBD5E0"))
                    views.setTextColor(R.id.item_course_time, Color.parseColor("#CBD5E0"))
                }
                "urgent" -> {
                    // 待办紧急临期（24小时内）
                    views.setTextColor(R.id.item_course_name, Color.parseColor("#1A202C"))
                    views.setTextColor(R.id.item_course_room, Color.parseColor("#4A5568"))
                    views.setTextColor(R.id.item_course_time, Color.parseColor("#CF1322"))
                }
                "near" -> {
                    // 待办临近（3天内）
                    views.setTextColor(R.id.item_course_name, Color.parseColor("#1A202C"))
                    views.setTextColor(R.id.item_course_room, Color.parseColor("#4A5568"))
                    views.setTextColor(R.id.item_course_time, Color.parseColor("#D97706"))
                }
                else -> {
                    views.setTextColor(R.id.item_course_name, Color.parseColor("#1A202C"))
                    views.setTextColor(R.id.item_course_room, Color.parseColor("#4A5568"))
                    views.setTextColor(R.id.item_course_time, Color.parseColor("#718096"))
                }
            }

            // 4. 状态角标（如 "进行中 (剩20m)" / "明日" / "临期" / "待办"）
            if (item.statusTag.isNotEmpty()) {
                views.setViewVisibility(R.id.item_course_status, View.VISIBLE)
                views.setTextViewText(R.id.item_course_status, item.statusTag)
                when (item.status) {
                    "urgent" -> views.setTextColor(R.id.item_course_status, Color.parseColor("#CF1322"))
                    "ongoing" -> views.setTextColor(R.id.item_course_status, Color.parseColor("#2B6CB0"))
                    "past" -> views.setTextColor(R.id.item_course_status, Color.parseColor("#A0AEC0"))
                    else -> views.setTextColor(R.id.item_course_status, Color.parseColor("#D97706"))
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
