package com.ovpn.panel.core

import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Date
import java.util.Locale

/** 展示辅助（对应 iOS enum Format） */
object Format {

    /** 字节数 → 可读文本（B/KB/MB/GB/TB/PB） */
    fun bytes(value: Long): String {
        if (value <= 0) return "0 B"
        val units = arrayOf("B", "KB", "MB", "GB", "TB", "PB")
        var size = value.toDouble()
        var index = 0
        while (size >= 1024 && index < units.size - 1) {
            size /= 1024
            index += 1
        }
        val digits = if (size >= 100 || index == 0) 0 else if (size >= 10) 1 else 2
        return String.format(Locale.US, "%.${digits}f", size) + " " + units[index]
    }

    /** 金额（分 → 带符号的两位小数） */
    fun money(cents: Int, symbol: String = "¥"): String =
        String.format(Locale.US, "%s%.2f", symbol, cents.toDouble() / 100.0)

    /** 限速（Kbps → 可读文本） */
    fun speed(kbps: Int): String {
        if (kbps <= 0) return "不限速"
        if (kbps >= 1024) return String.format(Locale.US, "%.1f Mbps", kbps.toDouble() / 1024.0)
        return "$kbps Kbps"
    }

    /** 实时速率（字节/秒 → 可读文本，用于连接页网速显示） */
    fun speedValue(bytesPerSecond: Double): String {
        if (bytesPerSecond <= 1) return "0 KB/s"
        val units = arrayOf("B/s", "KB/s", "MB/s", "GB/s")
        var value = bytesPerSecond
        var index = 0
        while (value >= 1024 && index < units.size - 1) {
            value /= 1024
            index += 1
        }
        val digits = if (value >= 100) 0 else if (value >= 10) 1 else 2
        return String.format(Locale.US, "%.${digits}f", value) + " " + units[index]
    }

    /** 流量（0 或负数表示不限量） */
    fun traffic(value: Long): String = if (value <= 0) "不限量" else bytes(value)

    /** ISO8601 → 简短本地时间 */
    fun dateTime(iso: String?): String {
        val date = parse(iso) ?: return iso?.takeIf { it.isNotEmpty() } ?: "-"
        val out = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.CHINA)
        return out.format(Date.from(date))
    }

    /** ISO8601 → 仅日期 */
    fun dateOnly(iso: String?): String {
        val date = parse(iso) ?: return iso?.takeIf { it.isNotEmpty() } ?: "-"
        val out = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA)
        return out.format(Date.from(date))
    }

    /**
     * ISO8601 字符串 → Instant（兼容带/不带毫秒）
     * 对应 iOS ISO8601DateFormatter 的 withFractionalSeconds 首次尝试、
     * 失败后去掉毫秒再解析的行为。
     */
    fun parse(iso: String?): Instant? {
        if (iso.isNullOrEmpty()) return null
        return try {
            // 带毫秒（或其它小数秒）与时区偏移
            OffsetDateTime.parse(iso, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant()
        } catch (e: Exception) {
            try {
                // 形如 ...Z 的 UTC 时间
                Instant.parse(iso)
            } catch (e2: Exception) {
                try {
                    // 无时区信息的本地时间，按系统时区解释
                    LocalDateTime.parse(iso, DateTimeFormatter.ISO_LOCAL_DATE_TIME)
                        .atZone(ZoneId.systemDefault()).toInstant()
                } catch (e3: Exception) {
                    null
                }
            }
        }
    }

    /** 秒数 → mm:ss（用于订单支付倒计时） */
    fun countdown(seconds: Int): String {
        val value = maxOf(0, seconds)
        return String.format(Locale.US, "%02d:%02d", value / 60, value % 60)
    }
}