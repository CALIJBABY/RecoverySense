package com.recoverysense.wear.sleep

import android.content.Intent
import androidx.core.content.ContextCompat
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/** Receives sleep-mode commands while the unified foreground recorder stays active. */
class SleepCommandListenerService : WearableListenerService() {
    override fun onMessageReceived(messageEvent: MessageEvent) {
        when (messageEvent.path) {
            SleepTrackingService.START_MESSAGE_PATH -> {
                val sessionId = messageEvent.data.toString(Charsets.UTF_8).trim()
                if (sessionId.isBlank()) return
                val intent = Intent(this, SleepTrackingService::class.java)
                    .setAction(SleepTrackingService.ACTION_START_SLEEP)
                    .putExtra(SleepTrackingService.EXTRA_SLEEP_SESSION_ID, sessionId)
                ContextCompat.startForegroundService(this, intent)
            }

            SleepTrackingService.STOP_MESSAGE_PATH -> {
                ContextCompat.startForegroundService(
                    this,
                    Intent(this, SleepTrackingService::class.java)
                        .setAction(SleepTrackingService.ACTION_STOP_SLEEP),
                )
            }
        }
    }
}
