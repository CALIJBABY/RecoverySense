import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/risk_prediction.dart';

class LatestEmaRating {
  const LatestEmaRating({required this.score, required this.timestamp});

  final int score;
  final DateTime timestamp;
}

class ParticipantInsightsRepository {
  ParticipantInsightsRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>>? get _participantRef {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _firestore.collection('participants').doc(user.uid);
  }

  Stream<LatestEmaRating?> latestEmaStream() {
    final ref = _participantRef;
    if (ref == null) return Stream<LatestEmaRating?>.value(null);
    return ref
        .collection('ema_events')
        .orderBy('timestamp_ms', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final data = snapshot.docs.first.data();
      final score = (data['craving_score'] as num?)?.toInt();
      final timestampMs = (data['timestamp_ms'] as num?)?.toInt();
      if (score == null || timestampMs == null || timestampMs <= 0) return null;
      return LatestEmaRating(
        score: score.clamp(0, 10).toInt(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true).toLocal(),
      );
    });
  }

  Stream<RiskPrediction?> latestRiskPredictionStream() {
    final ref = _participantRef;
    if (ref == null) return Stream<RiskPrediction?>.value(null);
    return ref
        .collection('risk_predictions')
        .orderBy('timestamp_ms', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
      for (final document in snapshot.docs) {
        final prediction = RiskPrediction.fromMap(document.data());
        if (prediction.displayEligible) return prediction;
      }
      return null;
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> emaHistoryStream({int limit = 500}) {
    final ref = _participantRef;
    if (ref == null) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return ref
        .collection('ema_events')
        .orderBy('timestamp_ms', descending: true)
        .limit(limit)
        .snapshots();
  }
}
