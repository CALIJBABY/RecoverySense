import 'dart:async';
import 'dart:collection';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/watch_ema_event.dart';
import '../../models/watch_ppg_batch.dart';
import '../../models/watch_sensor_batch.dart';
import '../firebase/ema_repository.dart';
import '../firebase/firestore_sensor_repository.dart';
import '../sleep/sleep_session_service.dart';
import '../watch/watch_connection_service.dart';

class SensorIngestionService {
  SensorIngestionService._();

  static final SensorIngestionService instance = SensorIngestionService._();
  static const int _maxQueuedUploads = 8;

  final FirestoreSensorRepository _repository = FirestoreSensorRepository();
  final EmaRepository _emaRepository = EmaRepository();
  final Queue<_QueuedUpload> _queue = Queue<_QueuedUpload>();
  final Set<String> _queuedOrInFlight = <String>{};

  StreamSubscription<WatchSensorBatch>? _batchSubscription;
  StreamSubscription<WatchPpgBatch>? _ppgBatchSubscription;
  StreamSubscription<WatchEmaEvent>? _emaEventSubscription;
  StreamSubscription<User?>? _authSubscription;

  bool _started = false;
  bool _processing = false;
  bool _pendingRequestInFlight = false;

  String? latestWatchSessionId;
  int uploadedBatchCount = 0;
  int uploadedPpgBatchCount = 0;
  int uploadedWatchEmaCount = 0;
  Object? lastError;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _batchSubscription = WatchConnectionService.instance.batchStream.listen(
      _enqueueSensorBatch,
      onError: _handleStreamError,
    );
    _ppgBatchSubscription =
        WatchConnectionService.instance.ppgBatchStream.listen(
      _enqueuePpgBatch,
      onError: _handleStreamError,
    );
    _emaEventSubscription =
        WatchConnectionService.instance.emaEventStream.listen(
      _enqueueWatchEma,
      onError: _handleStreamError,
    );

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _clearMemoryQueue();
        return;
      }
      unawaited(_requestNextPending());
    });

    if (FirebaseAuth.instance.currentUser != null) {
      await _requestNextPending();
    }
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    lastError = error;
    debugPrint('Watch ingestion stream error: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  void _enqueueSensorBatch(WatchSensorBatch batch) {
    _enqueue(
      key: 'sensor:${batch.batchId}',
      upload: () => _uploadSensorBatch(batch),
    );
  }

  void _enqueuePpgBatch(WatchPpgBatch batch) {
    _enqueue(
      key: 'ppg:${batch.batchId}',
      upload: () => _uploadPpgBatch(batch),
    );
  }

  void _enqueueWatchEma(WatchEmaEvent event) {
    _enqueue(
      key: 'ema:${event.eventId}',
      upload: () => _uploadWatchEma(event),
    );
  }

  void _enqueue({
    required String key,
    required Future<void> Function() upload,
  }) {
    // If signed out, do not retain a large payload in memory. The Wear Data
    // Item stays unacknowledged and can be replayed after the next login.
    if (FirebaseAuth.instance.currentUser == null) return;
    if (_queuedOrInFlight.contains(key)) return;

    if (_queue.length >= _maxQueuedUploads) {
      lastError = StateError(
        'RecoverySense ingestion queue reached $_maxQueuedUploads items. '
        'The unacknowledged Wear Data Item will be replayed later.',
      );
      return;
    }

    _queuedOrInFlight.add(key);
    _queue.add(_QueuedUpload(key: key, upload: upload));
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        if (FirebaseAuth.instance.currentUser == null) {
          _clearMemoryQueue();
          return;
        }

        final item = _queue.removeFirst();
        try {
          await item.upload();
          _queuedOrInFlight.remove(item.key);
          lastError = null;

          // Ask the native bridge for only one more stored Data Item after the
          // current item has been persisted and acknowledged.
          await _requestNextPending();
        } catch (error, stackTrace) {
          lastError = error;
          _queuedOrInFlight.remove(item.key);
          debugPrint('RecoverySense upload failed for ${item.key}: $error');
          debugPrintStack(stackTrace: stackTrace);

          // Do not spin on a failing Firestore write. All unacknowledged Wear
          // Data Items remain available for a later app start/login retry.
          _clearMemoryQueue();
          return;
        }
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _requestNextPending() async {
    if (FirebaseAuth.instance.currentUser == null ||
        _pendingRequestInFlight) {
      return;
    }
    _pendingRequestInFlight = true;
    try {
      await WatchConnectionService.instance.requestPendingBatches();
    } catch (error, stackTrace) {
      lastError = error;
      debugPrint('Unable to request the next pending watch item: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _pendingRequestInFlight = false;
    }
  }

  Future<void> _uploadSensorBatch(WatchSensorBatch batch) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('A signed-in participant is required for sensor upload.');
    }

    await _repository.saveSensorBatch(
      participantId: user.uid,
      batch: batch,
    );
    if (batch.isSleepBatch) {
      await SleepSessionService.instance.processBatch(batch);
    }
    latestWatchSessionId = batch.watchSessionId;
    uploadedBatchCount += 1;
    await WatchConnectionService.instance.acknowledgeBatch(batch.uri);
  }

  Future<void> _uploadPpgBatch(WatchPpgBatch batch) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('A signed-in participant is required for PPG upload.');
    }

    await _repository.savePpgBatch(
      participantId: user.uid,
      batch: batch,
    );
    latestWatchSessionId = batch.watchSessionId;
    uploadedPpgBatchCount += 1;
    await WatchConnectionService.instance.acknowledgeBatch(batch.uri);
  }

  Future<void> _uploadWatchEma(WatchEmaEvent event) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('A signed-in participant is required for EMA upload.');
    }

    await _emaRepository.submitWatchEma(event);
    if (event.watchSessionId != null) {
      latestWatchSessionId = event.watchSessionId;
    }
    uploadedWatchEmaCount += 1;
    await WatchConnectionService.instance.acknowledgeBatch(event.uri);
  }

  void _clearMemoryQueue() {
    for (final item in _queue) {
      _queuedOrInFlight.remove(item.key);
    }
    _queue.clear();
  }

  Future<void> dispose() async {
    await _batchSubscription?.cancel();
    await _ppgBatchSubscription?.cancel();
    await _emaEventSubscription?.cancel();
    await _authSubscription?.cancel();
    _clearMemoryQueue();
    _started = false;
  }
}

class _QueuedUpload {
  const _QueuedUpload({
    required this.key,
    required this.upload,
  });

  final String key;
  final Future<void> Function() upload;
}
