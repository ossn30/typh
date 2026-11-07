package com.example.glyph

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
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
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

object DynamicIslandOverlay {
    private const val TAG = "TYPH_DynamicIsland"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentView: View? = null
    private var currentParams: WindowManager.LayoutParams? = null
    private var currentWm: WindowManager? = null
    private var dismissRunnable: Runnable? = null

    // State tracking
    var isShowing: Boolean = false
        private set
    private var currentBatteryPercent: Int = 85
    private var currentIsCharging: Boolean = false
    private var isExpanded: Boolean = false
    private var stayWhileChargingActive: Boolean = false

    // View references for live updates without re-inflation
    private var batteryTextView: TextView? = null
    private var statusTextView: TextView? = null
    private var expandedContainer: LinearLayout? = null
    private var expandedProgressBar: ProgressBar? = null

    fun showCharging(
        context: Context,
        batteryPercent: Int,
        isCharging: Boolean,
        stayWhileCharging: Boolean = true,
        durationMs: Long = 4000L
    ) {
        mainHandler.post {
            try {
                showChargingInternal(context, batteryPercent, isCharging, stayWhileCharging, durationMs)
            } catch (e: Exception) {
                Log.e(TAG, "Error displaying Dynamic Island: ${e.message}", e)
            }
        }
    }

    fun updateBattery(batteryPercent: Int, isCharging: Boolean) {
        mainHandler.post {
            currentBatteryPercent = batteryPercent
            currentIsCharging = isCharging

            if (!isCharging && stayWhileChargingActive) {
                dismiss()
                return@post
            }

            if (isShowing && currentView != null) {
                batteryTextView?.text = "$batteryPercent%"
                expandedProgressBar?.progress = batteryPercent
            }
        }
    }

    fun dismiss() {
        mainHandler.post {
            dismissRunnable?.let { mainHandler.removeCallbacks(it) }
            dismissRunnable = null
            stayWhileChargingActive = false

            val wm = currentWm ?: return@post
            val view = currentView ?: return@post
            dismissAnimated(wm, view)
        }
    }

    private fun showChargingInternal(
        context: Context,
        batteryPercent: Int,
        isCharging: Boolean,
        stayWhileCharging: Boolean,
        durationMs: Long
    ) {
        val prefs = context.getSharedPreferences("glyph_native_settings", Context.MODE_PRIVATE)
        val islandEnabled = prefs.getBoolean("island_enabled", true)
        val showOnCharging = prefs.getBoolean("island_show_on_charging", true)
        if (!islandEnabled || (!showOnCharging && isCharging)) {
            Log.d(TAG, "Dynamic Island or charging display disabled in settings")
            return
        }

        currentBatteryPercent = batteryPercent
        currentIsCharging = isCharging
        stayWhileChargingActive = stayWhileCharging && isCharging

        val windowContext = GlyphAccessibilityService.instance ?: context
        val wm = windowContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return

        // If already showing, simply update the battery and don't re-create view
        if (isShowing && currentView != null) {
            batteryTextView?.text = "$batteryPercent%"
            expandedProgressBar?.progress = batteryPercent
            return
        }

        dismissImmediate(wm)

        val metrics = context.resources.displayMetrics
        val density = metrics.density

        // Camera Cutout calculation
        val detectedCutout = detectCutout(context)
        val customTopMargin = prefs.getInt("island_top_margin", 10)
        val customDiameter = prefs.getInt("island_cutout_diameter", 32)
        val pillWidthDp = prefs.getInt("island_pill_width", 195)

        val cutoutDiameterPx = if (detectedCutout != null && detectedCutout.height() > 0) {
            detectedCutout.height()
        } else {
            (customDiameter * density).toInt()
        }

        // Vertically center the pill (height ~38dp) over the camera cutout
        val pillHeightPx = (38 * density).toInt()
        val topMarginPx = if (detectedCutout != null && detectedCutout.top >= 0) {
            (detectedCutout.centerY() - (pillHeightPx / 2)).coerceAtLeast(0)
        } else {
            (customTopMargin * density).toInt()
        }

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
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            x = 0
            y = topMarginPx
            windowAnimations = 0

            // Crucial: Allow drawing inside the camera cutout area
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        isExpanded = false
        val view = buildChargingPill(context, batteryPercent, isCharging, cutoutDiameterPx, pillWidthDp, density)

        // Interactive toggle on tap: expand to see more details, or collapse
        view.setOnClickListener {
            toggleExpand(wm, view, params, density)
        }

        try {
            wm.addView(view, params)
            currentView = view
            currentParams = params
            currentWm = wm
            isShowing = true

            // Snappy Dynamic Island expansion from camera punch-hole
            view.alpha = 0f
            view.scaleX = 0.28f
            view.scaleY = 0.5f

            view.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(300)
                .setInterpolator(OvershootInterpolator(1.25f))
                .start()

            // If not set to stay permanently while charging (e.g. preview trigger), auto dismiss
            if (!stayWhileChargingActive) {
                val runnable = Runnable {
                    dismissAnimated(wm, view)
                }
                dismissRunnable = runnable
                mainHandler.postDelayed(runnable, durationMs)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add Dynamic Island view: ${e.message}", e)
        }
    }

    private fun toggleExpand(wm: WindowManager, view: View, params: WindowManager.LayoutParams, density: Float) {
        isExpanded = !isExpanded
        if (isExpanded) {
            expandedContainer?.visibility = View.VISIBLE
            view.animate()
                .scaleX(1.05f)
                .scaleY(1.05f)
                .setDuration(150)
                .withEndAction {
                    view.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                }
                .start()
        } else {
            expandedContainer?.visibility = View.GONE
        }
        try {
            wm.updateViewLayout(view, params)
        } catch (_: Exception) {}
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
        currentParams = null
        currentWm = null
        isShowing = false
        batteryTextView = null
        statusTextView = null
        expandedContainer = null
        expandedProgressBar = null
    }

    private fun dismissAnimated(wm: WindowManager, view: View) {
        dismissRunnable?.let { mainHandler.removeCallbacks(it) }
        dismissRunnable = null

        if (currentView != view) return

        view.animate()
            .alpha(0f)
            .scaleX(0.24f)
            .scaleY(0.4f)
            .setDuration(220)
            .setInterpolator(AccelerateInterpolator())
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    try {
                        wm.removeView(view)
                    } catch (_: Exception) {}
                    if (currentView == view) {
                        currentView = null
                        currentParams = null
                        currentWm = null
                        isShowing = false
                        batteryTextView = null
                        statusTextView = null
                        expandedContainer = null
                        expandedProgressBar = null
                    }
                }
            })
            .start()
    }

    private fun buildChargingPill(
        context: Context,
        batteryPercent: Int,
        isCharging: Boolean,
        cutoutDiameterPx: Int,
        pillWidthDp: Int,
        density: Float
    ): View {
        val master = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(
                (14 * density).toInt(),
                (7 * density).toInt(),
                (14 * density).toInt(),
                (7 * density).toInt()
            )

            background = GradientDrawable().apply {
                setColor(Color.BLACK)
                cornerRadius = 24 * density
                setStroke((0.8f * density).toInt(), Color.parseColor("#26262B"))
            }
            elevation = 20 * density
        }

        // Top Row: [ Battery % ] --- [ Camera Cutout ] --- [ ⚡ CHARGING ]
        val topRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        // Left Wing: Battery Percentage
        val leftWing = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumWidth = (45 * density).toInt()
        }

        val bText = TextView(context).apply {
            text = "$batteryPercent%"
            setTextColor(Color.WHITE)
            textSize = 12.5f
            typeface = Typeface.create("sans-serif-black", Typeface.BOLD)
            letterSpacing = 0.04f
        }
        batteryTextView = bText
        leftWing.addView(bText)
        topRow.addView(leftWing)

        // Center: Hollow space reserving area for physical Camera Cutout
        val cameraSpacer = View(context).apply {
            layoutParams = ViewGroup.LayoutParams(
                cutoutDiameterPx.coerceAtLeast((28 * density).toInt()),
                cutoutDiameterPx.coerceAtLeast((28 * density).toInt())
            )
        }
        topRow.addView(cameraSpacer)

        // Right Wing: Green Lightning Bolt & Charging Status
        val rightWing = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumWidth = (70 * density).toInt()
        }

        val boltIcon = TextView(context).apply {
            text = "⚡"
            setTextColor(Color.parseColor("#34C759"))
            textSize = 13.5f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, (4 * density).toInt(), 0)
        }
        rightWing.addView(boltIcon)

        val sText = TextView(context).apply {
            text = if (isCharging) "CHARGING" else "CONNECTED"
            setTextColor(Color.parseColor("#34C759"))
            textSize = 9.5f
            typeface = Typeface.MONOSPACE
            letterSpacing = 0.08f
        }
        statusTextView = sText
        rightWing.addView(sText)
        topRow.addView(rightWing)

        master.addView(topRow)

        // Bottom Expandable Drawer (Revealed on Tap)
        val drawer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.GONE
            setPadding(
                (6 * density).toInt(),
                (8 * density).toInt(),
                (6 * density).toInt(),
                (4 * density).toInt()
            )
        }

        val pBar = ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal).apply {
            layoutParams = LinearLayout.LayoutParams(
                (180 * density).toInt(),
                (4 * density).toInt()
            ).apply {
                bottomMargin = (6 * density).toInt()
            }
            max = 100
            progress = batteryPercent
            progressDrawable = GradientDrawable().apply {
                setColor(Color.parseColor("#34C759"))
                cornerRadius = 2 * density
            }
        }
        expandedProgressBar = pBar
        drawer.addView(pBar)

        val detailText = TextView(context).apply {
            text = "NOTHING OS // RAPID CHARGE"
            setTextColor(Color.parseColor("#8E8E93"))
            textSize = 8.5f
            typeface = Typeface.MONOSPACE
            letterSpacing = 0.1f
        }
        drawer.addView(detailText)

        expandedContainer = drawer
        master.addView(drawer)

        return master
    }

    fun detectCutout(context: Context): Rect? {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val insets = wm.maximumWindowMetrics.windowInsets
            val cutout = insets.displayCutout
            if (cutout != null) {
                val rects = cutout.boundingRects
                if (rects.isNotEmpty()) {
                    return rects[0]
                }
            }
        }
        return null
    }

    fun getCutoutInfo(context: Context): Map<String, Any> {
        val rect = detectCutout(context)
        val metrics = context.resources.displayMetrics
        val density = metrics.density

        return if (rect != null) {
            mapOf(
                "hasCutout" to true,
                "top" to (rect.top / density).toInt(),
                "bottom" to (rect.bottom / density).toInt(),
                "left" to (rect.left / density).toInt(),
                "right" to (rect.right / density).toInt(),
                "width" to (rect.width() / density).toInt(),
                "height" to (rect.height() / density).toInt()
            )
        } else {
            mapOf(
                "hasCutout" to false,
                "top" to 10,
                "bottom" to 42,
                "left" to ((metrics.widthPixels / density / 2) - 16).toInt(),
                "right" to ((metrics.widthPixels / density / 2) + 16).toInt(),
                "width" to 32,
                "height" to 32
            )
        }
    }
}
