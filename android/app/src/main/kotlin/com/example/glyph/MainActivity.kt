package com.example.glyph

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.util.Log
import com.nothing.ketchum.Common
import com.nothing.ketchum.Glyph
import com.nothing.ketchum.GlyphException
import com.nothing.ketchum.GlyphFrame
import com.nothing.ketchum.GlyphManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nothing.glyph_3a"
    private var isServiceConnected = false
    private var isSessionOpened = false
    private var methodChannel: MethodChannel? = null

    // Battery & Charging tracking
    private var isCharging = false
    private var batteryLevel = 0
    private var batteryReceiverRegistered = false

    // Native High-Speed Animation Sequence Player
    private data class CompiledFrame(val frame: GlyphFrame?, val durationMs: Long)
    private var animationThread: Thread? = null
    @Volatile private var isAnimationRunning = false

    // Shake for Glyph Torch Detector
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var isShakeDetectionEnabled = false
    private var shakeThresholdG = 2.0f
    private var lastShakeTimestamp = 0L
    private val SHAKE_DEBOUNCE_MS = 650L

    private val shakeListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            if (event == null || !isShakeDetectionEnabled) return
            if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
                val x = event.values[0] / SensorManager.GRAVITY_EARTH
                val y = event.values[1] / SensorManager.GRAVITY_EARTH
                val z = event.values[2] / SensorManager.GRAVITY_EARTH
                val gForce = Math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()

                if (gForce >= shakeThresholdG) {
                    val now = System.currentTimeMillis()
                    if (now - lastShakeTimestamp > SHAKE_DEBOUNCE_MS) {
                        lastShakeTimestamp = now
                        Log.d(TAG, "Shake detected: gForce=$gForce, threshold=$shakeThresholdG")
                        runOnUiThread {
                            try {
                                methodChannel?.invokeMethod(
                                    "onShakeDetected",
                                    mapOf("gForce" to gForce)
                                )
                            } catch (e: Exception) {
                                Log.w(TAG, "Failed to invoke onShakeDetected: ${e.message}")
                            }
                        }
                    }
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    companion object {
        private const val TAG = "TYPH_Glyph3a"
    }

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            isCharging = (status == BatteryManager.BATTERY_STATUS_CHARGING ||
                          status == BatteryManager.BATTERY_STATUS_FULL)
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            batteryLevel = if (level >= 0 && scale > 0) (level * 100 / scale) else 0

            notifyBatteryToFlutter()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "initGlyph" -> {
                    initGlyph(result)
                }
                "getDeviceStatus" -> {
                    result.success(getDeviceStatusMap())
                }
                "getBatteryStatus" -> {
                    result.success(getBatteryStatusMap())
                }
                "toggleChannels" -> {
                    val channels = call.argument<List<Int>>("channels") ?: emptyList()
                    val brightness = call.argument<Int>("brightness") ?: 4000
                    toggleChannels(channels, brightness, result)
                }
                "animateChannels" -> {
                    val channels = call.argument<List<Int>>("channels") ?: emptyList()
                    val period = call.argument<Int>("period") ?: 2000
                    val cycles = call.argument<Int>("cycles") ?: 3
                    val interval = call.argument<Int>("interval") ?: 100
                    animateChannels(channels, period, cycles, interval, result)
                }
                "toggleGroup" -> {
                    val group = call.argument<String>("group") ?: "ALL"
                    toggleGroup(group, result)
                }
                "turnOff" -> {
                    turnOff(result)
                }
                "displayProgress" -> {
                    val progress = call.argument<Int>("progress") ?: 0
                    val reverse = call.argument<Boolean>("reverse") ?: false
                    displayProgress(progress, reverse, result)
                }
                "closeSession" -> {
                    closeSession(result)
                }
                "playAnimationSequence" -> {
                    val frames = call.argument<List<Map<String, Any>>>("frames") ?: emptyList()
                    val loop = call.argument<Boolean>("loop") ?: true
                    playAnimationSequence(frames, loop, result)
                }
                "stopAnimationSequence" -> {
                    stopAnimationSequence(result)
                }
                "setShakeDetection" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val threshold = (call.argument<Number>("threshold"))?.toDouble() ?: 2.0
                    setShakeDetection(enabled, threshold, result)
                }
                "syncBackgroundSettings" -> {
                    @Suppress("UNCHECKED_CAST")
                    val settings = call.arguments as? Map<String, Any?> ?: emptyMap()
                    syncBackgroundSettings(settings, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        registerBatteryMonitor()
    }

    private fun registerBatteryMonitor() {
        if (!batteryReceiverRegistered) {
            val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus: Intent? = registerReceiver(batteryReceiver, filter)
            batteryStatus?.let { intent ->
                val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                isCharging = (status == BatteryManager.BATTERY_STATUS_CHARGING ||
                              status == BatteryManager.BATTERY_STATUS_FULL)
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                batteryLevel = if (level >= 0 && scale > 0) (level * 100 / scale) else 0
            }
            batteryReceiverRegistered = true
        }
    }

    private fun getBatteryStatusMap(): Map<String, Any> {
        return mapOf(
            "isCharging" to isCharging,
            "batteryLevel" to batteryLevel
        )
    }

    private fun notifyBatteryToFlutter() {
        runOnUiThread {
            try {
                methodChannel?.invokeMethod("onBatteryChanged", getBatteryStatusMap())
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send battery update: ${e.message}")
            }
        }
    }

    private fun getDeviceStatusMap(): Map<String, Any?> {
        val is3a = Common.is24111()
        return mapOf(
            "isPhone3a" to is3a,
            "deviceModel" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "deviceTarget" to Glyph.DEVICE_24111,
            "isServiceConnected" to GlyphNativeManager.isServiceConnected,
            "isSessionOpened" to GlyphNativeManager.isSessionOpened
        )
    }

    private fun notifyStatusToFlutter() {
        runOnUiThread {
            try {
                methodChannel?.invokeMethod("onStatusChanged", getDeviceStatusMap())
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send status update: ${e.message}")
            }
        }
    }

    private fun startGlyphBackgroundService() {
        try {
            val serviceIntent = Intent(applicationContext, GlyphBackgroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(serviceIntent)
            } else {
                applicationContext.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start background service: ${e.message}", e)
        }
    }

    private fun syncBackgroundSettings(settings: Map<String, Any?>, result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences("glyph_native_settings", Context.MODE_PRIVATE)
            val editor = prefs.edit()

            if (settings.containsKey("charging_animation_enabled")) {
                editor.putBoolean("charging_enabled", settings["charging_animation_enabled"] as? Boolean ?: true)
            }
            if (settings.containsKey("charging_selected_arcs")) {
                @Suppress("UNCHECKED_CAST")
                val arcs = (settings["charging_selected_arcs"] as? List<*>)?.mapNotNull { it?.toString() }?.toSet() ?: setOf("C")
                editor.putStringSet("selected_arcs", arcs)
            }
            if (settings.containsKey("charging_is_clockwise")) {
                editor.putBoolean("is_clockwise", settings["charging_is_clockwise"] as? Boolean ?: true)
            }
            if (settings.containsKey("charging_is_combined")) {
                editor.putBoolean("is_combined", settings["charging_is_combined"] as? Boolean ?: true)
            }
            if (settings.containsKey("charging_is_duration_always")) {
                editor.putBoolean("is_duration_always", settings["charging_is_duration_always"] as? Boolean ?: true)
            }
            if (settings.containsKey("charging_timer_duration_seconds")) {
                editor.putInt("timer_duration", (settings["charging_timer_duration_seconds"] as? Number)?.toInt() ?: 3)
            }
            if (settings.containsKey("charging_brightness")) {
                editor.putInt("charging_brightness", (settings["charging_brightness"] as? Number)?.toInt() ?: 4000)
            }
            if (settings.containsKey("shake_torch_enabled")) {
                editor.putBoolean("shake_torch_enabled", settings["shake_torch_enabled"] as? Boolean ?: false)
            }
            if (settings.containsKey("shake_threshold")) {
                editor.putFloat("shake_threshold", (settings["shake_threshold"] as? Number)?.toFloat() ?: 2.0f)
            }
            if (settings.containsKey("torch_brightness")) {
                editor.putInt("torch_brightness", (settings["torch_brightness"] as? Number)?.toInt() ?: 4000)
            }
            editor.apply()

            startGlyphBackgroundService()
            GlyphBackgroundService.instance?.syncSensorState()

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing background settings: ${e.message}", e)
            result.error("SYNC_ERROR", e.message, null)
        }
    }

    private fun initGlyph(result: MethodChannel.Result) {
        try {
            startGlyphBackgroundService()
            GlyphNativeManager.initIfNeeded(applicationContext)
            GlyphNativeManager.addConnectionListener {
                runOnUiThread {
                    notifyStatusToFlutter()
                }
            }
            result.success(getDeviceStatusMap())
        } catch (e: Exception) {
            Log.e(TAG, "initGlyph failed: ${e.message}", e)
            result.error("INIT_FAILED", e.message, null)
        }
    }

    private fun stopCurrentAnimation() {
        isAnimationRunning = false
        val t = animationThread
        if (t != null && t.isAlive) {
            t.interrupt()
            try {
                t.join(250)
            } catch (_: Exception) {}
        }
        animationThread = null
    }

    private fun playAnimationSequence(
        framesRaw: List<Map<String, Any>>,
        loop: Boolean,
        result: MethodChannel.Result
    ) {
        val gm = GlyphNativeManager.glyphManager
        if (gm == null) {
            result.error("NOT_INITIALIZED", "GlyphManager not initialized", null)
            return
        }

        stopCurrentAnimation()

        if (framesRaw.isEmpty()) {
            try {
                gm.turnOff()
            } catch (_: Exception) {}
            result.success(true)
            return
        }

        // Pre-build all GlyphFrame objects once so playback has ZERO object creation/JNI allocation overhead!
        val compiledFrames = ArrayList<CompiledFrame>(framesRaw.size)
        for (fMap in framesRaw) {
            val durationMs = (fMap["durationMs"] as? Number)?.toLong() ?: 32L
            @Suppress("UNCHECKED_CAST")
            val channels = (fMap["channels"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() } ?: emptyList()
            val brightness = ((fMap["brightness"] as? Number)?.toInt() ?: 4000).coerceIn(0, 4000)

            val frame: GlyphFrame? = if (channels.isEmpty()) {
                null
            } else {
                val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
                for (ch in channels) {
                    if (ch in 0..35) {
                        if (brightness == 4000) {
                            builder.buildChannel(ch)
                        } else {
                            builder.buildChannel(ch, brightness)
                        }
                    }
                }
                builder.build()
            }
            compiledFrames.add(CompiledFrame(frame, durationMs.coerceAtLeast(10L)))
        }

        isAnimationRunning = true
        val thread = Thread {
            try {
                while (isAnimationRunning && !Thread.currentThread().isInterrupted) {
                    for (cf in compiledFrames) {
                        if (!isAnimationRunning || Thread.currentThread().isInterrupted) break
                        val start = System.currentTimeMillis()
                        try {
                            if (cf.frame == null) {
                                gm.turnOff()
                            } else {
                                gm.toggle(cf.frame)
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Frame toggle error: ${e.message}")
                        }
                        val elapsed = System.currentTimeMillis() - start
                        val sleepTime = cf.durationMs - elapsed
                        if (sleepTime > 0) {
                            Thread.sleep(sleepTime)
                        }
                    }
                    if (!loop) break
                }
            } catch (_: InterruptedException) {
                // Thread interrupted on stop
            } finally {
                if (!isAnimationRunning || !loop) {
                    try {
                        gm.turnOff()
                    } catch (_: Exception) {}
                }
            }
        }
        thread.priority = Thread.MAX_PRIORITY
        animationThread = thread
        thread.start()

        result.success(true)
    }

    private fun stopAnimationSequence(result: MethodChannel.Result) {
        stopCurrentAnimation()
        try {
            GlyphNativeManager.glyphManager?.turnOff()
        } catch (e: Exception) {
            Log.w(TAG, "Error turning off on stop: ${e.message}")
        }
        result.success(true)
    }

    private fun toggleChannels(channels: List<Int>, brightness: Int, result: MethodChannel.Result) {
        stopCurrentAnimation()
        val gm = GlyphNativeManager.glyphManager
        if (gm == null) {
            result.error("NOT_INITIALIZED", "GlyphManager not initialized", null)
            return
        }

        try {
            if (channels.isEmpty()) {
                gm.turnOff()
            } else {
                val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
                val clampedBrightness = brightness.coerceIn(0, 4000)
                for (ch in channels) {
                    if (ch in 0..35) {
                        if (clampedBrightness == 4000) {
                            builder.buildChannel(ch)
                        } else {
                            builder.buildChannel(ch, clampedBrightness)
                        }
                    }
                }
                val frame = builder.build()
                gm.toggle(frame)
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "toggleChannels error: ${e.message}", e)
            result.error("TOGGLE_ERROR", e.message, null)
        }
    }

    private fun animateChannels(
        channels: List<Int>,
        period: Int,
        cycles: Int,
        interval: Int,
        result: MethodChannel.Result
    ) {
        val gm = GlyphNativeManager.glyphManager
        if (gm == null) {
            result.error("NOT_INITIALIZED", "GlyphManager not initialized", null)
            return
        }

        try {
            val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
            for (ch in channels) {
                if (ch in 0..35) {
                    builder.buildChannel(ch)
                }
            }
            builder.buildPeriod(period)
            builder.buildCycles(cycles)
            builder.buildInterval(interval)
            val frame = builder.build()
            gm.animate(frame)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "animateChannels error: ${e.message}", e)
            result.error("ANIMATE_ERROR", e.message, null)
        }
    }

    private fun toggleGroup(group: String, result: MethodChannel.Result) {
        val gm = GlyphNativeManager.glyphManager
        if (gm == null) {
            result.error("NOT_INITIALIZED", "GlyphManager not initialized", null)
            return
        }

        try {
            val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
            when (group.uppercase()) {
                "A" -> builder.buildChannelA()
                "B" -> builder.buildChannelB()
                "C" -> builder.buildChannelC()
                "ALL" -> {
                    builder.buildChannelA()
                    builder.buildChannelB()
                    builder.buildChannelC()
                }
            }
            val frame = builder.build()
            gm.toggle(frame)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "toggleGroup error: ${e.message}", e)
            result.error("GROUP_ERROR", e.message, null)
        }
    }

    private fun displayProgress(progress: Int, reverse: Boolean, result: MethodChannel.Result) {
        val gm = GlyphNativeManager.glyphManager
        if (gm == null) {
            result.error("NOT_INITIALIZED", "GlyphManager not initialized", null)
            return
        }

        try {
            val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
            val frame = builder.buildChannelC().build()
            val clamped = progress.coerceIn(0, 100)
            gm.displayProgress(frame, clamped, reverse)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "displayProgress error: ${e.message}", e)
            result.error("PROGRESS_ERROR", e.message, null)
        }
    }

    private fun turnOff(result: MethodChannel.Result) {
        stopCurrentAnimation()
        try {
            GlyphNativeManager.glyphManager?.turnOff()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "turnOff error: ${e.message}", e)
            result.error("TURNOFF_ERROR", e.message, null)
        }
    }

    private fun setShakeDetection(enabled: Boolean, threshold: Double, result: MethodChannel.Result) {
        try {
            isShakeDetectionEnabled = enabled
            shakeThresholdG = threshold.toFloat()
            if (sensorManager == null) {
                sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
                accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            }
            if (enabled) {
                accelerometer?.let {
                    sensorManager?.unregisterListener(shakeListener)
                    sensorManager?.registerListener(shakeListener, it, SensorManager.SENSOR_DELAY_UI)
                    Log.d(TAG, "Shake detection registered with threshold: $shakeThresholdG")
                }
            } else {
                sensorManager?.unregisterListener(shakeListener)
                Log.d(TAG, "Shake detection unregistered")
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "setShakeDetection error: ${e.message}", e)
            result.error("SHAKE_ERROR", e.message, null)
        }
    }

    private fun closeSession(result: MethodChannel.Result) {
        stopCurrentAnimation()
        try {
            GlyphNativeManager.glyphManager?.closeSession()
            isSessionOpened = false
            notifyStatusToFlutter()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "closeSession error: ${e.message}", e)
            result.error("CLOSE_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        stopCurrentAnimation()
        try {
            sensorManager?.unregisterListener(shakeListener)
            isShakeDetectionEnabled = false
        } catch (_: Exception) {}
        if (batteryReceiverRegistered) {
            try {
                unregisterReceiver(batteryReceiver)
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering batteryReceiver: ${e.message}")
            }
            batteryReceiverRegistered = false
        }
        // Note: We intentionally do NOT unInit GlyphManager here.
        // GlyphBackgroundService continues running in the background to handle
        // persistent charging animations and gesture torch while the app is closed.
        super.onDestroy()
    }
}
