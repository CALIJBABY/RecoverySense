import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/baseline_assessment.dart';

class BaselineAssessmentRepository {
  BaselineAssessmentRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  static const int currentAssessmentVersion = 1;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _participantRef(String uid) =>
      _firestore.collection('participants').doc(uid);

  DocumentReference<Map<String, dynamic>> _assessmentRef(String uid) =>
      _participantRef(uid)
          .collection('baseline_assessments')
          .doc('baseline_v$currentAssessmentVersion');

  Future<bool> isComplete() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final snapshot = await _assessmentRef(user.uid).get();
    final data = snapshot.data();
    return snapshot.exists &&
        data?['completed'] == true &&
        (data?['assessment_version'] as num?)?.toInt() == currentAssessmentVersion;
  }

  Stream<Map<String, dynamic>?> watchCurrentAssessment() {
    final user = _auth.currentUser;
    if (user == null) return Stream<Map<String, dynamic>?>.value(null);
    return _assessmentRef(user.uid).snapshots().map((snapshot) => snapshot.data());
  }

  Future<void> submitInitialAssessment(BaselineAssessment assessment) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('A signed-in participant is required for baseline assessment.');
    }

    final participantRef = _participantRef(user.uid);
    final assessmentRef = _assessmentRef(user.uid);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(assessmentRef);
      if (existing.exists && existing.data()?['completed'] == true) {
        throw StateError(
          'The initial baseline assessment has already been completed. '
          'A later protocol revision should use a new assessment version rather than overwrite it.',
        );
      }

      transaction.set(assessmentRef, <String, Object?>{
        'participant_id': user.uid,
        ...assessment.toFirestore(),
        'completed': true,
        'completed_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      });
      transaction.set(
        participantRef,
        <String, Object?>{
          'baseline_assessment_version': currentAssessmentVersion,
          'baseline_completed': true,
          'baseline_completed_at': FieldValue.serverTimestamp(),
          'last_seen_at': FieldValue.serverTimestamp(),
          'schema_version': 2,
        },
        SetOptions(merge: true),
      );
    });
  }
}
