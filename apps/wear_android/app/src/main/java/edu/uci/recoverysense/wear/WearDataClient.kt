package edu.uci.recoverysense.wear

import android.content.Context
import com.google.android.gms.wearable.Wearable

class WearDataClient(private val context: Context) {
    private val nodeClient = Wearable.getNodeClient(context)
    private val messageClient = Wearable.getMessageClient(context)

    fun sendSensorReading(reading: SensorReading) {
        nodeClient.connectedNodes.addOnSuccessListener { nodes ->
            nodes.forEach { node ->
                messageClient.sendMessage(
                    node.id,
                    WearMessagePaths.SENSOR_READING,
                    reading.toJson().toByteArray(),
                )
            }
        }
    }
}
