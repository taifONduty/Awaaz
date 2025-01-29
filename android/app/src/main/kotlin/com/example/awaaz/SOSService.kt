// android/app/src/main/kotlin/com/example/awaaz/SOSService.kt

package com.example.awaaz

import android.app.Service
import android.content.Intent
import android.content.IntentFilter
import android.os.IBinder
import android.content.BroadcastReceiver
import android.content.Context

class SOSService : Service() {
    private var powerButtonCount = 0
    private var lastPressTime: Long = 0
    private val POWER_BUTTON_TIMEOUT = 3000 // 3 seconds timeout
    private val REQUIRED_PRESSES = 3 // Number of presses required

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastPressTime > POWER_BUTTON_TIMEOUT) {
                    powerButtonCount = 1
                } else {
                    powerButtonCount++
                }
                lastPressTime = currentTime

                if (powerButtonCount >= REQUIRED_PRESSES) {
                    triggerSOS()
                    powerButtonCount = 0
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        registerReceiver(screenReceiver, filter)
    }

    private fun triggerSOS() {
        // Send broadcast to Flutter app
        val intent = Intent("com.example.awaaz.SOS_TRIGGERED")
        sendBroadcast(intent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(screenReceiver)
    }
}