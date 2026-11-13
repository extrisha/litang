package com.example.project_usst

import android.content.Context
import android.content.res.Configuration

/**
 * 小组件的主题：跟随系统 / 强制浅色 / 强制深色。
 *
 * `values-night` 资源只在系统切深色时生效，用户手动选「深色」时系统可能还是浅色，
 * 这时布局里的 `@color/widget_*` 会拿到浅色值（深字 + 深底 = 看不见）。
 * 所以这里按主题造一个「配置被改过的 Context」，从同一套资源里取到对应颜色，
 * 再在 Provider / RemoteViewsService 里逐个 setTextColor。
 */
enum class WidgetTheme(val key: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark");

    companion object {
        fun from(raw: String?): WidgetTheme = when (raw) {
            LIGHT.key -> LIGHT
            DARK.key -> DARK
            else -> SYSTEM
        }
    }
}

/** 一次取齐小组件用到的颜色，避免每个 TextView 都去查资源。 */
data class WidgetColors(
    val textPrimary: Int,
    val textSecondary: Int,
    val textMuted: Int,
    val textFaint: Int,
    val accentRed: Int,
    val statusOngoing: Int,
    val statusPast: Int,
    val statusUrgent: Int,
    val statusNear: Int
)

object WidgetThemeHelper {
    private const val PREF_KEY = "widget_theme"

    fun themeOf(context: Context): WidgetTheme =
        WidgetTheme.from(
            es.antonborri.home_widget.HomeWidgetPlugin.getData(context)
                .getString(PREF_KEY, WidgetTheme.SYSTEM.key)
        )

    fun isNight(context: Context, theme: WidgetTheme): Boolean = when (theme) {
        WidgetTheme.DARK -> true
        WidgetTheme.LIGHT -> false
        WidgetTheme.SYSTEM ->
            (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    }

    fun colors(context: Context, theme: WidgetTheme): WidgetColors {
        val themed = themedContext(context, isNight(context, theme))
        return WidgetColors(
            textPrimary = themed.getColor(R.color.widget_text_primary),
            textSecondary = themed.getColor(R.color.widget_text_secondary),
            textMuted = themed.getColor(R.color.widget_text_muted),
            textFaint = themed.getColor(R.color.widget_text_faint),
            accentRed = themed.getColor(R.color.widget_accent_red),
            statusOngoing = themed.getColor(R.color.widget_status_ongoing),
            statusPast = themed.getColor(R.color.widget_status_past),
            statusUrgent = themed.getColor(R.color.widget_status_urgent),
            statusNear = themed.getColor(R.color.widget_status_near)
        )
    }

    private fun themedContext(context: Context, night: Boolean): Context {
        val config = Configuration(context.resources.configuration)
        val mask = Configuration.UI_MODE_NIGHT_MASK
        config.uiMode = (config.uiMode and mask.inv()) or
            if (night) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        return context.createConfigurationContext(config)
    }
}
