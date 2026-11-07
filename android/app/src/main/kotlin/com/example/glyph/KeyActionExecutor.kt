package com.example.glyph

import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.AlarmClock
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.util.Log
import com.nothing.ketchum.Glyph
import com.nothing.ketchum.GlyphFrame
import java.util.Locale

object KeyActionExecutor {
    private const val TAG = "TYPH_KeyActionExecutor"
    private var tts: TextToSpeech? = null

    @Volatile
    var isTorchActive: Boolean = false

    fun toggleTorch(context: Context): Boolean {
        isTorchActive = !isTorchActive
        val state = isTorchActive
        Log.d(TAG, "Toggling torch to state: $state")

        // 1. Toggle camera hardware flashlight (system-wide reliable)
        try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            if (cm != null) {
                val cameraId = cm.cameraIdList.firstOrNull { id ->
                    val chars = cm.getCameraCharacteristics(id)
                    chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                } ?: cm.cameraIdList.firstOrNull()
                if (cameraId != null) {
                    cm.setTorchMode(cameraId, state)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Camera torch error: ${e.message}")
        }

        // 2. Toggle Nothing rear Glyph LEDs (Ketchum SDK)
        try {
            GlyphNativeManager.initIfNeeded(context.applicationContext)
            val gm = GlyphNativeManager.glyphManager
            if (gm != null && GlyphNativeManager.isSessionOpened) {
                if (state) {
                    val prefs = context.getSharedPreferences("glyph_native_settings", Context.MODE_PRIVATE)
                    val brightness = prefs.getInt("torch_brightness", 4000).coerceIn(0, 4000)
                    val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
                    if (brightness == 4000) {
                        builder.buildChannelA().buildChannelB().buildChannelC()
                    } else {
                        for (ch in 0..35) builder.buildChannel(ch, brightness)
                    }
                    gm.toggle(builder.build())
                } else {
                    gm.turnOff()
                }
            } else {
                GlyphNativeManager.addConnectionListener { connected ->
                    if (connected) {
                        try {
                            val activeGm = GlyphNativeManager.glyphManager
                            if (isTorchActive) {
                                val prefs = context.getSharedPreferences("glyph_native_settings", Context.MODE_PRIVATE)
                                val brightness = prefs.getInt("torch_brightness", 4000).coerceIn(0, 4000)
                                val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
                                if (brightness == 4000) {
                                    builder.buildChannelA().buildChannelB().buildChannelC()
                                } else {
                                    for (ch in 0..35) builder.buildChannel(ch, brightness)
                                }
                                activeGm?.toggle(builder.build())
                            } else {
                                activeGm?.turnOff()
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Deferred torch toggle error: ${e.message}")
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Glyph torch error: ${e.message}")
        }

        // 3. Keep GlyphBackgroundService instance state in sync
        try {
            GlyphBackgroundService.instance?.let { bg ->
                bg.isTorchOn = state
            }
        } catch (_: Exception) {}

        return state
    }

    fun vibrate(context: Context, durationMs: Long = 70L) {
        try {
            val v = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v?.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                v?.vibrate(durationMs)
            }
        } catch (_: Exception) {}
    }

    fun execute(context: Context, action: String, params: Map<String, Any?> = emptyMap()): Map<String, Any> {
        vibrate(context, 60L)
        Log.d(TAG, "Executing key action: $action")

        return try {
            when (action) {
                "torch" -> {
                    val state = toggleTorch(context)
                    mapOf("status" to "success", "torchOn" to state, "message" to if (state) "Torch: ON" else "Torch: OFF")
                }
                "rotation_lock" -> {
                    try {
                        val cr = context.contentResolver
                        val current = Settings.System.getInt(cr, Settings.System.ACCELEROMETER_ROTATION, 1)
                        val newState = if (current == 1) 0 else 1
                        val canWrite = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.System.canWrite(context) else true
                        if (canWrite) {
                            Settings.System.putInt(cr, Settings.System.ACCELEROMETER_ROTATION, newState)
                            mapOf("status" to "success", "state" to (newState == 1), "message" to if (newState == 1) "Auto-rotate: ON" else "Rotation: LOCKED")
                        } else {
                            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                                data = android.net.Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            mapOf("status" to "permission_needed", "message" to "Grant Write Settings permission")
                        }
                    } catch (_: Exception) {
                        val intent = Intent(Settings.ACTION_DISPLAY_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                        mapOf("status" to "opened_settings", "message" to "Display Settings opened")
                    }
                }
                "auto_brightness" -> {
                    try {
                        val cr = context.contentResolver
                        val current = Settings.System.getInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
                        val newMode = if (current == Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC) Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL else Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC
                        val canWrite = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.System.canWrite(context) else true
                        if (canWrite) {
                            Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE, newMode)
                            mapOf("status" to "success", "auto" to (newMode == Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC), "message" to if (newMode == Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC) "Auto Brightness: ON" else "Auto Brightness: OFF")
                        } else {
                            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
                                data = android.net.Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            mapOf("status" to "permission_needed", "message" to "Grant Write Settings permission")
                        }
                    } catch (e: Exception) {
                        mapOf("status" to "error", "message" to (e.message ?: "Error"))
                    }
                }
                "ringer_mode" -> {
                    val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    val canChangeDnd = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) nm.isNotificationPolicyAccessGranted else true
                    val currentMode = am.ringerMode
                    val (newMode, label) = when (currentMode) {
                        AudioManager.RINGER_MODE_NORMAL -> Pair(AudioManager.RINGER_MODE_VIBRATE, "VIBRATE")
                        AudioManager.RINGER_MODE_VIBRATE -> if (canChangeDnd) Pair(AudioManager.RINGER_MODE_SILENT, "SILENT") else Pair(AudioManager.RINGER_MODE_NORMAL, "RING")
                        else -> Pair(AudioManager.RINGER_MODE_NORMAL, "RING")
                    }
                    try {
                        am.ringerMode = newMode
                        mapOf("status" to "success", "mode" to label, "message" to "Ringer: $label")
                    } catch (_: Exception) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !nm.isNotificationPolicyAccessGranted) {
                            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                            context.startActivity(intent)
                        }
                        mapOf("status" to "permission_needed", "message" to "Grant DND permission")
                    }
                }
                "dnd" -> {
                    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (nm.isNotificationPolicyAccessGranted) {
                            val current = nm.currentInterruptionFilter
                            val newFilter = if (current == NotificationManager.INTERRUPTION_FILTER_ALL) NotificationManager.INTERRUPTION_FILTER_PRIORITY else NotificationManager.INTERRUPTION_FILTER_ALL
                            nm.setInterruptionFilter(newFilter)
                            val isDnd = newFilter != NotificationManager.INTERRUPTION_FILTER_ALL
                            mapOf("status" to "success", "dnd" to isDnd, "message" to if (isDnd) "Do Not Disturb: ON" else "Do Not Disturb: OFF")
                        } else {
                            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                            context.startActivity(intent)
                            mapOf("status" to "permission_needed", "message" to "Grant DND permission")
                        }
                    } else {
                        mapOf("status" to "not_supported", "message" to "Not supported")
                    }
                }
                "voice_assistant" -> {
                    try {
                        val intent = Intent(Intent.ACTION_VOICE_COMMAND).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                        mapOf("status" to "success", "message" to "Voice Assistant launched")
                    } catch (_: Exception) {
                        try {
                            val assistIntent = Intent(Intent.ACTION_ASSIST).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                            context.startActivity(assistIntent)
                            mapOf("status" to "success", "message" to "Assistant opened")
                        } catch (e: Exception) {
                            mapOf("status" to "error", "message" to (e.message ?: "Assistant unavailable"))
                        }
                    }
                }
                "lock_screen" -> {
                    val acc = GlyphAccessibilityService.instance
                    if (acc != null) {
                        val locked = acc.performLockScreen()
                        mapOf("status" to if (locked) "success" else "failed", "message" to "Screen locked")
                    } else {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                        mapOf("status" to "accessibility_required", "message" to "Enable Accessibility Service to lock screen")
                    }
                }
                "wake_screen" -> {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    @Suppress("DEPRECATION")
                    val wl = pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "glyph:wake")
                    wl.acquire(2000)
                    mapOf("status" to "success", "message" to "Screen waking up")
                }
                "brightness_slider" -> {
                    mapOf("status" to "success", "message" to "Brightness Slider")
                }
                "night_light" -> {
                    try {
                        val intent = Intent(Settings.ACTION_NIGHT_DISPLAY_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                    } catch (_: Exception) {
                        val intent = Intent(Settings.ACTION_DISPLAY_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                    }
                    mapOf("status" to "success", "message" to "Night Light opened")
                }
                "extra_dim" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                    context.startActivity(intent)
                    mapOf("status" to "success", "message" to "Extra Dim opened")
                }
                "internet_panel" -> {
                    try {
                        val intent = Intent("android.settings.panel.action.INTERNET_CONNECTIVITY").apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                        mapOf("status" to "success", "message" to "Internet panel opened")
                    } catch (_: Exception) {
                        val intent = Intent(Settings.ACTION_WIRELESS_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                        mapOf("status" to "success", "message" to "Wireless settings opened")
                    }
                }
                "bluetooth_panel" -> {
                    try {
                        val intent = Intent("android.settings.panel.action.BLUETOOTH").apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                        mapOf("status" to "success", "message" to "Bluetooth panel opened")
                    } catch (_: Exception) {
                        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                        mapOf("status" to "success", "message" to "Bluetooth settings opened")
                    }
                }
                "volume_panel" -> {
                    val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    am.adjustVolume(AudioManager.ADJUST_SAME, AudioManager.FLAG_SHOW_UI)
                    try {
                        val intent = Intent("android.settings.panel.action.VOLUME").apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                    } catch (_: Exception) {}
                    mapOf("status" to "success", "message" to "Volume panel displayed")
                }
                "power_menu" -> {
                    val acc = GlyphAccessibilityService.instance
                    if (acc != null) {
                        acc.performPowerMenu()
                        mapOf("status" to "success", "message" to "Power menu opened")
                    } else {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        context.startActivity(intent)
                        mapOf("status" to "accessibility_required", "message" to "Enable Accessibility Service for Power Dialog")
                    }
                }
                "set_timer" -> {
                    try {
                        val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                            putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        mapOf("status" to "success", "message" to "Timer opened")
                    } catch (_: Exception) {
                        try {
                            val clockIntent = Intent(AlarmClock.ACTION_SHOW_ALARMS).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                            context.startActivity(clockIntent)
                            mapOf("status" to "success", "message" to "Clock opened")
                        } catch (e: Exception) {
                            mapOf("status" to "error", "message" to (e.message ?: "Timer unavailable"))
                        }
                    }
                }
                "read_aloud" -> {
                    val textToRead = params["text"] as? String ?: run {
                        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cm.primaryClip?.getItemAt(0)?.text?.toString() ?: "No text selected or in clipboard"
                    }
                    speakText(context, textToRead)
                    mapOf("status" to "success", "text" to textToRead, "message" to "Reading aloud text")
                }
                "copy_text" -> {
                    val textToCopy = params["text"] as? String ?: "Copied via Essential Key"
                    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("GlyphCopy", textToCopy))
                    mapOf("status" to "success", "message" to "Text copied to clipboard")
                }
                "paste_text" -> {
                    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val text = cm.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
                    mapOf("status" to "success", "text" to text, "message" to if (text.isNotEmpty()) "Pasted from clipboard" else "Clipboard empty")
                }
                "calculator" -> {
                    val pm = context.packageManager
                    val calcIntent = pm.getLaunchIntentForPackage("com.google.android.calculator")
                        ?: pm.getLaunchIntentForPackage("com.nothing.calculator")
                        ?: pm.getLaunchIntentForPackage("com.android.calculator2")
                        ?: Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_CALCULATOR)
                    calcIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    context.startActivity(calcIntent)
                    mapOf("status" to "success", "message" to "Calculator launched")
                }
                else -> {
                    mapOf("status" to "ignored", "action" to action)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error executing key action $action: ${e.message}", e)
            mapOf("status" to "error", "message" to (e.message ?: "Error"))
        }
    }

    private fun speakText(context: Context, text: String) {
        try {
            if (tts == null) {
                tts = TextToSpeech(context.applicationContext) { status ->
                    if (status == TextToSpeech.SUCCESS) {
                        tts?.language = Locale.getDefault()
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "read_aloud_id")
                    }
                }
            } else {
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "read_aloud_id")
            }
        } catch (e: Exception) {
            Log.e(TAG, "TTS speak error: ${e.message}")
        }
    }
}

