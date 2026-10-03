package com.ovpn.panel

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * 轻量震动反馈（对应 Swift 侧 `Haptics` 的 UIImpactFeedbackGenerator / UINotificationFeedbackGenerator）。
 *
 * Android 没有等价的 haptic API 名称，用系统 Vibrator 的预置波形做等价替代：
 * - light：轻触（下拉刷新、断开）
 * - success：成功（连接成功）
 * - error：失败（连接失败）
 */
object HapticsBridge {

    private fun vibrator(): Vibrator? {
        val context = AppEnv.appContext
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun perform(effect: VibrationEffect) {
        val vib = vibrator() ?: return
        if (!vib.hasVibrator()) return
        runCatching { vib.vibrate(effect) }
    }

    fun light() {
        perform(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
    }

    fun success() {
        perform(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
    }

    fun error() {
        perform(VibrationEffect.createPredefined(VibrationEffect.EFFECT_DOUBLE_CLICK))
    }
}