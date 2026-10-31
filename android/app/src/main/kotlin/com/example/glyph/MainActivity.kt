package com.example.glyph

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
    private var mGM: GlyphManager? = null
    private var mCallback: GlyphManager.Callback? = null
    private var isServiceConnected = false
    private var isSessionOpened = false
    private var methodChannel: MethodChannel? = null

    // Battery & Charging tracking
    private var isCharging = false
    private var batteryLevel = 0
    private var batteryReceiverRegistered = false

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
            "isServiceConnected" to isServiceConnected,
            "isSessionOpened" to isSessionOpened
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

    private fun initGlyph(result: MethodChannel.Result) {
        try {
            if (mGM == null) {
                mGM = GlyphManager.getInstance(applicationContext)
            }

            mCallback = object : GlyphManager.Callback {
                override fun onServiceConnected(componentName: ComponentName?) {
                    Log.d(TAG, "onServiceConnected: $componentName")
                    isServiceConnected = true

                    try {
                        val regSuccess = mGM?.register(Glyph.DEVICE_24111) ?: false
                        Log.d(TAG, "Registered DEVICE_24111: $regSuccess")

                        mGM?.openSession()
                        isSessionOpened = true
                        Log.d(TAG, "Glyph session opened successfully.")
                    } catch (e: GlyphException) {
                        Log.e(TAG, "GlyphException opening session: ${e.message}", e)
                    } catch (e: Exception) {
                        Log.e(TAG, "Exception opening session: ${e.message}", e)
                    }

                    notifyStatusToFlutter()
                }

                override fun onServiceDisconnected(componentName: ComponentName?) {
                    Log.d(TAG, "onServiceDisconnected: $componentName")
                    isServiceConnected = false
                    isSessionOpened = false
                    try {
                        mGM?.closeSession()
                    } catch (e: Exception) {
                        Log.e(TAG, "Error closing session on disconnect: ${e.message}")
                    }
                    notifyStatusToFlutter()
                }
            }

            mGM?.init(mCallback)
            result.success(getDeviceStatusMap())
        } catch (e: Exception) {
            Log.e(TAG, "initGlyph failed: ${e.message}", e)
            result.error("INIT_FAILED", e.message, null)
        }
    }

    private fun toggleChannels(channels: List<Int>, brightness: Int, result: MethodChannel.Result) {
        val gm = mGM
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
        val gm = mGM
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
        val gm = mGM
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
        val gm = mGM
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
        try {
            mGM?.turnOff()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "turnOff error: ${e.message}", e)
            result.error("TURNOFF_ERROR", e.message, null)
        }
    }

    private fun closeSession(result: MethodChannel.Result) {
        try {
            mGM?.closeSession()
            isSessionOpened = false
            notifyStatusToFlutter()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "closeSession error: ${e.message}", e)
            result.error("CLOSE_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        if (batteryReceiverRegistered) {
            try {
                unregisterReceiver(batteryReceiver)
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering batteryReceiver: ${e.message}")
            }
            batteryReceiverRegistered = false
        }
        try {
            mGM?.turnOff()
            if (isSessionOpened) {
                mGM?.closeSession()
                isSessionOpened = false
            }
        } catch (e: Exception) {
            Log.e(TAG, "onDestroy cleanup error: ${e.message}")
        }
        try {
            mGM?.unInit()
            mGM = null
        } catch (e: Exception) {
            Log.e(TAG, "onDestroy unInit error: ${e.message}")
        }
        super.onDestroy()
    }
}
