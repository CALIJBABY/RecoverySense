# Samsung Health Sensor SDK AAR

Download `samsung-health-sensor-api.aar` from Samsung's official Health Sensor SDK page and place it in this directory.

The Gradle build includes the AAR automatically when the file is present. The app uses reflection so the standard build still compiles before the AAR is available. Raw PPG remains disabled with state `sdk_aar_missing` until the AAR is added and Health Platform developer mode / SDK policy access is configured.
