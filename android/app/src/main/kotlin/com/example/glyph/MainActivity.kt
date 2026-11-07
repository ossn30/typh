package com.example.glyph

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.AlarmClock
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.util.Base64
import android.util.Log
import android.view.KeyEvent
import java.util.Locale
import com.nothing.ketchum.Common
import com.nothing.ketchum.Glyph
import com.nothing.ketchum.GlyphException
import com.nothing.ketchum.GlyphFrame
import com.nothing.ketchum.GlyphManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

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

    // Essential Key Remapper
    private var isListeningForHardwareKey = false
    private var tts: TextToSpeech? = null

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
        var activeInstance: MainActivity? = null
            private set
    }

    fun notifyActionTriggered(trigger: String, action: String) {
        runOnUiThread {
            try {
                methodChannel?.invokeMethod("onActionTriggered", mapOf(
                    "trigger" to trigger,
                    "action" to action
                ))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send onActionTriggered: ${e.message}")
            }
        }
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
        activeInstance = this

        // Ensure background services and Ketchum Glyph hardware connection are initialized immediately
        startGlyphBackgroundService()
        GlyphNativeManager.initIfNeeded(applicationContext)

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
                "getInstalledApps" -> {
                    getInstalledApps(result)
                }
                "isNotificationAccessGranted" -> {
                    result.success(isNotificationAccessGranted())
                }
                "openNotificationAccessSettings" -> {
                    openNotificationAccessSettings()
                    result.success(true)
                }
                "openNotificationSoundSettings" -> {
                    openNotificationSoundSettings()
                    result.success(true)
                }
                "syncNotificationRules" -> {
                    @Suppress("UNCHECKED_CAST")
                    val data = call.arguments as? Map<String, Any?> ?: emptyMap()
                    syncNotificationRules(data, result)
                }
                "checkEssentialPackagesDisabled" -> {
                    result.success(checkEssentialPackagesDisabled())
                }
                "startHardwareKeyListening" -> {
                    isListeningForHardwareKey = true
                    Log.d(TAG, "Hardware key listening started")
                    result.success(true)
                }
                "stopHardwareKeyListening" -> {
                    isListeningForHardwareKey = false
                    Log.d(TAG, "Hardware key listening stopped")
                    result.success(true)
                }
                "executeKeyAction" -> {
                    val action = call.argument<String>("action") ?: ""
                    @Suppress("UNCHECKED_CAST")
                    val params = call.argument<Map<String, Any?>>("params") ?: emptyMap()
                    executeKeyAction(action, params, result)
                }
                "setSystemBrightness" -> {
                    val brightness = (call.argument<Number>("brightness"))?.toFloat() ?: 0.5f
                    setSystemBrightness(brightness, result)
                }
                "getSystemBrightness" -> {
                    result.success(getSystemBrightness())
                }
                "isAccessibilityServiceEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "openAccessibilitySettings" -> {
                    openAccessibilitySettings()
                    result.success(true)
                }
                "showSystemHudOverlay" -> {
                    val trigger = call.argument<String>("trigger") ?: "single_press"
                    val action = call.argument<String>("action") ?: "torch"
                    val message = call.argument<String>("message")
                    SystemHudOverlay.show(this, trigger, action, message)
                    result.success(true)
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

    private val connectionListener: (Boolean) -> Unit = {
        runOnUiThread {
            notifyStatusToFlutter()
        }
    }

    private fun startGlyphBackgroundService() {
        if (GlyphBackgroundService.instance != null) {
            return
        }
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
            if (settings.containsKey("essential_key_remap_enabled")) {
                editor.putBoolean("essential_key_remap_enabled", settings["essential_key_remap_enabled"] as? Boolean ?: true)
            }
            if (settings.containsKey("essential_key_code")) {
                editor.putInt("essential_key_code", (settings["essential_key_code"] as? Number)?.toInt() ?: 0)
            }
            if (settings.containsKey("essential_scan_code")) {
                editor.putInt("essential_scan_code", (settings["essential_scan_code"] as? Number)?.toInt() ?: 250)
            }
            if (settings.containsKey("essential_action_single_press")) {
                editor.putString("essential_action_single_press", settings["essential_action_single_press"] as? String ?: "torch")
            }
            if (settings.containsKey("essential_action_double_press")) {
                editor.putString("essential_action_double_press", settings["essential_action_double_press"] as? String ?: "calculator")
            }
            if (settings.containsKey("essential_action_triple_press")) {
                editor.putString("essential_action_triple_press", settings["essential_action_triple_press"] as? String ?: "ringer_mode")
            }
            if (settings.containsKey("essential_action_long_press")) {
                editor.putString("essential_action_long_press", settings["essential_action_long_press"] as? String ?: "power_menu")
            }
            if (settings.containsKey("essential_timing_multi_press_gap_ms")) {
                editor.putInt("essential_timing_multi_press_gap_ms", (settings["essential_timing_multi_press_gap_ms"] as? Number)?.toInt() ?: 350)
            }
            if (settings.containsKey("essential_timing_long_press_hold_ms")) {
                editor.putInt("essential_timing_long_press_hold_ms", (settings["essential_timing_long_press_hold_ms"] as? Number)?.toInt() ?: 500)
            }
            if (settings.containsKey("overlay_enabled")) {
                editor.putBoolean("overlay_enabled", settings["overlay_enabled"] as? Boolean ?: true)
            }
            if (settings.containsKey("overlay_position_side")) {
                editor.putString("overlay_position_side", settings["overlay_position_side"] as? String ?: "left")
            }
            if (settings.containsKey("overlay_position_percent")) {
                editor.putInt("overlay_position_percent", (settings["overlay_position_percent"] as? Number)?.toInt() ?: 45)
            }
            if (settings.containsKey("overlay_duration_ms")) {
                editor.putInt("overlay_duration_ms", (settings["overlay_duration_ms"] as? Number)?.toInt() ?: 2000)
            }
            editor.commit()

            startGlyphBackgroundService()
            GlyphBackgroundService.instance?.syncSensorState()
            GlyphBackgroundService.instance?.refreshChargingAnimation()

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing background settings: ${e.message}", e)
            result.error("SYNC_ERROR", e.message, null)
        }
    }

    private fun syncNotificationRules(data: Map<String, Any?>, result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences(GlyphNotificationListenerService.PREFS_RULES, Context.MODE_PRIVATE)
            val editor = prefs.edit()

            if (data.containsKey("alerts_enabled")) {
                editor.putBoolean("alerts_enabled", data["alerts_enabled"] as? Boolean ?: false)
            }
            if (data.containsKey("default_enabled")) {
                editor.putBoolean("default_enabled", data["default_enabled"] as? Boolean ?: true)
            }
            if (data.containsKey("default_animation")) {
                val defJson = data["default_animation"] as? String
                if (defJson != null && defJson.isNotBlank()) {
                    editor.putString("default_animation", defJson)
                } else {
                    editor.remove("default_animation")
                }
            }

            @Suppress("UNCHECKED_CAST")
            val rules = data["rules"] as? Map<String, String>
            if (rules != null) {
                // Clear any existing rule_* keys first
                for (key in prefs.all.keys) {
                    if (key.startsWith("rule_")) {
                        editor.remove(key)
                    }
                }
                for ((pkg, animJson) in rules) {
                    editor.putString("rule_$pkg", animJson)
                }
            }

            editor.commit()
            Log.d(TAG, "Synced ${rules?.size ?: 0} app notification rules to native storage.")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing notification rules: ${e.message}", e)
            result.error("SYNC_RULES_ERROR", e.message, null)
        }
    }

    private fun getInstalledApps(result: MethodChannel.Result) {
        Thread {
            try {
                val pm = packageManager
                val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                    addCategory(Intent.CATEGORY_LAUNCHER)
                }
                val resolveInfos = pm.queryIntentActivities(mainIntent, 0)
                val appsList = ArrayList<Map<String, Any?>>()

                for (ri in resolveInfos) {
                    try {
                        val appName = ri.loadLabel(pm).toString()
                        val pkg = ri.activityInfo.packageName
                        if (pkg == packageName) continue

                        val iconDrawable = ri.loadIcon(pm)
                        val bitmap = drawableToBitmap(iconDrawable)
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 75, stream)
                        val iconBytes = stream.toByteArray()

                        appsList.add(mapOf(
                            "appName" to appName,
                            "packageName" to pkg,
                            "iconBytes" to iconBytes
                        ))
                    } catch (_: Exception) {}
                }

                appsList.sortBy { (it["appName"] as? String)?.lowercase() ?: "" }

                runOnUiThread {
                    result.success(appsList)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error fetching installed apps: ${e.message}", e)
                runOnUiThread {
                    result.error("APPS_ERROR", e.message, null)
                }
            }
        }.start()
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return Bitmap.createScaledBitmap(drawable.bitmap, 48, 48, true)
        }
        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth.coerceAtMost(48) else 48
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight.coerceAtMost(48) else 48
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return Bitmap.createScaledBitmap(bitmap, 48, 48, true)
    }

    private fun isNotificationAccessGranted(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        val myComponent = ComponentName(this, GlyphNotificationListenerService::class.java).flattenToString()
        return enabledListeners.contains(myComponent) || enabledListeners.contains(packageName)
    }

    private fun openNotificationAccessSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun openNotificationSoundSettings() {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_ALL_APPS_NOTIFICATION_SETTINGS)
            } else {
                Intent(Settings.ACTION_SOUND_SETTINGS)
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (_: Exception) {
            try {
                val soundIntent = Intent(Settings.ACTION_SOUND_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(soundIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Error opening sound settings: ${e.message}")
            }
        }
    }

    private fun checkEssentialPackagesDisabled(): Map<String, Any> {
        val pm = packageManager
        fun checkPackage(pkg: String): Map<String, Any> {
            return try {
                val appInfo = pm.getApplicationInfo(pkg, 0)
                val state = pm.getApplicationEnabledSetting(pkg)
                val isDisabled = !appInfo.enabled ||
                    state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED ||
                    state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER ||
                    state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED
                mapOf(
                    "packageName" to pkg,
                    "installed" to true,
                    "enabled" to appInfo.enabled,
                    "disabled" to isDisabled,
                    "state" to state
                )
            } catch (e: PackageManager.NameNotFoundException) {
                mapOf(
                    "packageName" to pkg,
                    "installed" to false,
                    "enabled" to false,
                    "disabled" to true,
                    "state" to -1
                )
            }
        }

        val recorder = checkPackage("com.nothing.ntessentialrecorder")
        val space = checkPackage("com.nothing.ntessentialspace")
        val recorderDisabled = recorder["disabled"] as Boolean
        val spaceDisabled = space["disabled"] as Boolean
        val allDisabled = recorderDisabled && spaceDisabled

        return mapOf(
            "recorder" to recorder,
            "space" to space,
            "recorderDisabled" to recorderDisabled,
            "spaceDisabled" to spaceDisabled,
            "allDisabled" to allDisabled
        )
    }

    private fun initGlyph(result: MethodChannel.Result) {
        try {
            startGlyphBackgroundService()
            GlyphNativeManager.initIfNeeded(applicationContext)
            GlyphNativeManager.addConnectionListener(connectionListener)
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

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        val scanCode = event.scanCode

        // Strict Hardware Filter: Volume Up (24), Volume Down (25), Power (26) must NEVER be remapped
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
            keyCode == KeyEvent.KEYCODE_POWER) {
            if (isListeningForHardwareKey && event.action == KeyEvent.ACTION_DOWN) {
                runOnUiThread {
                    methodChannel?.invokeMethod("onHardwareKeyCaptured", mapOf(
                        "keyCode" to keyCode,
                        "scanCode" to scanCode,
                        "keyName" to KeyEvent.keyCodeToString(keyCode),
                        "isRejected" to true,
                        "error" to "Volume and Power keys cannot be used as Essential Key"
                    ))
                }
            }
            return super.dispatchKeyEvent(event)
        }

        // Essential Key on Nothing Phone (3a): scanCode 250, keyCode 0, KEYCODE_UNKNOWN
        val isEssential = (scanCode == 250) || (keyCode == 0) || (keyCode == 0 && scanCode == 250)

        if (isListeningForHardwareKey && event.action == KeyEvent.ACTION_DOWN) {
            if (keyCode != KeyEvent.KEYCODE_BACK) {
                val keyName = if (isEssential) "KEYCODE_UNKNOWN" else KeyEvent.keyCodeToString(keyCode)
                Log.d(TAG, "Hardware key captured: keyCode=$keyCode, scanCode=$scanCode, keyName=$keyName, isEssential=$isEssential")
                runOnUiThread {
                    methodChannel?.invokeMethod("onHardwareKeyCaptured", mapOf(
                        "keyCode" to keyCode,
                        "scanCode" to scanCode,
                        "keyName" to keyName,
                        "isEssentialKey" to isEssential,
                        "isValid" to isEssential
                    ))
                }
                return true
            }
        } else if (!isListeningForHardwareKey) {
            val prefs = getSharedPreferences("glyph_native_settings", Context.MODE_PRIVATE)
            val remapEnabled = prefs.getBoolean("essential_key_remap_enabled", true)
            val targetScanCode = prefs.getInt("essential_scan_code", 250)
            val targetKeyCode = prefs.getInt("essential_key_code", 0)

            val matchesKey = isEssential ||
                (targetScanCode == 250 && scanCode == 250) ||
                (targetScanCode > 0 && scanCode == targetScanCode) ||
                (targetKeyCode > 0 && keyCode == targetKeyCode)

            if (remapEnabled && matchesKey) {
                // If GlyphAccessibilityService is actively running, it handles hardware key gestures system-wide.
                // Consuming the key here prevents dual/competing timers from running!
                if (GlyphAccessibilityService.isRunning) {
                    return true
                }
                runOnUiThread {
                    methodChannel?.invokeMethod("onEssentialKeyEvent", mapOf(
                        "action" to if (event.action == KeyEvent.ACTION_DOWN) "down" else "up",
                        "keyCode" to keyCode,
                        "scanCode" to scanCode,
                        "repeatCount" to event.repeatCount,
                        "eventTime" to event.eventTime
                    ))
                }
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        if (GlyphAccessibilityService.isRunning) return true
        val expectedComponentName = ComponentName(this, GlyphAccessibilityService::class.java).flattenToString()
        val shortName = "${packageName}/.GlyphAccessibilityService"
        val enabledServicesSetting = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServicesSetting.contains(expectedComponentName) ||
               enabledServicesSetting.contains(shortName) ||
               enabledServicesSetting.contains("GlyphAccessibilityService")
    }

    private fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun setSystemBrightness(brightness: Float, result: MethodChannel.Result) {
        runOnUiThread {
            try {
                val window = window
                val lp = window.attributes
                lp.screenBrightness = brightness.coerceIn(0.01f, 1.0f)
                window.attributes = lp
                result.success(true)
            } catch (e: Exception) {
                result.error("BRIGHTNESS_ERROR", e.message, null)
            }
        }
    }

    private fun getSystemBrightness(): Float {
        val window = window
        val lp = window.attributes
        return if (lp.screenBrightness >= 0) lp.screenBrightness else 0.5f
    }


    private fun executeKeyAction(action: String, params: Map<String, Any?>, result: MethodChannel.Result) {
        try {
            val response = KeyActionExecutor.execute(this, action, params)
            result.success(response)
        } catch (e: Exception) {
            Log.e(TAG, "Error executing key action $action: ${e.message}", e)
            result.error("ACTION_ERROR", e.message, null)
        }
    }


    override fun onDestroy() {
        if (activeInstance == this) {
            activeInstance = null
        }
        stopCurrentAnimation()
        GlyphNativeManager.removeConnectionListener(connectionListener)
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
