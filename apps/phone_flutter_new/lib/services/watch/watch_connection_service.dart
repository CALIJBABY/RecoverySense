import 'package:flutter/services.dart';

import '../../models/watch_ema_event.dart';
import '../../models/watch_ppg_batch.dart';
import '../../models/watch_sensor_batch.dart';
import '../../models/watch_sensor_sample.dart';

class WatchConnectionService {
  WatchConnectionService._();

  static final WatchConnectionService instance = WatchConnectionService._();

  static const EventChannel _liveChannel = EventChannel(
    'recoverysense/live_sensors',
  );
  static const EventChannel _batchChannel = EventChannel(
    'recoverysense/sensor_batches',
  );
  static const EventChannel _ppgBatchChannel = EventChannel(
    'recoverysense/ppg_batches',
  );
  static const EventChannel _emaEventChannel = EventChannel(
    'recoverysense/ema_events',
  );
  static const MethodChannel _controlChannel = MethodChannel(
    'recoverysense/sensor_control',
  );

  late final Stream<WatchSensorSample> liveStream = _liveChannel
      .receiveBroadcastStream()
      .map((dynamic event) {
        if (event is! Map) {
          throw const FormatException('Invalid live watch sensor payload.');
        }
        return WatchSensorSample.fromMap(event);
      })
      .asBroadcastStream();

  late final Stream<WatchSensorBatch> batchStream = _batchChannel
      .receiveBroadcastStream()
      .map((dynamic event) {
        if (event is! Map) {
          throw const FormatException('Invalid watch sensor batch payload.');
        }
        return WatchSensorBatch.fromMap(event);
      })
      .asBroadcastStream();

  late final Stream<WatchPpgBatch> ppgBatchStream = _ppgBatchChannel
      .receiveBroadcastStream()
      .map((dynamic event) {
        if (event is! Map) {
          throw const FormatException('Invalid watch PPG batch payload.');
        }
        return WatchPpgBatch.fromMap(event);
      })
      .asBroadcastStream();

  late final Stream<WatchEmaEvent> emaEventStream = _emaEventChannel
      .receiveBroadcastStream()
      .map((dynamic event) {
        if (event is! Map) {
          throw const FormatException('Invalid watch EMA event payload.');
        }
        return WatchEmaEvent.fromMap(event);
      })
      .asBroadcastStream();

  Future<bool> requestPendingBatches() async {
    final result = await _controlChannel.invokeMethod<bool>(
      'requestPendingBatches',
    );
    return result ?? false;
  }

  Future<int> startSleepRecording(String sleepSessionId) async {
    final result = await _controlChannel.invokeMethod<int>(
      'startSleepRecording',
      <String, Object?>{'sleepSessionId': sleepSessionId},
    );
    return result ?? 0;
  }

  Future<int> stopSleepRecording() async {
    final result = await _controlChannel.invokeMethod<int>(
      'stopSleepRecording',
    );
    return result ?? 0;
  }

  Future<int> acknowledgeBatch(String uri) async {
    final result = await _controlChannel.invokeMethod<int>(
      'ackBatch',
      <String, Object?>{'uri': uri},
    );
    return result ?? 0;
  }
}
