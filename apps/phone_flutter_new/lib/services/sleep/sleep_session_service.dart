import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/sleep_epoch.dart';
import '../../models/sleep_session.dart';
import '../../models/watch_sensor_batch.dart';
import '../firebase/sleep_repository.dart';
import '../watch/watch_connection_service.dart';
import 'sleep_estimator.dart';

class SleepTrackingState {
  final SleepSessionRecord? currentSession;
  final SleepSessionRecord? latestConfirmedSession;
  final double? latestSleepProbability;
  final List<SleepEpochEstimate> epochs;
  final int epochCount;
  final bool busy;
  final Object? error;

  const SleepTrackingState({
    this.currentSession,
    this.latestConfirmedSession,
    this.latestSleepProbability,
    this.epochs = const <SleepEpochEstimate>[],
    this.epochCount = 0,
    this.busy = false,
    this.error,
  });

  bool get isRecording => currentSession?.isRecording ?? false;
  bool get needsConfirmation => currentSession?.needsConfirmation ?? false;

  SleepTrackingState copyWith({
    SleepSessionRecord? currentSession,
    bool clearCurrentSession = false,
    SleepSessionRecord? latestConfirmedSession,
    double? latestSleepProbability,
    List<SleepEpochEstimate>? epochs,
    int? epochCount,
    bool? busy,
    Object? error,
    bool clearError = false,
  }) {
    return SleepTrackingState(
      currentSession:
          clearCurrentSession ? null : currentSession ?? this.currentSession,
      latestConfirmedSession:
          latestConfirmedSession ?? this.latestConfirmedSession,
      latestSleepProbability:
          latestSleepProbability ?? this.latestSleepProbability,
      epochs: epochs ?? this.epochs,
      epochCount: epochCount ?? this.epochCount,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class SleepSessionService {
  SleepSessionService._();

  static final SleepSessionService instance = SleepSessionService._();

  final SleepRepository _repository = SleepRepository();
  final SleepEstimator _estimator = const SleepEstimator();
  final ValueNotifier<SleepTrackingState> state =
      ValueNotifier<SleepTrackingState>(const SleepTrackingState());

  StreamSubscription<User?>? _authSubscription;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        state.value = const SleepTrackingState();
      } else {
        unawaited(_restore(user.uid));
      }
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) await _restore(user.uid);
  }

  Future<void> _restore(String participantId) async {
    try {
      final open = await _repository.findOpenSession(participantId);
      final latest = await _repository.latestConfirmedSession(participantId);
      final epochs = open == null
          ? const <SleepEpochEstimate>[]
          : await _repository.loadEpochs(
              participantId: participantId,
              sleepSessionId: open.id,
            );
      state.value = SleepTrackingState(
        currentSession: open,
        latestConfirmedSession: latest,
        latestSleepProbability:
            epochs.isEmpty ? null : epochs.last.sleepProbability,
        epochs: epochs,
        epochCount: epochs.length,
      );
    } catch (error) {
      state.value = state.value.copyWith(error: error);
    }
  }

  Future<String> startRecording() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before starting sleep recording.');
    if (state.value.isRecording) return state.value.currentSession!.id;

    state.value = state.value.copyWith(busy: true, clearError: true);
    final now = DateTime.now().toUtc();
    final sessionId = '${user.uid}_${now.microsecondsSinceEpoch}';
    try {
      await _repository.createSession(
        participantId: user.uid,
        sleepSessionId: sessionId,
        recordingStart: now,
      );
      final delivered =
          await WatchConnectionService.instance.startSleepRecording(sessionId);
      if (delivered == 0) {
        throw StateError(
          'The sleep command did not reach a paired watch. Open RecoverySense '
          'on the watch once, grant sensor permissions, and try again.',
        );
      }
      final record = SleepSessionRecord(
        id: sessionId,
        participantId: user.uid,
        status: 'recording',
        recordingStart: now,
        recordingEnd: null,
        reportedSleepOnset: now,
        reportedWake: null,
        sleepQuality: null,
        restedScore: null,
        reportedAwakenings: null,
        watchRemoved: null,
        summary: null,
      );
      state.value = SleepTrackingState(
        currentSession: record,
        latestConfirmedSession: state.value.latestConfirmedSession,
        epochs: const <SleepEpochEstimate>[],
      );
      return sessionId;
    } catch (error) {
      try {
        await _repository.markStartFailed(
          participantId: user.uid,
          sleepSessionId: sessionId,
          error: error,
        );
      } catch (repositoryError) {
        debugPrint('Unable to mark failed sleep start: $repositoryError');
      }
      state.value = state.value.copyWith(busy: false, error: error);
      rethrow;
    }
  }

  Future<void> processBatch(WatchSensorBatch batch) async {
    if (!batch.isSleepBatch || batch.sleepSessionId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final epoch = _estimator.estimateBatch(batch);
      await _repository.saveEpoch(participantId: user.uid, epoch: epoch);
      final current = state.value.currentSession;
      final belongsToCurrent = current?.id == batch.sleepSessionId;
      var updatedEpochs = state.value.epochs;
      if (belongsToCurrent) {
        updatedEpochs = <SleepEpochEstimate>[
          ...state.value.epochs.where((item) => item.batchId != epoch.batchId),
          epoch,
        ]..sort((a, b) => a.start.compareTo(b.start));
      }
      state.value = state.value.copyWith(
        latestSleepProbability: epoch.sleepProbability,
        epochs: updatedEpochs,
        epochCount: updatedEpochs.length,
        clearError: true,
      );
    } catch (error, stackTrace) {
      debugPrint('Unable to estimate sleep epoch ${batch.batchId}: $error');
      debugPrintStack(stackTrace: stackTrace);
      state.value = state.value.copyWith(error: error);
    }
  }

  Future<SleepSummary> stopRecording() async {
    final user = FirebaseAuth.instance.currentUser;
    final current = state.value.currentSession;
    if (user == null || current == null || !current.isRecording) {
      throw StateError('There is no active sleep recording.');
    }

    state.value = state.value.copyWith(busy: true, clearError: true);
    final end = DateTime.now().toUtc();
    try {
      final delivered = await WatchConnectionService.instance.stopSleepRecording();
      if (delivered == 0) {
        throw StateError(
          'The stop command did not reach the watch. Keep the phone near the '
          'watch and try I Woke Up again so overnight recording is not left active.',
        );
      }
      await WatchConnectionService.instance.requestPendingBatches();
      // Give the final Data Item a brief chance to arrive before querying the
      // provisional epochs. The session can be re-estimated later from raw data.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final epochs = await _repository.loadEpochs(
        participantId: user.uid,
        sleepSessionId: current.id,
      );
      final summary = _estimator.summarize(
        epochs,
        recordingStart: current.recordingStart,
        recordingEnd: end,
      );
      await _repository.markAwaitingConfirmation(
        participantId: user.uid,
        sleepSessionId: current.id,
        recordingEnd: end,
        summary: summary,
      );
      final awaiting = SleepSessionRecord(
        id: current.id,
        participantId: user.uid,
        status: 'awaiting_confirmation',
        recordingStart: current.recordingStart,
        recordingEnd: end,
        reportedSleepOnset: summary.estimatedSleepOnset,
        reportedWake: summary.estimatedWake,
        sleepQuality: null,
        restedScore: null,
        reportedAwakenings: null,
        watchRemoved: null,
        summary: summary,
      );
      state.value = SleepTrackingState(
        currentSession: awaiting,
        latestConfirmedSession: state.value.latestConfirmedSession,
        latestSleepProbability: state.value.latestSleepProbability,
        epochs: epochs,
        epochCount: epochs.length,
      );
      return summary;
    } catch (error) {
      state.value = state.value.copyWith(busy: false, error: error);
      rethrow;
    }
  }

  Future<void> confirmSession({
    required DateTime reportedSleepOnset,
    required DateTime reportedWake,
    required int sleepQuality,
    required int restedScore,
    required int reportedAwakenings,
    required bool watchRemoved,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final current = state.value.currentSession;
    if (user == null || current == null || !current.needsConfirmation) {
      throw StateError('There is no sleep session awaiting confirmation.');
    }
    if (!reportedWake.isAfter(reportedSleepOnset)) {
      throw ArgumentError('Wake time must be after sleep onset.');
    }

    state.value = state.value.copyWith(busy: true, clearError: true);
    try {
      await _repository.confirmSession(
        participantId: user.uid,
        sleepSessionId: current.id,
        reportedSleepOnset: reportedSleepOnset,
        reportedWake: reportedWake,
        sleepQuality: sleepQuality,
        restedScore: restedScore,
        reportedAwakenings: reportedAwakenings,
        watchRemoved: watchRemoved,
      );
      final confirmed = SleepSessionRecord(
        id: current.id,
        participantId: user.uid,
        status: 'confirmed',
        recordingStart: current.recordingStart,
        recordingEnd: current.recordingEnd,
        reportedSleepOnset: reportedSleepOnset,
        reportedWake: reportedWake,
        sleepQuality: sleepQuality,
        restedScore: restedScore,
        reportedAwakenings: reportedAwakenings,
        watchRemoved: watchRemoved,
        summary: current.summary,
      );
      state.value = SleepTrackingState(
        currentSession: null,
        latestConfirmedSession: confirmed,
        epochs: const <SleepEpochEstimate>[],
      );
    } catch (error) {
      state.value = state.value.copyWith(busy: false, error: error);
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _started = false;
  }
}
