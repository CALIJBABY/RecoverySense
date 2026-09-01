import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/ema_prompt.dart';
import '../../models/watch_ema_event.dart';

class EmaRepository {
  EmaRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Stores the core EMA label used by the craving model.
  ///
  /// The required participant response is intentionally one item only:
  /// craving/urge intensity from 0 (none) to 10 (extreme).
  Future<void> submitEma({
    required int cravingScore,
    String? sessionId,
    required int openedAtMs,
    EmaPrompt prompt = const EmaPrompt(),
    String responseDevice = 'phone',
  }) async {
    _validateScore(cravingScore);
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('A signed-in participant is required to submit an EMA.');
    }

    final submittedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final responseStartMs = prompt.promptedAtMs ?? openedAtMs;
    final eventRef = _firestore
        .collection('participants')
        .doc(user.uid)
        .collection('ema_events')
        .doc();

    await eventRef.set(<String, Object?>{
      'participant_id': user.uid,
      'session_id': sessionId,
      'timestamp_ms': submittedAtMs,
      'prompted_at_ms': prompt.promptedAtMs,
      'opened_at_ms': openedAtMs,
      'submitted_at_ms': submittedAtMs,
      'response_delay_ms': submittedAtMs - responseStartMs,
      'craving_score': cravingScore,
      'source': prompt.source,
      'response_device': responseDevice,
      'trigger_reason': _emptyToNull(prompt.triggerReason),
      'trigger_probability': prompt.triggerProbability,
      'model_version': prompt.modelVersion,
      'model_threshold': prompt.modelThreshold,
      'window_start_ms': prompt.windowStartMs,
      'window_end_ms': prompt.windowEndMs,
      'created_at': FieldValue.serverTimestamp(),
      'schema_version': 3,
    });
  }

  /// Persists a 0-10 response captured directly on the Galaxy Watch.
  Future<void> submitWatchEma(WatchEmaEvent event) async {
    _validateScore(event.cravingScore);
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('A signed-in participant is required to submit an EMA.');
    }

    final responseStartMs = event.promptedAtMs ?? event.openedAtMs;
    final eventId = event.eventId.isEmpty
        ? 'watch_${event.submittedAtMs}'
        : event.eventId;
    final eventRef = _firestore
        .collection('participants')
        .doc(user.uid)
        .collection('ema_events')
        .doc(eventId);

    await eventRef.set(<String, Object?>{
      'participant_id': user.uid,
      'session_id': event.watchSessionId,
      'timestamp_ms': event.timestampMs,
      'prompted_at_ms': event.promptedAtMs,
      'opened_at_ms': event.openedAtMs,
      'submitted_at_ms': event.submittedAtMs,
      'response_delay_ms': event.submittedAtMs - responseStartMs,
      'craving_score': event.cravingScore,
      'source': event.source,
      'response_device': 'watch',
      'created_at': FieldValue.serverTimestamp(),
      'schema_version': 3,
    }, SetOptions(merge: true));
  }

  static void _validateScore(int score) {
    if (score < 0 || score > 10) {
      throw RangeError.range(score, 0, 10, 'cravingScore');
    }
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
