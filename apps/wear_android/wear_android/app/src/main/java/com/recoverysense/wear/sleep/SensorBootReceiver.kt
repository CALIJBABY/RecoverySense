package com.recoverysense.wear.sleep

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/** Restarts an explicitly enabled recorder after a watch reboot or app update. */
class SensorBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val supportedAction = intent?.action == Intent.ACTION_BOOT_COMPLETED ||
            intent?.action == Intent.ACTION_MY_PACKAGE_REPLACED
        if (!supportedAction || !SleepTrackingService.isActive(context)) return
        try {
            // No action is supplied: the service restores the persisted daytime
            // or sleep mode instead of always replacing it with daytime mode.
            ContextCompat.startForegroundService(
                context,
                Intent(context, SleepTrackingService::class.java),
            )
        } catch (error: SecurityException) {
            // Android can block a health FGS at boot if background health access
            // was not granted. Opening the watch app requests access and restarts.
            Log.w(TAG, "Recorder will resume when RecoverySense is opened", error)
        }
    }

    private companion object {
        const val TAG = "RecoverySenseBoot"
    }
}
