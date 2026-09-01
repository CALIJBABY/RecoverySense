import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/watch_ppg_batch.dart';
import '../../models/watch_sensor_batch.dart';

class FirestoreSensorRepository {
  FirestoreSensorRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> saveSensorBatch({
    required String participantId,
    required WatchSensorBatch batch,
  }) async {
    final participantRef =
        _firestore.collection('participants').doc(participantId);
    final sessionRef =
        participantRef.collection('sessions').doc(batch.watchSessionId);
    final batchRef =
        sessionRef.collection('sensor_batches').doc(batch.batchId);

    final firstTimestamp = batch.timestampsMs.first;
    final lastTimestamp = batch.timestampsMs.last;
    final batchData = <String, Object?>{
      'participant_id': participantId,
      'session_id': batch.watchSessionId,
      'batch_id': batch.batchId,
      'sequence': batch.sequence,
      'source': 'wear_os_android_sensors',
      'recording_mode': batch.recordingMode,
      'sleep_session_id': batch.sleepSessionId,
      'sampling_rate_hz': batch.samplingRateHz,
      'sample_count': batch.sampleCount,
      'start_time_ms': firstTimestamp,
      'end_time_ms': lastTimestamp,
      'watch_created_at_ms': batch.createdAt.millisecondsSinceEpoch,
      'received_at': FieldValue.serverTimestamp(),
      'watch_schema_version': batch.schemaVersion,
      'schema_version': 4,
      'sensor_capabilities': batch.sensorCapabilities,
      'quality_summary': batch.qualitySummary,
      'samples': batch.toFirestoreSamples(),
    };

    final writeBatch = _firestore.batch();
    writeBatch.set(
      participantRef,
      <String, Object?>{
        'participant_id': participantId,
        'last_seen_at': FieldValue.serverTimestamp(),
        'schema_version': 4,
      },
      SetOptions(merge: true),
    );
    writeBatch.set(
      sessionRef,
      <String, Object?>{
        'participant_id': participantId,
        'session_id': batch.watchSessionId,
        'source': 'wear_os_android_sensors',
        'recording_mode': batch.recordingMode,
        'sleep_session_id': batch.sleepSessionId,
        'started_at_ms': firstTimestamp,
        'last_sample_at_ms': lastTimestamp,
        'sampling_rate_hz': batch.samplingRateHz,
        'last_batch_sequence': batch.sequence,
        'sensor_capabilities': batch.sensorCapabilities,
        'updated_at': FieldValue.serverTimestamp(),
        'schema_version': 4,
      },
      SetOptions(merge: true),
    );
    writeBatch.set(batchRef, batchData, SetOptions(merge: true));

    // Keep a direct raw-data link under each overnight session so the sleep
    // pipeline can be rebuilt even if provisional phone-side epochs change.
    if (batch.isSleepBatch && batch.sleepSessionId != null) {
      final sleepRef = participantRef
          .collection('sleep_sessions')
          .doc(batch.sleepSessionId);
      writeBatch.set(
        sleepRef,
        <String, Object?>{
          'participant_id': participantId,
          'sleep_session_id': batch.sleepSessionId,
          'last_sample_at_ms': lastTimestamp,
          'updated_at': FieldValue.serverTimestamp(),
          'schema_version': 1,
        },
        SetOptions(merge: true),
      );
      writeBatch.set(
        sleepRef.collection('sensor_batches').doc(batch.batchId),
        batchData,
        SetOptions(merge: true),
      );
    }

    await writeBatch.commit();
  }

  Future<void> savePpgBatch({
    required String participantId,
    required WatchPpgBatch batch,
  }) async {
    final participantRef =
        _firestore.collection('participants').doc(participantId);
    final sessionRef =
        participantRef.collection('sessions').doc(batch.watchSessionId);
    final batchRef = sessionRef.collection('ppg_batches').doc(batch.batchId);

    final firstTimestamp = batch.timestampsMs.first;
    final lastTimestamp = batch.timestampsMs.last;
    final batchData = <String, Object?>{
      'participant_id': participantId,
      'session_id': batch.watchSessionId,
      'batch_id': batch.batchId,
      'sequence': batch.sequence,
      'source': batch.source,
      'recording_mode': batch.recordingMode,
      'sleep_session_id': batch.sleepSessionId,
      'sampling_rate_hz': batch.samplingRateHz,
      'sample_count': batch.sampleCount,
      'start_time_ms': firstTimestamp,
      'end_time_ms': lastTimestamp,
      'watch_created_at_ms': batch.createdAt.millisecondsSinceEpoch,
      'received_at': FieldValue.serverTimestamp(),
      'watch_schema_version': batch.schemaVersion,
      'schema_version': 1,
      'quality_summary': batch.qualitySummary,
      // Array-based storage keeps each 10-second PPG batch compact while the
      // export pipeline can still flatten it losslessly into one row/sample.
      'timestamps_ms': batch.timestampsMs,
      'green_adc': batch.green,
      'infrared_adc': batch.infrared,
      'red_adc': batch.red,
      'green_status': batch.greenStatus,
      'infrared_status': batch.infraredStatus,
      'red_status': batch.redStatus,
    };

    final writeBatch = _firestore.batch();
    writeBatch.set(
      participantRef,
      <String, Object?>{
        'participant_id': participantId,
        'last_seen_at': FieldValue.serverTimestamp(),
        'raw_ppg_available': true,
        'schema_version': 4,
      },
      SetOptions(merge: true),
    );
    writeBatch.set(
      sessionRef,
      <String, Object?>{
        'participant_id': participantId,
        'session_id': batch.watchSessionId,
        'ppg_source': batch.source,
        'ppg_sampling_rate_hz': batch.samplingRateHz,
        'last_ppg_sample_at_ms': lastTimestamp,
        'last_ppg_batch_sequence': batch.sequence,
        'updated_at': FieldValue.serverTimestamp(),
        'schema_version': 4,
      },
      SetOptions(merge: true),
    );
    writeBatch.set(batchRef, batchData, SetOptions(merge: true));

    if (batch.isSleepBatch && batch.sleepSessionId != null) {
      final sleepRef = participantRef
          .collection('sleep_sessions')
          .doc(batch.sleepSessionId);
      writeBatch.set(
        sleepRef,
        <String, Object?>{
          'participant_id': participantId,
          'sleep_session_id': batch.sleepSessionId,
          'raw_ppg_available': true,
          'ppg_source': batch.source,
          'last_ppg_sample_at_ms': lastTimestamp,
          'updated_at': FieldValue.serverTimestamp(),
          'schema_version': 2,
        },
        SetOptions(merge: true),
      );
      writeBatch.set(
        sleepRef.collection('ppg_batches').doc(batch.batchId),
        batchData,
        SetOptions(merge: true),
      );
    }

    await writeBatch.commit();
  }

}
