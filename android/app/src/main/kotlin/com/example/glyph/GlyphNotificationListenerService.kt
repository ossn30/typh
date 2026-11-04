package com.example.glyph

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.nothing.ketchum.Glyph
import com.nothing.ketchum.GlyphFrame
import org.json.JSONArray
import org.json.JSONObject

class GlyphNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "GlyphNotifListener"
        const val PREFS_RULES = "glyph_notification_rules"

        var isConnected: Boolean = false
            private set
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var playbackThread: Thread? = null
    @Volatile private var isPlayingAlert = false

    private val lastAlertTime = HashMap<String, Long>()
    private val PACKAGE_DEBOUNCE_MS = 1500L // 1.5s per package

    private data class AlertFrame(val frame: GlyphFrame?, val durationMs: Long)

    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnected = true
        Log.d(TAG, "Notification listener connected!")
        GlyphNativeManager.initIfNeeded(applicationContext)
    }

    override fun onListenerDisconnected() {
        isConnected = false
        Log.d(TAG, "Notification listener disconnected!")
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        // Ignore ongoing notifications (media playback, downloads, active calls)
        if (sbn.isOngoing) return

        val pkg = sbn.packageName ?: return
        // Ignore notifications from our own app
        if (pkg == packageName) return

        val now = System.currentTimeMillis()
        val lastTime = lastAlertTime[pkg] ?: 0L
        if (now - lastTime < PACKAGE_DEBOUNCE_MS) {
            Log.d(TAG, "Debounced notification from $pkg")
            return
        }
        lastAlertTime[pkg] = now

        Log.d(TAG, "Incoming alert from package: $pkg")
        processNotificationAlert(pkg)
    }

    private fun processNotificationAlert(pkg: String) {
        val prefs: SharedPreferences = getSharedPreferences(PREFS_RULES, Context.MODE_PRIVATE)

        // Master Switch: Are notification Glyph alerts enabled by the user?
        val areAlertsEnabled = prefs.getBoolean("alerts_enabled", false)
        if (!areAlertsEnabled) {
            Log.d(TAG, "Notification Glyph alerts are disabled in settings. Skipping playback.")
            return
        }

        // 1. Check for App-Specific Custom Animation Rule
        val appRuleJson = prefs.getString("rule_$pkg", null)

        if (appRuleJson != null && appRuleJson.isNotBlank()) {
            Log.d(TAG, "Found custom Glyph animation rule for $pkg! Playing custom animation.")
            // Play custom animation and PREVENT default one
            playAnimationJson(appRuleJson)
            return
        }

        // 2. Fallback to Default Animation if enabled
        val isDefaultEnabled = prefs.getBoolean("default_enabled", true)
        if (!isDefaultEnabled) {
            Log.d(TAG, "No rule for $pkg and default animation is disabled.")
            return
        }

        val defaultJson = prefs.getString("default_animation", null)
        if (defaultJson != null && defaultJson.isNotBlank()) {
            Log.d(TAG, "Playing default notification animation for $pkg.")
            playAnimationJson(defaultJson)
        } else {
            Log.d(TAG, "No default animation configured.")
        }
    }

    private fun stopCurrentAlertPlayback() {
        isPlayingAlert = false
        val t = playbackThread
        if (t != null && t.isAlive) {
            t.interrupt()
            try {
                t.join(250)
            } catch (_: Exception) {}
        }
        playbackThread = null
    }

    private fun playAnimationJson(jsonStr: String) {
        val gm = GlyphNativeManager.glyphManager
        if (gm == null) {
            Log.w(TAG, "GlyphManager not initialized, attempting init...")
            GlyphNativeManager.initIfNeeded(applicationContext)
            return
        }

        stopCurrentAlertPlayback()

        try {
            val root = JSONObject(jsonStr)
            val framesArr = root.optJSONArray("frames") ?: JSONArray()
            if (framesArr.length() == 0) return

            val compiled = ArrayList<AlertFrame>(framesArr.length())
            for (i in 0 until framesArr.length()) {
                val fObj = framesArr.getJSONObject(i)
                val durationMs = fObj.optLong("durationMs", 50L).coerceAtLeast(15L)
                val brightness = fObj.optInt("brightness", 4000).coerceIn(0, 4000)
                val chArr = fObj.optJSONArray("channels") ?: JSONArray()

                val frame: GlyphFrame? = if (chArr.length() == 0) {
                    null
                } else {
                    val builder = GlyphFrame.Builder(Glyph.DEVICE_24111)
                    for (j in 0 until chArr.length()) {
                        val ch = chArr.getInt(j)
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
                compiled.add(AlertFrame(frame, durationMs))
            }

            // Play the alert animation sequence (repeats 2 cycles for visibility)
            isPlayingAlert = true
            val repeatCount = 2
            val thread = Thread {
                try {
                    for (c in 0 until repeatCount) {
                        if (!isPlayingAlert || Thread.currentThread().isInterrupted) break
                        for (af in compiled) {
                            if (!isPlayingAlert || Thread.currentThread().isInterrupted) break
                            val start = System.currentTimeMillis()
                            try {
                                if (af.frame == null) {
                                    gm.turnOff()
                                } else {
                                    gm.toggle(af.frame)
                                }
                            } catch (e: Exception) {
                                Log.w(TAG, "Frame toggle error: ${e.message}")
                            }
                            val elapsed = System.currentTimeMillis() - start
                            val sleepTime = af.durationMs - elapsed
                            if (sleepTime > 0) {
                                Thread.sleep(sleepTime)
                            }
                        }
                    }
                } catch (_: InterruptedException) {
                    // Alert interrupted
                } finally {
                    try {
                        gm.turnOff()
                    } catch (_: Exception) {}
                    isPlayingAlert = false
                }
            }
            thread.priority = Thread.MAX_PRIORITY
            playbackThread = thread
            thread.start()
        } catch (e: Exception) {
            Log.e(TAG, "Error playing alert animation: ${e.message}", e)
        }
    }
}

