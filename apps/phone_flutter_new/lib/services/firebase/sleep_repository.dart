import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/sleep_epoch.dart';
import '../../models/sleep_session.dart';

class SleepRepository {
  SleepRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _sessions(String participantId) =>
      _firestore
          .collection('participants')
          .doc(participantId)
          .collection('sleep_sessions');

  Future<void> createSession({
    required String participantId,
    required String sleepSessionId,
    required DateTime recordingStart,
  }) async {
    await _sessions(participantId).doc(sleepSessionId).set(
      <String, Object?>{
        'participant_id': participantId,
        'sleep_session_id': sleepSessionId,
        'status': 'recording',
        'recording_start_ms': recordingStart.toUtc().millisecondsSinceEpoch,
        'reported_bedtime_ms': recordingStart.toUtc().millisecondsSinceEpoch,
        'reported_sleep_onset_ms': recordingStart.toUtc().millisecondsSinceEpoch,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'schema_version': 1,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> markStartFailed({
    required String participantId,
    required String sleepSessionId,
    required Object error,
  }) async {
    await _sessions(participantId).doc(sleepSessionId).set(
      <String, Object?>{
        'status': 'start_failed',
        'start_error_code': 'watch_start_failed',
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> saveEpoch({
    required String participantId,
    required SleepEpochEstimate epoch,
  }) async {
    final sessionRef = _sessions(participantId).doc(epoch.sleepSessionId);
    final epochRef = sessionRef.collection('epochs').doc(epoch.batchId);
    final batch = _firestore.batch();
    batch.set(epochRef, <String, Object?>{
      ...epoch.toFirestore(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    batch.set(
      sessionRef,
      <String, Object?>{
        'last_epoch_end_ms': epoch.end.millisecondsSinceEpoch,
        'last_sleep_probability': epoch.sleepProbability,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<List<SleepEpochEstimate>> loadEpochs({
    required String participantId,
    required String sleepSessionId,
  }) async {
    final snapshot = await _sessions(participantId)
        .doc(sleepSessionId)
        .collection('epochs')
        .orderBy('epoch_start_ms')
        .get();
    return snapshot.docs
        .map((doc) => SleepEpochEstimate.fromMap(doc.data()))
        .toList(growable: false);
  }

  Future<void> markAwaitingConfirmation({
    required String participantId,
    required String sleepSessionId,
    required DateTime recordingEnd,
    required SleepSummary summary,
  }) async {
    await _sessions(participantId).doc(sleepSessionId).set(
      <String, Object?>{
        'status': 'awaiting_confirmation',
        'recording_end_ms': recordingEnd.toUtc().millisecondsSinceEpoch,
        ...summary.toFirestore(),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> confirmSession({
    required String participantId,
    required String sleepSessionId,
    required DateTime reportedSleepOnset,
    required DateTime reportedWake,
    required int sleepQuality,
    required int restedScore,
    required int reportedAwakenings,
    required bool watchRemoved,
  }) async {
    await _sessions(participantId).doc(sleepSessionId).set(
      <String, Object?>{
        'status': 'confirmed',
        'reported_sleep_onset_ms':
            reportedSleepOnset.toUtc().millisecondsSinceEpoch,
        'reported_wake_ms': reportedWake.toUtc().millisecondsSinceEpoch,
        'sleep_quality': sleepQuality,
        'rested_score': restedScore,
        'reported_awakenings': reportedAwakenings,
        'watch_removed': watchRemoved,
        'confirmed_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<SleepSessionRecord?> findOpenSession(String participantId) async {
    final snapshot = await _sessions(participantId).get();
    final open = snapshot.docs
        .map((doc) => SleepSessionRecord.fromMap(doc.id, doc.data()))
        .where((session) => session.isRecording || session.needsConfirmation)
        .toList()
      ..sort((a, b) => b.recordingStart.compareTo(a.recordingStart));
    return open.isEmpty ? null : open.first;
  }

  Future<SleepSessionRecord?> latestConfirmedSession(
    String participantId,
  ) async {
    final snapshot = await _sessions(participantId).get();
    final confirmed = snapshot.docs
        .map((doc) => SleepSessionRecord.fromMap(doc.id, doc.data()))
        .where((session) => session.status == 'confirmed')
        .toList()
      ..sort((a, b) => b.recordingStart.compareTo(a.recordingStart));
    return confirmed.isEmpty ? null : confirmed.first;
  }
}
