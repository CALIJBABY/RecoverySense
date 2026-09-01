import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/watch_sensor_batch.dart';
import '../firebase/firestore_sensor_repository.dart';
import '../watch/watch_connection_service.dart';

class SensorIngestionService {
  SensorIngestionService._();

  static final SensorIngestionService instance = SensorIngestionService._();

  final FirestoreSensorRepository _repository = FirestoreSensorRepository();
  StreamSubscription<WatchSensorBatch>? _batchSubscription;
  StreamSubscription<User?>? _authSubscription;
  final Set<String> _inFlightBatchIds = <String>{};
  bool _started = false;

  String? latestWatchSessionId;
  int uploadedBatchCount = 0;
  Object? lastError;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _batchSubscription = WatchConnectionService.instance.batchStream.listen(
      _ingestBatch,
      onError: (Object error, StackTrace stackTrace) {
        lastError = error;
        debugPrint('Watch batch stream error: $error');
      },
    );

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        WatchConnectionService.instance.requestPendingBatches();
      }
    });

    if (FirebaseAuth.instance.currentUser != null) {
      await WatchConnectionService.instance.requestPendingBatches();
    }
  }

  Future<void> _ingestBatch(WatchSensorBatch batch) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _inFlightBatchIds.contains(batch.batchId)) return;

    _inFlightBatchIds.add(batch.batchId);
    try {
      await _repository.saveSensorBatch(
        participantId: user.uid,
        batch: batch,
      );
      latestWatchSessionId = batch.watchSessionId;
      uploadedBatchCount += 1;

      // Firestore accepts this write into its local persistent cache when the
      // phone is offline, then synchronizes it when connectivity returns.
      await WatchConnectionService.instance.acknowledgeBatch(batch.uri);
      lastError = null;
    } catch (error, stackTrace) {
      lastError = error;
      debugPrint('Unable to ingest sensor batch ${batch.batchId}: $error');
      debugPrintStack(stackTrace: stackTrace);
      // Do not acknowledge the Data Item. It stays pending and is retried.
    } finally {
      _inFlightBatchIds.remove(batch.batchId);
    }
  }

  Future<void> dispose() async {
    await _batchSubscription?.cancel();
    await _authSubscription?.cancel();
    _started = false;
  }
}
