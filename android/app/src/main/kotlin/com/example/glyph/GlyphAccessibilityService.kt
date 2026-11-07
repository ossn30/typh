package com.example.glyph

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
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
    private var isLongPressTriggered = false
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
            isLongPressTriggered = true
            tapCount = 0
            handler.removeCallbacks(multiTapRunnable)
            handleTrigger("long_press")
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "GlyphAccessibilityService connected")

        try {
            GlyphNativeManager.initIfNeeded(applicationContext)
            if (GlyphBackgroundService.instance == null) {
                val serviceIntent = Intent(applicationContext, GlyphBackgroundService::class.java)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(serviceIntent)
                } else {
                    applicationContext.startService(serviceIntent)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to start background service from accessibility: ${e.message}")
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        // Strict guard: NEVER intercept volume up/down, or power keys
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
            event.keyCode == KeyEvent.KEYCODE_POWER) {
            return super.onKeyEvent(event)
        }

        val prefs = getSharedPreferences("glyph_native_settings", Context.MODE_PRIVATE)
        val remapEnabled = prefs.getBoolean("essential_key_remap_enabled", true)
        if (!remapEnabled) {
            return super.onKeyEvent(event)
        }

        val targetScanCode = prefs.getInt("essential_scan_code", 250)
        val targetKeyCode = prefs.getInt("essential_key_code", 0)

        // Essential Key on Nothing Phone (3a): scanCode 250, keyCode 0, KEYCODE_UNKNOWN
        val isEssential = (event.scanCode == 250) ||
            (event.keyCode == 0) ||
            (targetScanCode == 250 && event.scanCode == 250) ||
            (targetScanCode > 0 && event.scanCode == targetScanCode) ||
            (targetKeyCode > 0 && event.keyCode == targetKeyCode)

        if (!isEssential) {
            return super.onKeyEvent(event)
        }

        val gapMs = prefs.getInt("essential_timing_multi_press_gap_ms", 350).toLong()
        val holdMs = prefs.getInt("essential_timing_long_press_hold_ms", 500).toLong()

        if (event.action == KeyEvent.ACTION_DOWN) {
            if (event.repeatCount > 0) {
                // Key repeat while holding down: ignore and consume
                return true
            }
            isKeyDown = true
            isLongPressTriggered = false
            keyDownTime = System.currentTimeMillis()
            handler.removeCallbacks(multiTapRunnable)
            handler.removeCallbacks(longPressRunnable)
            handler.postDelayed(longPressRunnable, holdMs)
            return true
        } else if (event.action == KeyEvent.ACTION_UP) {
            isKeyDown = false
            handler.removeCallbacks(longPressRunnable)
            if (!isLongPressTriggered) {
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

        // Show system-wide Nothing OS HUD overlay positioned near the physical key
        SystemHudOverlay.show(this, trigger, action)

        // If MainActivity is in foreground, notify it as well
        MainActivity.activeInstance?.notifyActionTriggered(trigger, action)
    }

    fun executeAction(action: String) {
        if (action == "none" || action.isBlank()) return

        when (action) {
            "lock_screen" -> {
                KeyActionExecutor.vibrate(this, 60L)
                performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            }
            "power_menu" -> {
                KeyActionExecutor.vibrate(this, 60L)
                performGlobalAction(GLOBAL_ACTION_POWER_DIALOG)
            }
            else -> {
                KeyActionExecutor.execute(this, action)
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

