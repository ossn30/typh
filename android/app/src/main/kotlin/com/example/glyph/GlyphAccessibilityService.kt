package com.example.glyph

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class GlyphAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "TYPH_Accessibility"
        var instance: GlyphAccessibilityService? = null
            private set

        val isRunning: Boolean
            get() = instance != null
    }

    private val handler = Handler(Looper.getMainLooper())
    private var tapCount = 0
    private var isKeyDown = false
    private var keyDownTime = 0L

    private val multiTapRunnable = Runnable {
        val count = tapCount
        tapCount = 0
        when (count) {
            1 -> handleTrigger("single_press")
            2 -> handleTrigger("double_press")
            else -> if (count >= 3) handleTrigger("triple_press")
        }
    }

    private val longPressRunnable = Runnable {
        if (isKeyDown) {
            tapCount = 0
            handler.removeCallbacks(multiTapRunnable)
            handleTrigger("long_press")
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "GlyphAccessibilityService connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        val prefs = getSharedPreferences("glyph_native_settings", Context.MODE_PRIVATE)
        val remapEnabled = prefs.getBoolean("essential_key_remap_enabled", false)
        val targetKeyCode = prefs.getInt("essential_key_code", -1)

        if (!remapEnabled || targetKeyCode <= 0 || event.keyCode != targetKeyCode) {
            return super.onKeyEvent(event)
        }

        val gapMs = prefs.getInt("essential_timing_multi_press_gap_ms", 350).toLong()
        val holdMs = prefs.getInt("essential_timing_long_press_hold_ms", 500).toLong()

        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            isKeyDown = true
            keyDownTime = System.currentTimeMillis()
            handler.removeCallbacks(multiTapRunnable)
            handler.postDelayed(longPressRunnable, holdMs)
            return true
        } else if (event.action == KeyEvent.ACTION_UP) {
            isKeyDown = false
            handler.removeCallbacks(longPressRunnable)
            val duration = System.currentTimeMillis() - keyDownTime
            if (duration < holdMs) {
                tapCount++
                handler.removeCallbacks(multiTapRunnable)
                handler.postDelayed(multiTapRunnable, gapMs)
            }
            return true
        }

        return true
    }

    private fun handleTrigger(trigger: String) {
        val prefs = getSharedPreferences("glyph_native_settings", Context.MODE_PRIVATE)
        val action = when (trigger) {
            "single_press" -> prefs.getString("essential_action_single_press", "torch")
            "double_press" -> prefs.getString("essential_action_double_press", "calculator")
            "triple_press" -> prefs.getString("essential_action_triple_press", "ringer_mode")
            "long_press" -> prefs.getString("essential_action_long_press", "power_menu")
            else -> "none"
        } ?: "none"

        Log.d(TAG, "Triggered: $trigger -> Action: $action")
        executeAction(action)
    }

    fun executeAction(action: String) {
        when (action) {
            "lock_screen" -> performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            "power_menu" -> performGlobalAction(GLOBAL_ACTION_POWER_DIALOG)
            "volume_panel" -> {
                val intent = Intent("android.settings.panel.action.VOLUME").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                try {
                    startActivity(intent)
                } catch (_: Exception) {}
            }
            "internet_panel" -> {
                val intent = Intent("android.settings.panel.action.INTERNET_CONNECTIVITY").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                try {
                    startActivity(intent)
                } catch (_: Exception) {}
            }
            "bluetooth_panel" -> {
                val intent = Intent("android.settings.panel.action.BLUETOOTH").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                try {
                    startActivity(intent)
                } catch (_: Exception) {}
            }
            else -> {
                // Forward to MainActivity or GlyphBackgroundService
                val intent = Intent("com.example.glyph.ACTION_EXECUTE_KEY").apply {
                    putExtra("action", action)
                    setPackage(packageName)
                }
                sendBroadcast(intent)
            }
        }
    }

    fun performLockScreen(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
    }

    fun performPowerMenu(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_POWER_DIALOG)
    }
}

