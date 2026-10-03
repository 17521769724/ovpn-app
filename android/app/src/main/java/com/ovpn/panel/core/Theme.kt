package com.ovpn.panel.core

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 三端统一设计令牌（与 iOS Theme.swift / Web 端 globals.css 一一对应，改动需三端同步）
 * Web 端基准：--radius: 0.625rem (=10px)，Tailwind 语义色。
 */
object DS {

    object Radius {
        val sm: Dp = 6.dp      // 0.6 × 10
        val md: Dp = 8.dp      // 0.8 × 10
        val lg: Dp = 10.dp     // 基准
        val xl: Dp = 14.dp     // 1.4 × 10
        val xxl: Dp = 18.dp    // 1.8 × 10
    }

    /** 控件尺寸（三端硬性对齐） */
    object Size {
        val buttonHeight: Dp = 42.dp        // 主操作按钮高度
        val buttonHeightLarge: Dp = 46.dp   // 连接等强调按钮
        val buttonHeightSmall: Dp = 30.dp   // 次级/小按钮
        val inputHeight: Dp = 42.dp         // 输入框高度
        val cardPadding: Dp = 16.dp
        val pagePadding: Dp = 16.dp
        val gap: Dp = 12.dp
        val gapLarge: Dp = 16.dp
        val tabBarHeight: Dp = 54.dp
    }

    /** 字号 */
    object Font {
        val title = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
        val section = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        val body = TextStyle(fontSize = 15.sp)
        val bodySmall = TextStyle(fontSize = 13.sp)
        val caption = TextStyle(fontSize = 12.sp)
        val value = TextStyle(fontSize = 13.sp)
        val number = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }

    /** 品牌色（绿色为主，配青绿 / 黄绿 / 冷青 / 琥珀等协调辅助色） */
    object Brand {
        val primary = Color(0xFF059669)      // 主色（深一档，保证白字对比度）
        val primaryDeep = Color(0xFF047857)
        val green = Color(0xFF10B981)        // 主绿（emerald-500）
        val mint = Color(0xFF34D399)         // 亮绿（emerald-400）
        val teal = Color(0xFF14B8A6)         // 青绿（邻近色）
        val tealDeep = Color(0xFF0F766E)
        val lime = Color(0xFF84CC16)         // 黄绿（邻近色）
        val cyan = Color(0xFF06B6D4)         // 冷青（邻近色）
        val amber = Color(0xFFF59E0B)        // 琥珀（互补强调）
        val red = Color(0xFFE5484D)          // 危险（断开 / 退出）
        val redDeep = Color(0xFFC02830)
    }

    /** 颜色（亮色） */
    object Light {
        val background = Color(0xFFF6F8F7)
        val foreground = Color(0xFF0C1512)
        val card = Color(0xFFFFFFFF)
        val cardForeground = Color(0xFF0C1512)
        val primary = Color(0xFF059669)
        val primaryForeground = Color(0xFFFFFFFF)
        val secondary = Color(0xFFE6F7F0)
        val secondaryForeground = Color(0xFF046B56)
        val muted = Color(0xFFEEF2F0)
        val mutedForeground = Color(0xFF7C8A85)
        val border = Color(0xFFE2E9E6)
        val destructive = Color(0xFFE5484D)
    }

    /** 颜色（暗色） */
    object Dark {
        val background = Color(0xFF0A0F0D)
        val foreground = Color(0xFFF5FAF8)
        val card = Color(0xFF141A18)
        val cardForeground = Color(0xFFF5FAF8)
        val primary = Color(0xFF34D399)
        val primaryForeground = Color(0xFF04231B)
        val secondary = Color(0xFF16302A)
        val secondaryForeground = Color(0xFFA7F3D0)
        val muted = Color(0xFF212926)
        val mutedForeground = Color(0xFF9BAAA5)
        val border = Color(0x1AFFFFFF)      // Color.white.opacity(0.10)
        val destructive = Color(0xFFFF6B70)
    }

    /** 状态色（Tailwind 色板，与 Web 端一致） */
    object Status {
        val onlineBg = Color(0xFF10B981).copy(alpha = 0.15f)
        val onlineText = Color(0xFF059669)
        val offlineBg = Color(0xFFEF4444).copy(alpha = 0.15f)
        val offlineText = Color(0xFFDC2626)
        val pendingBg = Color(0xFFE5E5E5)
        val pendingText = Color(0xFF737373)
        val warningBg = Color(0xFFF59E0B).copy(alpha = 0.14f)
        val warningText = Color(0xFFB45309)
        val infoText = Color(0xFF2563EB)
    }

    /** 流量绿（对应 Web 端 emerald 色板，流量统计统一纯绿色） */
    object Traffic {
        val bar = Color(0xFF10B981)        // emerald-500
        val barStrong = Color(0xFF059669)  // emerald-600
        val barSoft = Color(0xFF6EE7B7)    // emerald-300
        val tracker = Color(0xFFD1FAE5)    // emerald-100
    }

    /** 功能图标配色（绿色系为主 + 少量协调强调色） */
    object IconColor {
        val green = Color(0xFF10B981)      // 主绿
        val mint = Color(0xFF34D399)       // 亮绿
        val teal = Color(0xFF14B8A6)       // 青绿（邻近）
        val tealDeep = Color(0xFF0F766E)
        val lime = Color(0xFF84CC16)       // 黄绿（邻近）
        val cyan = Color(0xFF06B6D4)       // 冷青（邻近）
        val amber = Color(0xFFF59E0B)      // 琥珀（互补强调）
        val orange = Color(0xFFFB923C)     // 橙（金币）
        val rose = Color(0xFFF43F5E)       // 玫红（警示类入口）
        val slate = Color(0xFF64748B)      // 中性
    }
}

/** 提示横幅类型 */
enum class BannerKind { Success, Error, Warning, Info }

/** 提示横幅配色（对齐 Web 端 sonner richColors） */
data class ToastStyle(
    val background: Color,
    val border: Color,
    val foreground: Color,
) {
    companion object {
        fun of(kind: BannerKind, dark: Boolean): ToastStyle = when (kind) {
            BannerKind.Success -> if (!dark) {
                ToastStyle(Color(0xFFECFDF5), Color(0xFFA7F3D0), Color(0xFF047857))
            } else {
                ToastStyle(Color(0xFF001A0F), Color(0xFF065F46), Color(0xFF4ADE80))
            }
            BannerKind.Error -> if (!dark) {
                ToastStyle(Color(0xFFFEF2F2), Color(0xFFFECACA), Color(0xFFE7000B))
            } else {
                ToastStyle(Color(0xFF2D0607), Color(0xFF7F1D1D), Color(0xFFFF9B9D))
            }
            BannerKind.Warning -> if (!dark) {
                ToastStyle(Color(0xFFFEFCE8), Color(0xFFFEF08A), Color(0xFFB45309))
            } else {
                ToastStyle(Color(0xFF1C1A00), Color(0xFF854D0E), Color(0xFFFCD34D))
            }
            BannerKind.Info -> if (!dark) {
                ToastStyle(Color(0xFFF0F9FF), Color(0xFFBAE6FD), Color(0xFF0369A1))
            } else {
                ToastStyle(Color(0xFF001B33), Color(0xFF1E40AF), Color(0xFF60A5FA))
            }
        }
    }
}

/** 语义色（跟随系统明暗） */
data class Palette(val dark: Boolean) {

    val background: Color get() = if (dark) DS.Dark.background else DS.Light.background
    val foreground: Color get() = if (dark) DS.Dark.foreground else DS.Light.foreground
    val card: Color get() = if (dark) DS.Dark.card else DS.Light.card
    val cardForeground: Color get() = if (dark) DS.Dark.cardForeground else DS.Light.cardForeground
    val primary: Color get() = if (dark) DS.Dark.primary else DS.Light.primary
    val primaryForeground: Color get() = if (dark) DS.Dark.primaryForeground else DS.Light.primaryForeground
    val secondary: Color get() = if (dark) DS.Dark.secondary else DS.Light.secondary
    val secondaryForeground: Color get() = if (dark) DS.Dark.secondaryForeground else DS.Light.secondaryForeground
    val muted: Color get() = if (dark) DS.Dark.muted else DS.Light.muted
    val mutedForeground: Color get() = if (dark) DS.Dark.mutedForeground else DS.Light.mutedForeground
    val border: Color get() = if (dark) DS.Dark.border else DS.Light.border
    val destructive: Color get() = if (dark) DS.Dark.destructive else DS.Light.destructive

    val onlineBg: Color get() = DS.Status.onlineBg
    val onlineText: Color get() = if (dark) Color(0xFF34D399) else DS.Status.onlineText
    val offlineBg: Color get() = DS.Status.offlineBg
    val offlineText: Color get() = if (dark) Color(0xFFF87171) else DS.Status.offlineText
    val pendingBg: Color get() = if (dark) DS.Dark.muted else DS.Status.pendingBg
    val pendingText: Color get() = if (dark) DS.Dark.mutedForeground else DS.Status.pendingText
    val warningBg: Color get() = DS.Status.warningBg
    val warningText: Color get() = if (dark) Color(0xFFFBBF24) else DS.Status.warningText

    /** 次级文字：比 mutedForeground 更深，保证手机上的可读性 */
    val secondaryText: Color get() = if (dark) Color(0xFFC9CCD2) else Color(0xFF5A6068)

    /** 流量统计统一纯绿色 */
    val trafficBar: Color get() = DS.Traffic.bar
    val trafficTracker: Color get() = if (dark) Color(0xFF064E3B) else DS.Traffic.tracker

    /** 品牌渐变（按钮）：右上 → 左下，对齐 SwiftUI .topLeading → .bottomTrailing */
    val accentGradient: Brush get() = if (dark) {
        Brush.linearGradient(listOf(Color(0xFF10B981), Color(0xFF047857)))
    } else {
        Brush.linearGradient(listOf(DS.Brand.primary, DS.Brand.primaryDeep))
    }

    val tealGradient: Brush get() = if (dark) {
        Brush.linearGradient(listOf(Color(0xFF2DD4BF), Color(0xFF0F766E)))
    } else {
        Brush.linearGradient(listOf(DS.Brand.teal, DS.Brand.tealDeep))
    }

    val dangerGradient: Brush get() = if (dark) {
        Brush.linearGradient(listOf(Color(0xFFFF7C80), Color(0xFFE5484D)))
    } else {
        Brush.linearGradient(listOf(DS.Brand.red, DS.Brand.redDeep))
    }

    /** 连接圆环使用的渐变（绿 → 青绿 → 冷青 → 黄绿），对应 SwiftUI AngularGradient */
    val connectionGradientColors: List<Color> get() = listOf(
        DS.Traffic.bar, Color(0xFF22D3EE), DS.Brand.teal, DS.Brand.lime, Color(0xFF6EE7B7), DS.Traffic.bar
    )

    fun toastStyle(kind: BannerKind): ToastStyle = ToastStyle.of(kind, dark)
}

val LocalPalette = staticCompositionLocalOf { Palette(false) }

/** 全局主题：跟随系统明暗，提供调色板与 Material 颜色 */
@Composable
fun PanelTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val palette = Palette(dark)
    val scheme = if (dark) {
        darkColorScheme(
            primary = DS.Dark.primary,
            background = DS.Dark.background,
            surface = DS.Dark.card,
            onSurface = DS.Dark.foreground,
            onBackground = DS.Dark.foreground,
            outline = DS.Dark.border,
            error = DS.Dark.destructive,
        )
    } else {
        lightColorScheme(
            primary = DS.Light.primary,
            background = DS.Light.background,
            surface = DS.Light.card,
            onSurface = DS.Light.foreground,
            onBackground = DS.Light.foreground,
            outline = DS.Light.border,
            error = DS.Light.destructive,
        )
    }
    CompositionLocalProvider(LocalPalette provides palette) {
        MaterialTheme(
            colorScheme = scheme,
            typography = Typography(
                bodyLarge = DS.Font.body,
                bodyMedium = DS.Font.bodySmall,
                labelSmall = DS.Font.caption,
            ),
            content = content,
        )
    }
}

/** 文本辅助：等宽数字（对齐 SwiftUI .monospacedDigit()） */
val MonospaceDigits = TextStyle(
    fontFeatureSettings = "tnum",
    textAlign = TextAlign.Start,
)