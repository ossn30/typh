package com.example.glyph

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import com.nothing.ketchum.Glyph
import com.nothing.ketchum.GlyphFrame

class GlyphBackgroundService : Service(), SensorEventListener {

    companion object {
        private const val TAG = "GlyphBackgroundService"
        private const val CHANNEL_ID = "glyph_background_service_channel"
        private const val NOTIFICATION_ID = 1001
        private const val PREFS_NAME = "glyph_native_settings"

        var instance: GlyphBackgroundService? = null
            private set
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isTorchOn = false
    private var lastShakeTimestamp = 0L
    private val SHAKE_DEBOUNCE_MS = 650L

    // Sensors
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var isSensorRegistered = false

    // Charging Animation Timer
    private val chargingTurnOffRunnable = Runnable {
        try {
            GlyphNativeManager.glyphManager?.turnOff()
        } catch (e: Exception) {
            Log.w(TAG, "Error turning off charging glyph: ${e.message}")
        }
    }

    // Battery Receiver
    private val batteryReceiver = object : BroadcastReceiver() {
        private var wasCharging = false
        private var lastReportedPercent = -1

        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            val action = intent.action

            val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            val isNowCharging = (action != Intent.ACTION_POWER_DISCONNECTED) &&
                                (status == BatteryManager.BATTERY_STATUS_CHARGING ||
                                 status == BatteryManager.BATTERY_STATUS_FULL ||
                                 action == Intent.ACTION_POWER_CONNECTED)

            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val percent = if (level >= 0 && scale > 0) (level * 100 / scale) else 0

            Log.d(TAG, "Battery status update: isCharging=$isNowCharging, percent=$percent, action=$action, wasCharging=$wasCharging, lastReported=$lastReportedPercent")

            if (isNowCharging) {
                // Trigger charging animation whenever newly plugged in OR whenever battery percentage updates
                if (!wasCharging || percent != lastReportedPercent) {
                    wasCharging = true
                    lastReportedPercent = percent
                    triggerChargingAnimation(percent)
                }
            } else if (wasCharging) {
                // Just unplugged! Turn off charging animation
                wasCharging = false
                lastReportedPercent = -1
                mainHandler.removeCallbacks(chargingTurnOffRunnable)
                try {
                    if (!isTorchOn) {
                        GlyphNativeManager.glyphManager?.turnOff()
                    }
                } catch (_: Exception) {}
            }
        }
    }
    private var isBatteryReceiverRegistered = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "GlyphBackgroundService onCreate")

        startForegroundNotification()
        GlyphNativeManager.initIfNeeded(applicationContext)

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        registerBatteryMonitor()
        syncSensorState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "GlyphBackgroundService onStartCommand")
        startForegroundNotification()
        GlyphNativeManager.initIfNeeded(applicationContext)
        syncSensorState()
        return START_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "GlyphBackgroundService onDestroy")
        instance = null
        unregisterBatteryMonitor()
        unregisterSensor()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundNotification() {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val channel = NotificationChannel(
                CHANNEL_ID,
                "Glyph Hardware Service",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Monitors Glyph gestures and charging status in background"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)

            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val notification = Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Glyph Active")
                .setContentText("Charging animations & gesture torch ready")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground notification: ${e.message}", e)
        }
    }

    private fun registerBatteryMonitor() {
        if (!isBatteryReceiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_BATTERY_CHANGED)
                addAction(Intent.ACTION_POWER_CONNECTED)
                addAction(Intent.ACTION_POWER_DISCONNECTED)
            }
            registerReceiver(batteryReceiver, filter)
            isBatteryReceiverRegistered = true
        }
    }

    private fun unregisterBatteryMonitor() {
        if (isBatteryReceiverRegistered) {
            try {
                unregisterReceiver(batteryReceiver)
            } catch (_: Exception) {}
            isBatteryReceiverRegistered = false
        }
    }

    fun syncSensorState() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val shakeTorchEnabled = prefs.getBoolean("shake_torch_enabled", false)

        if (shakeTorchEnabled && !isSensorRegistered) {
            accelerometer?.let {
                sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
                isSensorRegistered = true
                Log.d(TAG, "Accelerometer listener registered for shake torch")
            }
        } else if (!shakeTorchEnabled && isSensorRegistered) {
            unregisterSensor()
        }
    }

    private fun unregisterSensor() {
        if (isSensorRegistered) {
            sensorManager?.unregisterListener(this)
            isSensorRegistered = false
            Log.d(TAG, "Accelerometer listener unregistered")
        }
    }

    // --- Shake Detection ---
    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            val x = event.values[0] / SensorManager.GRAVITY_EARTH
            val y = event.values[1] / SensorManager.GRAVITY_EARTH
            val z = event.values[2] / SensorManager.GRAVITY_EARTH
            val gForce = Math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()

            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val threshold = prefs.getFloat("shake_threshold", 2.0f)

            if (gForce >= threshold) {
                val now = System.currentTimeMillis()
                if (now - lastShakeTimestamp > SHAKE_DEBOUNCE_MS) {
                    lastShakeTimestamp = now
                    Log.d(TAG, "Background shake detected! gForce=$gForce, threshold=$threshold")
                    toggleTorch()
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun toggleTorch() {
        val gm = GlyphNativeManager.glyphManager
        if (gm == null) {
            Log.w(TAG, "Cannot toggle torch: GlyphManager is null")
            return
        }

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val brightness = prefs.getInt("torch_brightness", 4000).coerceIn(0, 4000)

        if (isTorchOn) {
            isTorchOn = false
            try {
                gm.turnOff()
                vibratePhone(40)
            } catch (e: Exception) {
                Log.e(TAG, "Error turning off torch: ${e.message}")
            }
        } else {
            isTorchOn = true
            try {
                val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
                for (ch in 0..35) {
                    builder.buildChannel(ch, brightness)
                }
                gm.toggle(builder.build())
                vibratePhone(70)
            } catch (e: Exception) {
                Log.e(TAG, "Error turning on torch: ${e.message}")
            }
        }
    }

    private fun vibratePhone(durationMs: Long) {
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(durationMs)
            }
        } catch (_: Exception) {}
    }

    fun refreshChargingAnimation() {
        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val isChargingNow = bm?.isCharging ?: false
        val currentPercent = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        if (isChargingNow && currentPercent >= 0) {
            triggerChargingAnimation(currentPercent)
        }
    }

    // --- Charging Animation ---
    fun triggerChargingAnimation(percentage: Int) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("charging_enabled", true)
        if (!enabled) {
            Log.d(TAG, "Charging animation disabled in settings")
            return
        }

        if (isTorchOn) {
            Log.d(TAG, "Torch is currently active, skipping charging animation update")
            return
        }

        val gm = GlyphNativeManager.glyphManager
        if (gm == null || !GlyphNativeManager.isSessionOpened) {
            Log.w(TAG, "GlyphManager not opened yet, will trigger charging animation once connected")
            GlyphNativeManager.initIfNeeded(applicationContext)
            lateinit var sessionCallback: (Boolean) -> Unit
            sessionCallback = { opened ->
                if (opened) {
                    GlyphNativeManager.removeConnectionListener(sessionCallback)
                    triggerChargingAnimation(percentage)
                }
            }
            GlyphNativeManager.addConnectionListener(sessionCallback)
            return
        }

        val selectedArcs = prefs.getStringSet("selected_arcs", setOf("C")) ?: setOf("C")
        val isClockwise = prefs.getBoolean("is_clockwise", true)
        val isCombined = prefs.getBoolean("is_combined", true)
        val isDurationAlways = prefs.getBoolean("is_duration_always", true)
        val timerDurationSeconds = prefs.getInt("timer_duration", 3)
        val brightness = prefs.getInt("charging_brightness", 4000).coerceIn(0, 4000)

        val channels = computeChargingChannels(percentage, selectedArcs, isClockwise, isCombined)
        Log.d(TAG, "Displaying charging animation: $percentage% -> ${channels.size} LEDs at $brightness brightness (always=$isDurationAlways)")

        mainHandler.removeCallbacks(chargingTurnOffRunnable)

        try {
            if (channels.isEmpty()) {
                gm.turnOff()
            } else {
                val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
                for (ch in channels) {
                    if (brightness == 4000) {
                        builder.buildChannel(ch)
                    } else {
                        builder.buildChannel(ch, brightness)
                    }
                }
                gm.toggle(builder.build())

                if (!isDurationAlways) {
                    mainHandler.postDelayed(chargingTurnOffRunnable, timerDurationSeconds * 1000L)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error triggering charging animation: ${e.message}", e)
        }
    }

    private fun computeChargingChannels(
        percent: Int,
        selectedArcs: Set<String>,
        isClockwise: Boolean,
        isCombined: Boolean
    ): Set<Int> {
        if (selectedArcs.isEmpty() || percent <= 0) return emptySet()
        val clamped = percent.coerceIn(0, 100)

        // Arc C (20 LEDs: 0..19, upper-left)
        val arcCCw = (0..19).toList()
        val arcCAcw = (19 downTo 0).toList()

        // Arc A (11 LEDs: 20..30, right)
        val arcACw = (20..30).toList()
        val arcAAcw = (30 downTo 20).toList()

        // Arc B (5 LEDs: 31..35, lower-left)
        val arcBCw = (31..35).toList()
        val arcBAcw = (35 downTo 31).toList()

        val result = HashSet<Int>()

        if (isCombined) {
            val combined = ArrayList<Int>()
            if (isClockwise) {
                // Natural clockwise flow: Arc C (upper-left) -> Arc A (right) -> Arc B (lower-left)
                if (selectedArcs.contains("C")) combined.addAll(arcCCw)
                if (selectedArcs.contains("A")) combined.addAll(arcACw)
                if (selectedArcs.contains("B")) combined.addAll(arcBCw)
            } else {
                // Natural anticlockwise flow: Arc B (lower-left) -> Arc A (right) -> Arc C (upper-left)
                if (selectedArcs.contains("B")) combined.addAll(arcBAcw)
                if (selectedArcs.contains("A")) combined.addAll(arcAAcw)
                if (selectedArcs.contains("C")) combined.addAll(arcCAcw)
            }

            if (combined.isNotEmpty()) {
                val count = Math.ceil(combined.size * clamped / 100.0).toInt().coerceIn(1, combined.size)
                for (i in 0 until count) {
                    result.add(combined[i])
                }
            }
        } else {
            if (selectedArcs.contains("C")) {
                val list = if (isClockwise) arcCCw else arcCAcw
                val count = Math.ceil(list.size * clamped / 100.0).toInt().coerceIn(1, list.size)
                for (i in 0 until count) result.add(list[i])
            }
            if (selectedArcs.contains("A")) {
                val list = if (isClockwise) arcACw else arcAAcw
                val count = Math.ceil(list.size * clamped / 100.0).toInt().coerceIn(1, list.size)
                for (i in 0 until count) result.add(list[i])
            }
            if (selectedArcs.contains("B")) {
                val list = if (isClockwise) arcBCw else arcBAcw
                val count = Math.ceil(list.size * clamped / 100.0).toInt().coerceIn(1, list.size)
                for (i in 0 until count) result.add(list[i])
            }
        }

        return result
    }
}

