import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      try {
        await _ensureParticipantProfile(user);
      } catch (_) {
        await _auth.signOut();
        rethrow;
      }
    }
    return credential;
  }

  Future<void> sendPasswordResetEmail({required String email}) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user != null) {
      try {
        await _ensureParticipantProfile(user);
      } catch (_) {
        await _auth.signOut();
        rethrow;
      }
    }
    return credential;
  }

  Future<void> _ensureParticipantProfile(User user) async {
    final reference = _firestore.collection('participants').doc(user.uid);
    final existing = await reference.get();
    final data = <String, Object?>{
      'participant_id': user.uid,
      'auth_provider': 'firebase',
      // Email remains in Firebase Authentication and is intentionally not
      // duplicated into the research-data document.
      'last_seen_at': FieldValue.serverTimestamp(),
      'schema_version': 1,
    };
    if (!existing.exists) {
      data['created_at'] = FieldValue.serverTimestamp();
    }
    await reference.set(data, SetOptions(merge: true));
  }

  Future<void> signOut() => _auth.signOut();
}
