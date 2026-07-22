package com.recoverysense.wear

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.recoverysense.wear.sensors.HeartRateSensorService
import com.recoverysense.wear.sensors.MotionSensorService
import com.recoverysense.wear.watch.DataLayerService

class MainActivity : ComponentActivity() {
    private lateinit var heartRateService: HeartRateSensorService
    private lateinit var motionSensorService: MotionSensorService
    private lateinit var dataLayerService: DataLayerService

    private var heartRateText by mutableStateOf("--")
    private var accelText by mutableStateOf("--")
    private var statusText by mutableStateOf("Starting")

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            startSensors()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        heartRateService = HeartRateSensorService(this) { bpm ->
            heartRateText = if (bpm > 0) bpm.toInt().toString() else "--"
            sendSnapshot()
        }

        motionSensorService = MotionSensorService(this) { x, y, z ->
            val magnitude = kotlin.math.sqrt((x * x + y * y + z * z).toDouble())
            accelText = "%.2f g".format(magnitude)
            sendSnapshot()
        }

        dataLayerService = DataLayerService(this)

        setContent {
            RecoverySenseWearScreen(
                heartRate = heartRateText,
                accel = accelText,
                status = statusText
            )
        }

        permissionLauncher.launch(
            arrayOf(
                Manifest.permission.BODY_SENSORS,
                Manifest.permission.ACTIVITY_RECOGNITION
            )
        )
    }

    private fun startSensors() {
        statusText = "Listening"
        heartRateService.start()
        motionSensorService.start()
    }

    private fun sendSnapshot() {
        dataLayerService.sendSensorSnapshot(
            heartRate = heartRateText,
            acceleration = accelText
        )
    }

    override fun onDestroy() {
        heartRateService.stop()
        motionSensorService.stop()
        super.onDestroy()
    }
}

@Composable
fun RecoverySenseWearScreen(
    heartRate: String,
    accel: String,
    status: String
) {
    val background = Color(0xFFE7F3E4)
    val darkGreen = Color(0xFF2F5D3A)

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(background),
        contentAlignment = Alignment.TopCenter
    ) {
        // Automatically adjust for smaller watch displays.
        val compactScreen = maxWidth < 210.dp

        val horizontalPadding = if (compactScreen) 24.dp else 28.dp
        val topPadding = if (compactScreen) 18.dp else 22.dp
        val titleSize = if (compactScreen) 16.sp else 18.sp
        val valueSize = if (compactScreen) 16.sp else 18.sp

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(
                    start = horizontalPadding,
                    end = horizontalPadding,
                    top = topPadding,
                    bottom = 24.dp
                ),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "RecoverySense",
                color = Color.Black,
                fontSize = titleSize,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 1
            )

            Spacer(modifier = Modifier.height(8.dp))

            WearMetricCard(
                title = "Heart Rate",
                value = "$heartRate bpm",
                color = darkGreen,
                valueSize = valueSize
            )

            WearMetricCard(
                title = "Acceleration",
                value = accel,
                color = darkGreen,
                valueSize = valueSize
            )

            WearMetricCard(
                title = "Status",
                value = status,
                color = darkGreen,
                valueSize = valueSize
            )

            // Keeps the last card away from the curved bottom edge.
            Spacer(modifier = Modifier.height(18.dp))
        }
    }
}

@Composable
fun WearMetricCard(
    title: String,
    value: String,
    color: Color,
    valueSize: androidx.compose.ui.unit.TextUnit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White)
            .padding(
                horizontal = 8.dp,
                vertical = 7.dp
            ),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = title,
            color = Color.Black,
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            maxLines = 1
        )

        Spacer(modifier = Modifier.height(2.dp))

        Text(
            text = value,
            color = color,
            fontSize = valueSize,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            maxLines = 1
        )
    }
}