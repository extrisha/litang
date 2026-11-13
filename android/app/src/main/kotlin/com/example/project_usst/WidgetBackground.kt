package com.example.project_usst

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader

/**
 * 小组件背景：按「风格 + 透明度 + 深浅色」现画一张 Bitmap，再由 RemoteViews 放到
 * 背景 ImageView 上。
 *
 * 为什么不用 drawable：`setBackgroundColor` 会丢掉圆角，`setBackgroundResource`
 * 只能整档切换、没法跟用户的透明度滑杆。用 Bitmap 画一次，三个维度都能组合。
 *
 * 为什么不做真模糊：AppWidget 不是窗口，拿不到宿主桌面壁纸，也没有 RenderEffect
 * 的合成能力。这里只能用「半透明 + 上下渐变 + 细亮边」近似磨砂玻璃的观感。
 */
object WidgetBackground {
    const val STYLE_GLASS = "glass"
    const val STYLE_CLEAR = "clear"
    const val STYLE_SOLID = "solid"

    /** 位图缩放：1dp = 2px，够清晰又不至于让 Binder 超限。 */
    private const val PX_PER_DP = 2f

    /** 大 R 角；4×1 太矮时会被压到「半高」，避免变成药丸。 */
    private const val CORNER_RADIUS_DP = 24f
    private const val STROKE_DP = 1f

    fun isNight(context: Context): Boolean {
        val mode = context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK
        return mode == Configuration.UI_MODE_NIGHT_YES
    }

    /**
     * @param style [STYLE_GLASS] / [STYLE_CLEAR] / [STYLE_SOLID]
     * @param alphaPercent 0~100；玻璃风格的有效不透明度，实心风格忽略
     */
    fun build(
        context: Context,
        style: String,
        alphaPercent: Int,
        night: Boolean = isNight(context),
        widthDp: Float = 250f,
        heightDp: Float = 110f
    ): Bitmap {
        // 按控件真实宽高比生成：固定 480×240 时，4×1（250×60）被 fitXY 横向
        // 拉伸，圆角会变成扁椭圆，看起来像「小圆角」。
        val bitmapWidth = (widthDp * PX_PER_DP).toInt().coerceAtLeast(4)
        val bitmapHeight = (heightDp * PX_PER_DP).toInt().coerceAtLeast(4)
        val bitmap = Bitmap.createBitmap(
            bitmapWidth,
            bitmapHeight,
            Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)
        // 圆角最多到半高，4×1 不会变成药丸
        val radius = minOf(CORNER_RADIUS_DP * PX_PER_DP, bitmapHeight / 2f)
        val stroke = STROKE_DP * PX_PER_DP
        val rect = RectF(stroke, stroke, bitmapWidth - stroke, bitmapHeight - stroke)

        val base = if (night) Color.rgb(28, 28, 30) else Color.WHITE
        val alpha = alphaPercent.coerceIn(0, 100) * 255 / 100

        when (style) {
            STYLE_SOLID -> {
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = withAlpha(base, 255)
                }
                canvas.drawRoundRect(rect, radius, radius, paint)
            }

            STYLE_CLEAR -> {
                // 纯透明：只留一圈细边，文字靠阴影撑可读性
                val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = withAlpha(base, 12)
                }
                canvas.drawRoundRect(rect, radius, radius, fill)
            }

            else -> {
                // 磨砂玻璃：自上而下「亮 → 略暗」，模拟顶部受光
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    shader = LinearGradient(
                        0f,
                        0f,
                        0f,
                        bitmapHeight.toFloat(),
                        withAlpha(base, alpha),
                        withAlpha(base, (alpha * 0.82f).toInt()),
                        Shader.TileMode.CLAMP
                    )
                }
                canvas.drawRoundRect(rect, radius, radius, paint)
            }
        }

        // 一圈细亮边：玻璃质感的关键，纯透明风格也保留
        val borderAlpha = when (style) {
            STYLE_SOLID -> 40
            STYLE_CLEAR -> 90
            else -> 110
        }
        val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.STROKE
            strokeWidth = stroke
            color = withAlpha(Color.WHITE, borderAlpha)
        }
        canvas.drawRoundRect(rect, radius, radius, strokePaint)

        return bitmap
    }

    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(
            alpha.coerceIn(0, 255),
            Color.red(color),
            Color.green(color),
            Color.blue(color)
        )
}
