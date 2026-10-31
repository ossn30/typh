package com.example.glyph

import android.content.ComponentName
import android.content.Context
import android.util.Log
import com.nothing.ketchum.Glyph
import com.nothing.ketchum.GlyphManager

object GlyphNativeManager {
    private const val TAG = "GlyphNativeManager"

    var glyphManager: GlyphManager? = null
    var isServiceConnected: Boolean = false
    var isSessionOpened: Boolean = false

    private val listeners = ArrayList<(Boolean) -> Unit>()

    fun addConnectionListener(listener: (Boolean) -> Unit) {
        if (!listeners.contains(listener)) {
            listeners.add(listener)
        }
        if (isSessionOpened) {
            listener(true)
        }
    }

    fun removeConnectionListener(listener: (Boolean) -> Unit) {
        listeners.remove(listener)
    }

    @Synchronized
    fun initIfNeeded(context: Context) {
        if (glyphManager != null && isSessionOpened) return

        try {
            if (glyphManager == null) {
                glyphManager = GlyphManager.getInstance(context.applicationContext)
            }

            glyphManager?.init(object : GlyphManager.Callback {
                override fun onServiceConnected(componentName: ComponentName?) {
                    Log.d(TAG, "Ketchum Service Connected: $componentName")
                    isServiceConnected = true
                    try {
                        val reg = glyphManager?.register(Glyph.DEVICE_24111) ?: false
                        Log.d(TAG, "Registered DEVICE_24111: $reg")
                        glyphManager?.openSession()
                        isSessionOpened = true
                        Log.d(TAG, "Glyph Session Opened.")
                        for (l in ArrayList(listeners)) {
                            l(true)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error opening glyph session: ${e.message}", e)
                    }
                }

                override fun onServiceDisconnected(componentName: ComponentName?) {
                    Log.d(TAG, "Ketchum Service Disconnected: $componentName")
                    isServiceConnected = false
                    isSessionOpened = false
                    for (l in ArrayList(listeners)) {
                        l(false)
                    }
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "initIfNeeded error: ${e.message}", e)
        }
    }
}

