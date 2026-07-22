package com.recoverysense.wear.watch

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

class DataLayerService(private val context: Context) {
    fun sendSensorSnapshot(heartRate: String, acceleration: String) {
        val request = PutDataMapRequest.create("/recoverysense/sensors").apply {
            dataMap.putString("heartRate", heartRate)
            dataMap.putString("acceleration", acceleration)
            dataMap.putLong("timestamp", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()

        Wearable.getDataClient(context).putDataItem(request)
    }
}
