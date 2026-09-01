package com.recoverysense.wear

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.recoverysense.wear.ppg.PpgFeatureFlags
import com.recoverysense.wear.sleep.SleepTrackingService
import com.recoverysense.wear.watch.DataLayerService
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Participant-facing sensor summary plus the required watch micro-EMA.
 *
 * Sensor ownership lives in the foreground service so collection continues
 * after the display turns off. EMA responses are queued through the Wear Data
 * Layer and upload to Firestore when the paired phone is available and signed
 * in.
 */
class MainActivity : ComponentActivity() {
    private var heartRateText by mutableStateOf("--")
    private var accelText by mutableStateOf("--")
    private var gyroText by mutableStateOf("--")
    private var stepsText by mutableStateOf("--")
    private var emaScore by mutableIntStateOf(5)
    private var emaSelectionMade by mutableStateOf(false)
    private var emaStatusText by mutableStateOf("0 none · 10 extreme")
    private var emaInteractionStartedAtMs: Long? = null

    private val statusHandler = Handler(Looper.getMainLooper())
    private val statusPoll = object : Runnable {
        override fun run() {
            updateFromServiceStatus()
            statusHandler.postDelayed(this, 1_000L)
        }
    }

    private val backgroundPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            startContinuousTrackingService()
        }

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            requestBackgroundHeartRatePermissionOrStart()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            RecoverySenseWearScreen(
                heartRate = heartRateText,
                accel = accelText,
                gyro = gyroText,
                steps = stepsText,
                emaScore = emaScore,
                emaStatus = emaStatusText,
                emaSelectionMade = emaSelectionMade,
                onEmaScoreChanged = { value ->
                    if (emaInteractionStartedAtMs == null) {
                        emaInteractionStartedAtMs = System.currentTimeMillis()
                    }
                    emaScore = value.coerceIn(0, 10)
                    emaSelectionMade = true
                    emaStatusText = "0 none · 10 extreme"
                },
                onSubmitEma = ::submitWatchEma,
            )
        }
        requestInitialPermissions()
        statusHandler.post(statusPoll)
    }

    private fun requestInitialPermissions() {
        val permissions = linkedSetOf<String>()
        permissions += heartRatePermission()

        // PPG permission is deliberately not requested until Samsung SDK access
        // is available. Set PpgFeatureFlags.ENABLED to true after adding the AAR.
        if (PpgFeatureFlags.ENABLED) {
            permissions += ppgPermission()
        }

        permissions += Manifest.permission.ACTIVITY_RECOGNITION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.POST_NOTIFICATIONS
        }
        permissionLauncher.launch(permissions.toTypedArray())
    }

    private fun heartRatePermission(): String =
        if (Build.VERSION.SDK_INT >= 36) {
            SleepTrackingService.READ_HEART_RATE_PERMISSION
        } else {
            Manifest.permission.BODY_SENSORS
        }

    private fun ppgPermission(): String =
        if (Build.VERSION.SDK_INT >= 36) {
            SleepTrackingService.READ_ADDITIONAL_HEALTH_DATA_PERMISSION
        } else {
            Manifest.permission.BODY_SENSORS
        }

    private fun backgroundHeartRatePermission(): String? = when {
        Build.VERSION.SDK_INT >= 36 ->
            "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            "android.permission.BODY_SENSORS_BACKGROUND"
        else -> null
    }

    private fun requestBackgroundHeartRatePermissionOrStart() {
        val foregroundGranted = ContextCompat.checkSelfPermission(
            this,
            heartRatePermission(),
        ) == PackageManager.PERMISSION_GRANTED
        val backgroundPermission = backgroundHeartRatePermission()
        if (
            foregroundGranted &&
            backgroundPermission != null &&
            ContextCompat.checkSelfPermission(this, backgroundPermission) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            backgroundPermissionLauncher.launch(backgroundPermission)
        } else {
            startContinuousTrackingService()
        }
    }

    private fun startContinuousTrackingService() {
        ContextCompat.startForegroundService(
            this,
            Intent(this, SleepTrackingService::class.java)
                .setAction(SleepTrackingService.ACTION_START_CONTINUOUS),
        )
    }

    private fun submitWatchEma() {
        if (!emaSelectionMade) return
        val submittedAtMs = System.currentTimeMillis()
        val openedAtMs = emaInteractionStartedAtMs ?: submittedAtMs
        val status = SleepTrackingService.readStatus(this)
        val eventId = "watch_${submittedAtMs}_${UUID.randomUUID()}"
        emaStatusText = "Saving..."

        DataLayerService(this).sendEmaEvent(
            eventId = eventId,
            cravingScore = emaScore,
            openedAtMs = openedAtMs,
            submittedAtMs = submittedAtMs,
            watchSessionId = status.watchSessionId,
        ).addOnSuccessListener {
            emaStatusText = "Saved"
            emaInteractionStartedAtMs = null
            emaSelectionMade = false
            emaScore = 5
        }.addOnFailureListener { error ->
            Log.e("RecoverySenseWear", "Unable to queue EMA", error)
            emaStatusText = "Couldn't save. Try again."
        }
    }

    private fun updateFromServiceStatus() {
        val status = SleepTrackingService.readStatus(this)
        heartRateText = status.heartRate?.toString() ?: "--"
        accelText = status.accelerationG?.let { "%.2f g".format(it) } ?: "--"
        gyroText = status.gyroMagnitude?.let { "%.2f rad/s".format(it) } ?: "--"
        stepsText = status.steps?.toInt()?.toString() ?: "--"

    }

    override fun onDestroy() {
        statusHandler.removeCallbacks(statusPoll)
        super.onDestroy()
    }

    @Composable
    private fun RecoverySenseWearScreen(
        heartRate: String,
        accel: String,
        gyro: String,
        steps: String,
        emaScore: Int,
        emaStatus: String,
        emaSelectionMade: Boolean,
        onEmaScoreChanged: (Int) -> Unit,
        onSubmitEma: () -> Unit,
    ) {
        val background = Color(0xFFF8FBF4)
        val darkGreen = Color(0xFF356E0C)
        val metricBackground = Color(0xFFEAF6DF)

        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .background(background),
            contentAlignment = Alignment.TopCenter,
        ) {
            val compactScreen = maxWidth < 210.dp
            val horizontalPadding = if (compactScreen) 24.dp else 28.dp
            val topPadding = if (compactScreen) 18.dp else 22.dp
            val titleSize = if (compactScreen) 16.sp else 18.sp
            val valueSize = if (compactScreen) 14.sp else 16.sp

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(
                        start = horizontalPadding,
                        end = horizontalPadding,
                        top = topPadding,
                        bottom = 24.dp,
                    ),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = "RecoverySense",
                    color = Color.Black,
                    fontSize = titleSize,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                )

                Spacer(modifier = Modifier.height(8.dp))

                WearMetricCard("Heart Rate", "$heartRate bpm", metricBackground, valueSize)
                WearMetricCard("Acceleration", accel, metricBackground, valueSize)
                WearMetricCard("Gyroscope", gyro, metricBackground, valueSize)
                WearMetricCard("Steps", steps, metricBackground, valueSize)

                Spacer(modifier = Modifier.height(12.dp))
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color.White.copy(alpha = 0.94f))
                        .padding(horizontal = 10.dp, vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        text = "Craving right now?",
                        color = Color.Black,
                        fontSize = if (compactScreen) 12.sp else 13.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                    )
                    Text(
                        text = if (emaSelectionMade) "$emaScore / 10" else "— / 10",
                        color = darkGreen,
                        fontSize = if (compactScreen) 22.sp else 26.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    Slider(
                        value = emaScore.toFloat(),
                        onValueChange = { onEmaScoreChanged(it.roundToInt()) },
                        valueRange = 0f..10f,
                        steps = 9,
                    )
                    Button(
                        onClick = onSubmitEma,
                        enabled = emaSelectionMade,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(48.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFF4F9B17),
                            contentColor = Color.White,
                            disabledContainerColor = Color(0xFFEAF6DF),
                            disabledContentColor = Color(0xFF5D655B),
                        ),
                    ) {
                        Text(
                            text = "Save rating",
                            fontWeight = FontWeight.Bold,
                        )
                    }
                    Text(
                        text = emaStatus,
                        color = Color.DarkGray,
                        fontSize = if (compactScreen) 8.sp else 9.sp,
                        textAlign = TextAlign.Center,
                    )
                }

            }
        }
    }

    @Composable
    private fun WearMetricCard(
        label: String,
        value: String,
        backgroundColor: Color,
        valueFontSize: TextUnit,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 3.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(backgroundColor)
                .padding(horizontal = 10.dp, vertical = 7.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = label,
                color = Color(0xFF5D655B),
                fontSize = 9.sp,
                textAlign = TextAlign.Center,
            )
            Text(
                text = value,
                color = Color(0xFF356E0C),
                fontSize = valueFontSize,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
        }
    }
}
