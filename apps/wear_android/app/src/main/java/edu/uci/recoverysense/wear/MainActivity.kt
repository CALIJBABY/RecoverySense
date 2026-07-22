package edu.uci.recoverysense.wear

import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    private lateinit var sensorCollector: SensorCollector
    private lateinit var wearDataClient: WearDataClient

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        permissionLauncher.launch(Manifest.permission.BODY_SENSORS)

        sensorCollector = SensorCollector(this)
        wearDataClient = WearDataClient(this)

        setContent {
            var latest by remember { mutableStateOf(sensorCollector.currentReading()) }

            DisposableEffect(Unit) {
                sensorCollector.start()
                onDispose { sensorCollector.stop() }
            }

            MaterialTheme {
                Column(
                    modifier = Modifier.fillMaxSize().padding(12.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("RecoverySense")
                    Text("HR: ${latest.heartRate.toInt()} bpm")
                    Text("X: ${"%.2f".format(latest.accelX)}")
                    Text("Y: ${"%.2f".format(latest.accelY)}")
                    Text("Z: ${"%.2f".format(latest.accelZ)}")
                    Button(onClick = {
                        latest = sensorCollector.currentReading()
                        wearDataClient.sendSensorReading(latest)
                    }) {
                        Text("Send")
                    }
                }
            }
        }
    }
}
