package edu.uci.recoverysense.wear

data class SensorReading(
    val timestamp: Long = System.currentTimeMillis(),
    val heartRate: Float = 0f,
    val accelX: Float = 0f,
    val accelY: Float = 0f,
    val accelZ: Float = 0f,
) {
    fun toJson(): String {
        return """
            {
              "timestamp": "$timestamp",
              "heartRate": $heartRate,
              "accelX": $accelX,
              "accelY": $accelY,
              "accelZ": $accelZ
            }
        """.trimIndent()
    }
}
