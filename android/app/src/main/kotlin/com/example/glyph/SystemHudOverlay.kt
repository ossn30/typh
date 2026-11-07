package com.example.glyph

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.AccelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

object SystemHudOverlay {
    private const val TAG = "TYPH_SystemHudOverlay"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentView: View? = null
    private var dismissRunnable: Runnable? = null

    fun show(
        context: Context,
        trigger: String,
        action: String,
        customMessage: String? = null
    ) {
        mainHandler.post {
            try {
                showInternal(context, trigger, action, customMessage)
            } catch (e: Exception) {
                Log.e(TAG, "Error displaying system HUD overlay: ${e.message}", e)
            }
        }
    }

    private fun showInternal(
        context: Context,
        trigger: String,
        action: String,
        customMessage: String?
    ) {
        val prefs = context.getSharedPreferences("glyph_native_settings", Context.MODE_PRIVATE)
        val overlayEnabled = prefs.getBoolean("overlay_enabled", true)
        if (!overlayEnabled) {
            Log.d(TAG, "Overlay disabled in settings, skipping")
            return
        }

        val side = prefs.getString("overlay_position_side", "left") ?: "left"
        val positionPercent = prefs.getInt("overlay_position_percent", 45).coerceIn(10, 90)
        val durationMs = prefs.getInt("overlay_duration_ms", 2000).toLong().coerceIn(800L, 5000L)

        // Select best available window context
        val windowContext = GlyphAccessibilityService.instance ?: context
        val wm = windowContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        if (wm == null) {
            Log.w(TAG, "WindowManager unavailable")
            return
        }

        // Dismiss previous view if still showing
        dismissImmediate(wm)

        val metrics = context.resources.displayMetrics
        val density = metrics.density
        val screenHeight = metrics.heightPixels

        // Determine target Y position matching physical key
        val yPos = (screenHeight * (positionPercent.toFloat() / 100f)).toInt()

        val layoutType = if (GlyphAccessibilityService.isRunning) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or (if (side == "right") Gravity.END else Gravity.START)
            x = (14 * density).toInt()
            y = yPos
            windowAnimations = 0
        }

        val view = buildHudView(context, trigger, action, customMessage, density, side)

        view.setOnClickListener {
            dismissAnimated(wm, view, side)
        }

        try {
            wm.addView(view, params)
            currentView = view

            // Snappy entrance animation sliding from the physical button frame
            view.alpha = 0f
            view.scaleX = 0.88f
            view.scaleY = 0.88f
            view.translationX = if (side == "right") 70f * density else -70f * density

            view.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .translationX(0f)
                .setDuration(220)
                .setInterpolator(OvershootInterpolator(1.2f))
                .start()

            // Auto dismiss timer
            val runnable = Runnable {
                dismissAnimated(wm, view, side)
            }
            dismissRunnable = runnable
            mainHandler.postDelayed(runnable, durationMs)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add HUD view to window: ${e.message}", e)
        }
    }

    private fun dismissImmediate(wm: WindowManager) {
        dismissRunnable?.let { mainHandler.removeCallbacks(it) }
        dismissRunnable = null
        currentView?.let { v ->
            try {
                wm.removeViewImmediate(v)
            } catch (_: Exception) {}
        }
        currentView = null
    }

    private fun dismissAnimated(wm: WindowManager, view: View, side: String) {
        dismissRunnable?.let { mainHandler.removeCallbacks(it) }
        dismissRunnable = null

        if (currentView != view) return

        val density = view.resources.displayMetrics.density
        view.animate()
            .alpha(0f)
            .scaleX(0.92f)
            .scaleY(0.92f)
            .translationX(if (side == "right") 70f * density else -70f * density)
            .setDuration(160)
            .setInterpolator(AccelerateInterpolator())
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    try {
                        wm.removeView(view)
                    } catch (_: Exception) {}
                    if (currentView == view) {
                        currentView = null
                    }
                }
            })
            .start()
    }

    private fun buildHudView(
        context: Context,
        trigger: String,
        action: String,
        customMessage: String?,
        density: Float,
        side: String
    ): View {
        // Minimalist Black Pill Capsule matching Flutter live pill
        val capsule = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(
                (8 * density).toInt(),
                (8 * density).toInt(),
                (14 * density).toInt(),
                (8 * density).toInt()
            )

            background = GradientDrawable().apply {
                setColor(Color.BLACK)
                cornerRadius = 24 * density
            }
            elevation = 16 * density
        }

        // Circular Green Badge (matching CupertinoColors.systemGreen / #34C759)
        val iconBadge = FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                (32 * density).toInt(),
                (32 * density).toInt()
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#34C759"))
            }

            val symbol = TextView(context).apply {
                layoutParams = FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    gravity = Gravity.CENTER
                }
                text = getActionSymbol(action)
                setTextColor(Color.BLACK)
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
            }
            addView(symbol)
        }
        capsule.addView(iconBadge)

        // Spacing: 10dp
        val spacer = View(context).apply {
            layoutParams = ViewGroup.LayoutParams((10 * density).toInt(), 1)
        }
        capsule.addView(spacer)

        // Action Title (Crisp white text)
        val actionText = TextView(context).apply {
            text = formatActionTitle(action, customMessage)
            setTextColor(Color.WHITE)
            textSize = 12.5f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
        }
        capsule.addView(actionText)

        return capsule
    }

    private fun getActionSymbol(action: String): String {
        return when (action.lowercase()) {
            "torch" -> "⚡"
            "calculator" -> "🖩"
            "rotation_lock" -> "↻"
            "auto_brightness" -> "☼"
            "ringer_mode" -> "🔔"
            "dnd" -> "⊖"
            "voice_assistant" -> "✦"
            "lock_screen" -> "🔒"
            "wake_screen" -> "◉"
            "brightness_slider" -> "◐"
            "night_light" -> "☾"
            "extra_dim" -> "◑"
            "internet_panel" -> "ᯤ"
            "bluetooth_panel" -> "ᛒ"
            "volume_panel" -> "🔊"
            "power_menu" -> "⏻"
            "set_timer" -> "⏱"
            "read_aloud" -> "🗣"
            "copy_text" -> "📋"
            "paste_text" -> "📝"
            else -> "●"
        }
    }

    private fun formatActionTitle(action: String, customMessage: String?): String {
        if (!customMessage.isNullOrBlank()) {
            return customMessage
        }
        return when (action.lowercase()) {
            "torch" -> "Torch"
            "calculator" -> "Calculator"
            "rotation_lock" -> "Rotation Lock"
            "auto_brightness" -> "Auto Brightness"
            "ringer_mode" -> "Ring / Vibrate / Silent"
            "dnd" -> "Do Not Disturb"
            "voice_assistant" -> "Voice Assistant"
            "lock_screen" -> "Lock Screen"
            "wake_screen" -> "Wake Screen"
            "brightness_slider" -> "Brightness Slider"
            "night_light" -> "Night Light"
            "extra_dim" -> "Extra Dim"
            "internet_panel" -> "Internet Panel"
            "bluetooth_panel" -> "Bluetooth Panel"
            "volume_panel" -> "Volume Panel"
            "power_menu" -> "Power Menu"
            "set_timer" -> "Set Timer"
            "read_aloud" -> "Read Aloud Selected Text"
            "copy_text" -> "Copy Selected Text"
            "paste_text" -> "Paste Selected Text"
            else -> action.split('_').joinToString(" ") { word ->
                word.replaceFirstChar { it.uppercase() }
            }
        }
    }
}
