import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:archive/archive_io.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';

class ResearchDataExportResult {
  const ResearchDataExportResult({
    required this.file,
    required this.counts,
    required this.generatedAtUtc,
  });

  final File file;
  final Map<String, int> counts;
  final DateTime generatedAtUtc;
}

class ResearchDataExportService {
  ResearchDataExportService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  static const int exportSchemaVersion = 3;
  static const int _pageSize = 100;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<ResearchDataExportResult> createExport({
    void Function(String message)? onProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('A signed-in participant is required to export data.');
    }

    onProgress?.call('Syncing pending Firestore writes...');
    await _firestore.waitForPendingWrites();

    final generatedAt = DateTime.now().toUtc();
    final stamp = generatedAt
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final tempRoot = Directory.systemTemp;
    final exportRoot = Directory(
      '${tempRoot.path}${Platform.pathSeparator}recoverysense_exports',
    );
    await exportRoot.create(recursive: true);
    await _deleteOldWorkingDirectories(exportRoot);
    await _deleteOldExportFiles(exportRoot);

    final workDir = Directory('${exportRoot.path}/work_$stamp');
    final csvDir = Directory('${workDir.path}/csv');
    final rawDir = Directory('${workDir.path}/raw');
    await csvDir.create(recursive: true);
    await rawDir.create(recursive: true);

    final counts = <String, int>{
      'documents_total': 0,
      'sessions': 0,
      'sensor_batches': 0,
      'sensor_samples': 0,
      'ppg_batches': 0,
      'ppg_samples': 0,
      'ema_events': 0,
      'baseline_assessments': 0,
      'sleep_sessions': 0,
      'sleep_epochs': 0,
      'sleep_logs': 0,
      'sleep_mirror_sensor_batches': 0,
      'sleep_mirror_ppg_batches': 0,
      'model_predictions': 0,
      'risk_predictions': 0,
      'trigger_events': 0,
    };

    final rawSink = File('${rawDir.path}/firestore_documents.ndjson')
        .openWrite(encoding: utf8);
    final sensorSink =
        File('${csvDir.path}/sensor_readings.csv').openWrite(encoding: utf8);
    final ppgSink =
        File('${csvDir.path}/raw_ppg.csv').openWrite(encoding: utf8);
    final epochSink =
        File('${csvDir.path}/sleep_epochs.csv').openWrite(encoding: utf8);
    final sensorBatchSink =
        File('${csvDir.path}/sensor_batches.csv').openWrite(encoding: utf8);
    final ppgBatchSink =
        File('${csvDir.path}/ppg_batches.csv').openWrite(encoding: utf8);

    try {
      sensorSink.writeln(_csvRow(_sensorHeader));
      ppgSink.writeln(_csvRow(_ppgHeader));
      epochSink.writeln(_csvRow(_sleepEpochHeader));
      sensorBatchSink.writeln(_csvRow(_sensorBatchHeader));
      ppgBatchSink.writeln(_csvRow(_ppgBatchHeader));

      final participantRef = _firestore.collection('participants').doc(user.uid);

      onProgress?.call('Exporting participant metadata...');
      final participant = await participantRef.get(
        const GetOptions(source: Source.server),
      );
      if (participant.exists) {
        final participantData = participant.data()!;
        _writeRawDocument(rawSink, participant.reference.path, participantData);
        counts['documents_total'] = counts['documents_total']! + 1;
        await _writeDynamicCsv(
          File('${csvDir.path}/participant.csv'),
          <Map<String, dynamic>>[
            <String, dynamic>{
              'document_id': participant.id,
              'document_path': participant.reference.path,
              ...participantData,
            },
          ],
        );
      } else {
        await _writeDynamicCsv(
          File('${csvDir.path}/participant.csv'),
          const <Map<String, dynamic>>[],
          fallbackHeader: _participantFallbackHeader,
        );
      }

      onProgress?.call('Exporting watch sessions and sensor data...');
      final sessionsForCsv = <Map<String, dynamic>>[];
      await for (final session in _streamCollection(
        participantRef.collection('sessions'),
      )) {
        counts['sessions'] = counts['sessions']! + 1;
        counts['documents_total'] = counts['documents_total']! + 1;
        final sessionData = session.data();
        _writeRawDocument(rawSink, session.reference.path, sessionData);
        sessionsForCsv.add(<String, dynamic>{
          'document_id': session.id,
          'document_path': session.reference.path,
          ...sessionData,
        });

        await for (final batch in _streamCollection(
          session.reference.collection('sensor_batches'),
        )) {
          counts['sensor_batches'] = counts['sensor_batches']! + 1;
          counts['documents_total'] = counts['documents_total']! + 1;
          final data = batch.data();
          _writeRawDocument(rawSink, batch.reference.path, data);
          _writeSensorBatchMetadata(
            sensorBatchSink,
            participantId: user.uid,
            sessionId: session.id,
            batchId: batch.id,
            data: data,
          );
          counts['sensor_samples'] = counts['sensor_samples']! +
              _writeSensorSamples(
                sensorSink,
                participantId: user.uid,
                sessionId: session.id,
                batchId: batch.id,
                sessionData: sessionData,
                batchData: data,
              );
        }

        await for (final batch in _streamCollection(
          session.reference.collection('ppg_batches'),
        )) {
          counts['ppg_batches'] = counts['ppg_batches']! + 1;
          counts['documents_total'] = counts['documents_total']! + 1;
          final data = batch.data();
          _writeRawDocument(rawSink, batch.reference.path, data);
          _writePpgBatchMetadata(
            ppgBatchSink,
            participantId: user.uid,
            sessionId: session.id,
            batchId: batch.id,
            data: data,
          );
          counts['ppg_samples'] = counts['ppg_samples']! +
              _writePpgSamples(
                ppgSink,
                participantId: user.uid,
                sessionId: session.id,
                batchId: batch.id,
                sessionData: sessionData,
                batchData: data,
              );
        }
      }
      await _writeDynamicCsv(
        File('${csvDir.path}/sessions.csv'),
        sessionsForCsv,
        fallbackHeader: _sessionFallbackHeader,
      );

      onProgress?.call('Exporting one-time baseline assessment...');
      final baselineRows = await _exportSimpleCollection(
        participantRef.collection('baseline_assessments'),
        rawSink: rawSink,
        countKey: 'baseline_assessments',
        counts: counts,
      );
      await _writeDynamicCsv(
        File('${csvDir.path}/baseline_assessments.csv'),
        baselineRows,
        fallbackHeader: _baselineFallbackHeader,
      );

      onProgress?.call('Exporting EMA responses...');
      final emaRows = await _exportSimpleCollection(
        participantRef.collection('ema_events'),
        rawSink: rawSink,
        countKey: 'ema_events',
        counts: counts,
      );
      await _writeDynamicCsv(
        File('${csvDir.path}/ema_events.csv'),
        emaRows,
        fallbackHeader: _emaFallbackHeader,
      );

      onProgress?.call('Exporting sleep sessions and epochs...');
      final sleepSessionRows = <Map<String, dynamic>>[];
      await for (final sleepSession in _streamCollection(
        participantRef.collection('sleep_sessions'),
      )) {
        counts['sleep_sessions'] = counts['sleep_sessions']! + 1;
        counts['documents_total'] = counts['documents_total']! + 1;
        final sessionData = sleepSession.data();
        _writeRawDocument(
          rawSink,
          sleepSession.reference.path,
          sessionData,
        );
        sleepSessionRows.add(<String, dynamic>{
          'document_id': sleepSession.id,
          'document_path': sleepSession.reference.path,
          ...sessionData,
        });

        await for (final epoch in _streamCollection(
          sleepSession.reference.collection('epochs'),
        )) {
          counts['sleep_epochs'] = counts['sleep_epochs']! + 1;
          counts['documents_total'] = counts['documents_total']! + 1;
          final epochData = epoch.data();
          _writeRawDocument(rawSink, epoch.reference.path, epochData);
          epochSink.writeln(_csvRow(<Object?>[
            user.uid,
            sleepSession.id,
            epoch.id,
            epochData['batch_id'],
            epochData['epoch_start_ms'],
            _isoFromMs(epochData['epoch_start_ms']),
            epochData['epoch_end_ms'],
            _isoFromMs(epochData['epoch_end_ms']),
            epochData['sleep_probability'],
            epochData['is_sleep'],
            epochData['movement_std_g'],
            epochData['mean_gravity_deviation_g'],
            epochData['mean_gyroscope_rad_s'],
            epochData['mean_heart_rate'],
            epochData['step_events'],
            epochData['off_body_fraction'],
            epochData['data_coverage'],
            epochData['watch_schema_version'],
            epochData['heart_rate_quality_semantics_version'],
            epochData['estimator_version'],
          ]));
        }

        // These are deliberate mirrors of canonical session batches. Preserve
        // them in the lossless NDJSON export, but do not duplicate them in the
        // analysis CSV files.
        await for (final mirror in _streamCollection(
          sleepSession.reference.collection('sensor_batches'),
        )) {
          counts['sleep_mirror_sensor_batches'] =
              counts['sleep_mirror_sensor_batches']! + 1;
          counts['documents_total'] = counts['documents_total']! + 1;
          _writeRawDocument(rawSink, mirror.reference.path, mirror.data());
        }
        await for (final mirror in _streamCollection(
          sleepSession.reference.collection('ppg_batches'),
        )) {
          counts['sleep_mirror_ppg_batches'] =
              counts['sleep_mirror_ppg_batches']! + 1;
          counts['documents_total'] = counts['documents_total']! + 1;
          _writeRawDocument(rawSink, mirror.reference.path, mirror.data());
        }
      }
      await _writeDynamicCsv(
        File('${csvDir.path}/sleep_sessions.csv'),
        sleepSessionRows,
        fallbackHeader: _sleepSessionFallbackHeader,
      );

      onProgress?.call('Exporting sleep check-ins...');
      final sleepLogRows = await _exportSimpleCollection(
        participantRef.collection('sleep_logs'),
        rawSink: rawSink,
        countKey: 'sleep_logs',
        counts: counts,
      );
      await _writeDynamicCsv(
        File('${csvDir.path}/sleep_logs.csv'),
        sleepLogRows,
        fallbackHeader: _sleepLogFallbackHeader,
      );

      // Optional/future participant-level collections. Empty collections simply
      // generate empty CSV files with no effect on the export.
      for (final collectionName in const <String>[
        'model_predictions',
        'risk_predictions',
        'trigger_events',
      ]) {
        onProgress?.call('Checking $collectionName...');
        final rows = await _exportSimpleCollection(
          participantRef.collection(collectionName),
          rawSink: rawSink,
          countKey: collectionName,
          counts: counts,
        );
        await _writeDynamicCsv(
          File('${csvDir.path}/$collectionName.csv'),
          rows,
        );
      }
    } finally {
      await rawSink.flush();
      await rawSink.close();
      await sensorSink.flush();
      await sensorSink.close();
      await ppgSink.flush();
      await ppgSink.close();
      await epochSink.flush();
      await epochSink.close();
      await sensorBatchSink.flush();
      await sensorBatchSink.close();
      await ppgBatchSink.flush();
      await ppgBatchSink.close();
    }

    onProgress?.call('Writing export manifest...');
    await File('${workDir.path}/manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'export_schema_version': exportSchemaVersion,
        'generated_at_utc': generatedAt.toIso8601String(),
        'participant_id': user.uid,
        'scope': 'signed_in_participant_firestore_research_data',
        'firebase_auth_credentials_included': false,
        'synthetic_labels_added': false,
        'raw_format': 'NDJSON; one Firestore document per line',
        'analysis_format': 'CSV',
        'counts': counts,
      }),
      encoding: utf8,
    );

    await File('${workDir.path}/README.txt').writeAsString(
      _readmeText(generatedAt, user.uid),
      encoding: utf8,
    );

    onProgress?.call('Compressing export...');
    final zipPath =
        '${exportRoot.path}/RecoverySense_export_$stamp.zip';
    final zipEncoder = ZipFileEncoder();
    zipEncoder.create(zipPath);
    await zipEncoder.addDirectory(workDir, includeDirName: false);
    await zipEncoder.close();
    await workDir.delete(recursive: true);

    return ResearchDataExportResult(
      file: File(zipPath),
      counts: Map<String, int>.unmodifiable(counts),
      generatedAtUtc: generatedAt,
    );
  }

  Future<ShareResult> shareExport(
    ResearchDataExportResult export, {
    Rect? sharePositionOrigin,
  }) {
    return SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(export.file.path)],
        title: 'RecoverySense Research Data Export',
        subject: 'RecoverySense research data export',
        text: 'RecoverySense participant research-data export. '
            'The ZIP includes lossless Firestore NDJSON plus analysis-ready CSV files.',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Deletes the app's temporary copy after the platform share/save operation.
  /// Any copy explicitly saved by the user through the system share sheet remains.
  Future<void> deleteTemporaryExport(ResearchDataExportResult export) async {
    try {
      if (await export.file.exists()) {
        await export.file.delete();
      }
    } catch (_) {
      // Cleanup failure must not convert a completed export into a user error.
    }
  }

  Future<List<Map<String, dynamic>>> _exportSimpleCollection(
    CollectionReference<Map<String, dynamic>> collection, {
    required IOSink rawSink,
    required String countKey,
    required Map<String, int> counts,
  }) async {
    final rows = <Map<String, dynamic>>[];
    await for (final doc in _streamCollection(collection)) {
      counts[countKey] = (counts[countKey] ?? 0) + 1;
      counts['documents_total'] = counts['documents_total']! + 1;
      final data = doc.data();
      _writeRawDocument(rawSink, doc.reference.path, data);
      rows.add(<String, dynamic>{
        'document_id': doc.id,
        'document_path': doc.reference.path,
        ...data,
      });
    }
    return rows;
  }

  Stream<QueryDocumentSnapshot<Map<String, dynamic>>> _streamCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async* {
    DocumentSnapshot<Map<String, dynamic>>? lastDocument;
    while (true) {
      Query<Map<String, dynamic>> query = collection
          .orderBy(FieldPath.documentId)
          .limit(_pageSize);
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }
      final page = await query.get(
        const GetOptions(source: Source.server),
      );
      if (page.docs.isEmpty) return;
      for (final doc in page.docs) {
        yield doc;
      }
      lastDocument = page.docs.last;
      if (page.docs.length < _pageSize) return;
    }
  }


  void _writeSensorBatchMetadata(
    IOSink sink, {
    required String participantId,
    required String sessionId,
    required String batchId,
    required Map<String, dynamic> data,
  }) {
    sink.writeln(_csvRow(<Object?>[
      participantId,
      sessionId,
      data['batch_id'] ?? batchId,
      data['sequence'],
      data['source'],
      data['recording_mode'],
      data['sleep_session_id'],
      data['sampling_rate_hz'],
      data['sample_count'],
      data['start_time_ms'],
      _isoFromMs(data['start_time_ms']),
      data['end_time_ms'],
      _isoFromMs(data['end_time_ms']),
      data['watch_created_at_ms'],
      _isoFromMs(data['watch_created_at_ms']),
      _toCsvValue(data['received_at']),
      data['watch_schema_version'],
      data['schema_version'],
      _toCsvValue(data['sensor_capabilities']),
      _toCsvValue(data['quality_summary']),
    ]));
  }

  void _writePpgBatchMetadata(
    IOSink sink, {
    required String participantId,
    required String sessionId,
    required String batchId,
    required Map<String, dynamic> data,
  }) {
    sink.writeln(_csvRow(<Object?>[
      participantId,
      sessionId,
      data['batch_id'] ?? batchId,
      data['sequence'],
      data['source'],
      data['recording_mode'],
      data['sleep_session_id'],
      data['sampling_rate_hz'],
      data['sample_count'],
      data['start_time_ms'],
      _isoFromMs(data['start_time_ms']),
      data['end_time_ms'],
      _isoFromMs(data['end_time_ms']),
      data['watch_created_at_ms'],
      _isoFromMs(data['watch_created_at_ms']),
      _toCsvValue(data['received_at']),
      data['watch_schema_version'],
      data['schema_version'],
      _toCsvValue(data['quality_summary']),
    ]));
  }

  int _writeSensorSamples(
    IOSink sink, {
    required String participantId,
    required String sessionId,
    required String batchId,
    required Map<String, dynamic> sessionData,
    required Map<String, dynamic> batchData,
  }) {
    final samples = batchData['samples'];
    if (samples is! List) return 0;
    var written = 0;
    for (final rawSample in samples) {
      if (rawSample is! Map) continue;
      final sample = Map<String, dynamic>.from(rawSample);
      sink.writeln(_csvRow(<Object?>[
        participantId,
        sessionId,
        batchData['recording_mode'] ?? sessionData['recording_mode'],
        batchData['sleep_session_id'] ?? sessionData['sleep_session_id'],
        batchData['batch_id'] ?? batchId,
        batchData['sequence'],
        batchData['sampling_rate_hz'] ?? sessionData['sampling_rate_hz'],
        batchData['watch_schema_version'],
        batchData['schema_version'],
        sample['timestamp_ms'],
        _isoFromMs(sample['timestamp_ms']),
        sample['heart_rate'],
        sample['raw_heart_rate'],
        sample['heart_rate_valid'],
        sample['heart_rate_quality_code'],
        sample['heart_rate_quality_reason'],
        sample['heart_rate_outlier_flag'],
        sample['heart_rate_timestamp_ms'],
        _isoFromMs(sample['heart_rate_timestamp_ms']),
        sample['heart_rate_age_ms'],
        sample['heart_rate_accuracy'],
        sample['accel_x_ms2'],
        sample['accel_y_ms2'],
        sample['accel_z_ms2'],
        sample['acceleration_g'],
        sample['accelerometer_accuracy'],
        sample['gyro_x_rad_s'],
        sample['gyro_y_rad_s'],
        sample['gyro_z_rad_s'],
        sample['gyro_magnitude_rad_s'],
        sample['gyro_timestamp_ms'],
        _isoFromMs(sample['gyro_timestamp_ms']),
        sample['gyroscope_accuracy'],
        sample['step_count'],
        sample['step_detected'],
        _normalizedOffBody(
          sample['off_body'],
          _toInt(batchData['watch_schema_version']),
          _toInt(batchData['schema_version']),
        ),
        sample['screen_interactive'],
      ]));
      written++;
    }
    return written;
  }

  int _writePpgSamples(
    IOSink sink, {
    required String participantId,
    required String sessionId,
    required String batchId,
    required Map<String, dynamic> sessionData,
    required Map<String, dynamic> batchData,
  }) {
    final timestamps = _asList(batchData['timestamps_ms']);
    final green = _asList(batchData['green_adc']);
    final infrared = _asList(batchData['infrared_adc']);
    final red = _asList(batchData['red_adc']);
    final greenStatus = _asList(batchData['green_status']);
    final infraredStatus = _asList(batchData['infrared_status']);
    final redStatus = _asList(batchData['red_status']);
    final length = timestamps.length;
    if (length == 0 ||
        green.length != length ||
        infrared.length != length ||
        red.length != length ||
        greenStatus.length != length ||
        infraredStatus.length != length ||
        redStatus.length != length) {
      return 0;
    }

    for (var i = 0; i < length; i++) {
      sink.writeln(_csvRow(<Object?>[
        participantId,
        sessionId,
        batchData['recording_mode'] ?? sessionData['recording_mode'],
        batchData['sleep_session_id'] ?? sessionData['sleep_session_id'],
        batchData['batch_id'] ?? batchId,
        batchData['sequence'],
        batchData['sampling_rate_hz'] ?? sessionData['ppg_sampling_rate_hz'],
        batchData['source'] ?? sessionData['ppg_source'],
        timestamps[i],
        _isoFromMs(timestamps[i]),
        green[i],
        infrared[i],
        red[i],
        greenStatus[i],
        infraredStatus[i],
        redStatus[i],
      ]));
    }
    return length;
  }

  Future<void> _writeDynamicCsv(
    File file,
    List<Map<String, dynamic>> rows, {
    List<String> fallbackHeader = const <String>[],
  }) async {
    if (rows.isEmpty) {
      await file.writeAsString(
        fallbackHeader.isEmpty ? '' : '${_csvRow(fallbackHeader)}\n',
        encoding: utf8,
      );
      return;
    }

    final flattened = rows.map(_flattenMap).toList(growable: false);
    final keys = <String>{};
    for (final row in flattened) {
      keys.addAll(row.keys);
    }
    final orderedKeys = keys.toList()..sort();

    final sink = file.openWrite(encoding: utf8);
    try {
      sink.writeln(_csvRow(orderedKeys));
      for (final row in flattened) {
        sink.writeln(_csvRow(
          orderedKeys.map((key) => row[key]).toList(growable: false),
        ));
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Map<String, Object?> _flattenMap(Map<String, dynamic> source) {
    final result = <String, Object?>{};

    void visit(String prefix, Object? value) {
      if (value is Map) {
        if (value.isEmpty && prefix.isNotEmpty) {
          result[prefix] = '{}';
          return;
        }
        for (final entry in value.entries) {
          final key = entry.key.toString();
          visit(prefix.isEmpty ? key : '$prefix.$key', entry.value);
        }
        return;
      }
      if (value is Iterable && value is! String) {
        result[prefix] = jsonEncode(_toJsonValue(value));
        return;
      }
      result[prefix] = _toCsvValue(value);
    }

    for (final entry in source.entries) {
      visit(entry.key, entry.value);
    }
    return result;
  }

  void _writeRawDocument(
    IOSink sink,
    String path,
    Map<String, dynamic> data,
  ) {
    sink.writeln(jsonEncode(<String, Object?>{
      'path': path,
      'data': _toJsonValue(data),
    }));
  }

  Object? _toJsonValue(Object? value) {
    if (value == null ||
        value is String ||
        value is num ||
        value is bool) {
      return value;
    }
    if (value is Timestamp) {
      return <String, Object?>{
        '__firestore_type': 'timestamp',
        'iso8601_utc': value.toDate().toUtc().toIso8601String(),
        'milliseconds_since_epoch': value.millisecondsSinceEpoch,
      };
    }
    if (value is DateTime) {
      return <String, Object?>{
        '__dart_type': 'datetime',
        'iso8601_utc': value.toUtc().toIso8601String(),
        'milliseconds_since_epoch': value.toUtc().millisecondsSinceEpoch,
      };
    }
    if (value is GeoPoint) {
      return <String, Object?>{
        '__firestore_type': 'geopoint',
        'latitude': value.latitude,
        'longitude': value.longitude,
      };
    }
    if (value is Blob) {
      return <String, Object?>{
        '__firestore_type': 'blob',
        'base64': base64Encode(value.bytes),
      };
    }
    if (value is DocumentReference) {
      return <String, Object?>{
        '__firestore_type': 'document_reference',
        'path': value.path,
      };
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _toJsonValue(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_toJsonValue).toList(growable: false);
    }
    return value.toString();
  }

  Object? _toCsvValue(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is GeoPoint) return '${value.latitude},${value.longitude}';
    if (value is Blob) return base64Encode(value.bytes);
    if (value is DocumentReference) return value.path;
    if (value is Map || value is Iterable) return jsonEncode(_toJsonValue(value));
    return value;
  }

  static List<dynamic> _asList(Object? value) =>
      value is List ? value : const <dynamic>[];

  static String? _isoFromMs(Object? value) {
    final ms = _toInt(value);
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
        .toIso8601String();
  }

  static int? _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static Object? _normalizedOffBody(
    Object? value,
    int? watchSchemaVersion,
    int? storageSchemaVersion,
  ) {
    if (value == null) return null;
    bool? parsed;
    if (value is bool) {
      parsed = value;
    } else if (value is num) {
      parsed = value != 0;
    } else {
      final text = value.toString().toLowerCase();
      if (text == 'true' || text == '1') parsed = true;
      if (text == 'false' || text == '0') parsed = false;
    }
    if (parsed == null) return value;
    // Storage schema 5+ is written by the corrected phone parser and already
    // contains normalized true=off-body semantics, even when it ingested a
    // pending batch from an older watch. Historical storage schema <=4 kept
    // the old inverted watch value and therefore needs normalization on export.
    if ((storageSchemaVersion ?? 0) >= 5) return parsed;
    return (watchSchemaVersion ?? 1) <= 4 ? !parsed : parsed;
  }

  static String _csvRow(Iterable<Object?> cells) =>
      cells.map(_csvCell).join(',');

  static String _csvCell(Object? value) {
    if (value == null) return '';
    final text = value.toString();
    if (text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  Future<void> _deleteOldWorkingDirectories(Directory root) async {
    if (!await root.exists()) return;
    await for (final entity in root.list()) {
      if (entity is Directory &&
          entity.path.split(Platform.pathSeparator).last.startsWith('work_')) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // A stale working directory should never block a new export.
        }
      }
    }
  }

  Future<void> _deleteOldExportFiles(Directory root) async {
    if (!await root.exists()) return;
    await for (final entity in root.list()) {
      if (entity is File) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('RecoverySense_export_') && name.endsWith('.zip')) {
          try {
            await entity.delete();
          } catch (_) {
            // A stale temporary ZIP should not block a new export.
          }
        }
      }
    }
  }

  static String _readmeText(DateTime generatedAt, String participantId) => '''
RecoverySense research data export
==================================

Generated UTC: ${generatedAt.toIso8601String()}
Participant ID: $participantId
Export schema version: $exportSchemaVersion

Contents
--------
manifest.json
  Export metadata and record counts.

raw/firestore_documents.ndjson
  Lossless participant-scoped Firestore export. Each line contains the
  original document path and all stored fields. Firestore timestamps,
  geopoints, blobs, and document references are explicitly tagged.

csv/participant.csv
  Participant document fields in a one-row analysis-friendly table.

csv/sensor_batches.csv
  One row per standard sensor batch with metadata, capabilities, and quality
  summary fields.

csv/sensor_readings.csv
  One row per standard watch sensor sample. This is the preferred file for
  analysis-ready BPM, preserved raw BPM, HR validity/rejection reason, temporal
  outlier flags, accelerometer, gyroscope, steps, screen-state, and quality analysis.
  Historical storage schema <=4 off-body values are normalized in this CSV; lossless
  original documents remain available in raw/firestore_documents.ndjson.

csv/ppg_batches.csv
  One row per raw PPG batch with metadata and quality summary fields.

csv/raw_ppg.csv
  One row per raw PPG sample. This file remains empty until raw PPG collection
  is enabled and actual PPG documents exist.

csv/baseline_assessments.csv
  One-time participant baseline context. Baseline fields are exported for
  research stratification/ablation and are not treated as learned model weights.

csv/ema_events.csv
  Repeated EMA responses and prompt/response metadata, including local clock
  minute and timezone offset for v0.5+ records.

csv/sessions.csv
  Watch-session metadata and quality summaries.

csv/sleep_sessions.csv
  Automatic overnight recording summaries and confirmation fields.

csv/sleep_epochs.csv
  One row per estimated sleep/wake epoch.

csv/sleep_logs.csv
  Manual or generated nightly sleep summaries used as craving-model context.

csv/model_predictions.csv
csv/risk_predictions.csv
csv/trigger_events.csv
  Participant-scoped model/trigger records. risk_predictions can include the
  selected model probability plus the companion decision-tree top contributors
  and model/version provenance. Files are empty when the collection is absent.

Important notes
---------------
- The export contains only the currently signed-in participant's Firestore
  research data. It uses server reads after pending Firestore writes are synced,
  so an internet connection is required for a complete export.
- Firebase Authentication credentials and passwords are NOT exported.
- No synthetic craving labels or generated research outcomes are added.
- Sleep-session sensor/PPG mirror documents are preserved in the raw NDJSON
  file. They are not duplicated in sensor_readings.csv or raw_ppg.csv.
- Keep this ZIP protected because it can contain sensitive research data.
''';



  static const List<String> _participantFallbackHeader = <String>[
    'document_id',
    'document_path',
    'participant_id',
    'last_seen_at',
    'schema_version',
  ];

  static const List<String> _sessionFallbackHeader = <String>[
    'document_id',
    'document_path',
    'participant_id',
    'session_id',
    'source',
    'recording_mode',
    'sleep_session_id',
    'started_at_ms',
    'last_sample_at_ms',
    'sampling_rate_hz',
    'last_batch_sequence',
    'schema_version',
  ];

  static const List<String> _emaFallbackHeader = <String>[
    'document_id',
    'document_path',
    'participant_id',
    'session_id',
    'timestamp_ms',
    'prompted_at_ms',
    'opened_at_ms',
    'submitted_at_ms',
    'response_delay_ms',
    'local_minute_of_day',
    'timezone_offset_minutes',
    'craving_score',
    'source',
    'response_device',
    'trigger_reason',
    'trigger_probability',
    'model_version',
    'model_threshold',
    'window_start_ms',
    'window_end_ms',
    'schema_version',
  ];

  static const List<String> _baselineFallbackHeader = <String>[
    'document_id',
    'document_path',
    'participant_id',
    'target_behavior',
    'goal',
    'days_engaged_past_30',
    'typical_craving_score',
    'typical_episode_minutes',
    'self_reported_high_risk_time_blocks',
    'self_reported_high_risk_days',
    'common_triggers',
    'motives',
    'schedule_regularity',
    'typical_bedtime_minute_of_day',
    'typical_wake_minute_of_day',
    'activity_level',
    'confidence_to_resist_score',
    'typical_stress_score',
    'assessment_version',
    'schema_version',
    'completed',
    'completed_at',
  ];

  static const List<String> _sleepSessionFallbackHeader = <String>[
    'document_id',
    'document_path',
    'participant_id',
    'sleep_session_id',
    'status',
    'recording_start_ms',
    'recording_end_ms',
    'reported_sleep_onset_ms',
    'reported_wake_ms',
    'predicted_sleep_onset_ms',
    'predicted_wake_ms',
    'estimated_total_sleep_minutes',
    'estimated_waso_minutes',
    'estimated_sleep_efficiency',
    'sleep_quality',
    'rested_score',
    'reported_awakenings',
    'watch_removed',
    'confidence',
    'model_version',
    'schema_version',
  ];

  static const List<String> _sleepLogFallbackHeader = <String>[
    'document_id',
    'document_path',
    'participant_id',
    'bedtime_utc',
    'wake_time_utc',
    'time_in_bed_minutes',
    'total_sleep_minutes',
    'sleep_efficiency',
    'sleep_quality',
    'awakenings',
    'wake_after_sleep_onset_minutes',
    'rested_score',
    'timezone_offset_minutes',
    'source',
    'schema_version',
  ];


  static const List<String> _sensorBatchHeader = <String>[
    'participant_id',
    'session_id',
    'batch_id',
    'sequence',
    'source',
    'recording_mode',
    'sleep_session_id',
    'sampling_rate_hz',
    'sample_count',
    'start_time_ms',
    'start_time_utc',
    'end_time_ms',
    'end_time_utc',
    'watch_created_at_ms',
    'watch_created_at_utc',
    'received_at_utc',
    'watch_schema_version',
    'schema_version',
    'sensor_capabilities_json',
    'quality_summary_json',
  ];

  static const List<String> _ppgBatchHeader = <String>[
    'participant_id',
    'session_id',
    'batch_id',
    'sequence',
    'source',
    'recording_mode',
    'sleep_session_id',
    'sampling_rate_hz',
    'sample_count',
    'start_time_ms',
    'start_time_utc',
    'end_time_ms',
    'end_time_utc',
    'watch_created_at_ms',
    'watch_created_at_utc',
    'received_at_utc',
    'watch_schema_version',
    'schema_version',
    'quality_summary_json',
  ];

  static const List<String> _sensorHeader = <String>[
    'participant_id',
    'session_id',
    'recording_mode',
    'sleep_session_id',
    'batch_id',
    'batch_sequence',
    'batch_sampling_rate_hz',
    'watch_schema_version',
    'storage_schema_version',
    'timestamp_ms',
    'timestamp_utc',
    'heart_rate',
    'raw_heart_rate',
    'heart_rate_valid',
    'heart_rate_quality_code',
    'heart_rate_quality_reason',
    'heart_rate_outlier_flag',
    'heart_rate_timestamp_ms',
    'heart_rate_timestamp_utc',
    'heart_rate_age_ms',
    'heart_rate_accuracy',
    'accel_x_ms2',
    'accel_y_ms2',
    'accel_z_ms2',
    'acceleration_g',
    'accelerometer_accuracy',
    'gyro_x_rad_s',
    'gyro_y_rad_s',
    'gyro_z_rad_s',
    'gyro_magnitude_rad_s',
    'gyro_timestamp_ms',
    'gyro_timestamp_utc',
    'gyroscope_accuracy',
    'step_count',
    'step_detected',
    'off_body',
    'screen_interactive',
  ];

  static const List<String> _ppgHeader = <String>[
    'participant_id',
    'session_id',
    'recording_mode',
    'sleep_session_id',
    'batch_id',
    'batch_sequence',
    'sampling_rate_hz',
    'source',
    'timestamp_ms',
    'timestamp_utc',
    'green_adc',
    'infrared_adc',
    'red_adc',
    'green_status',
    'infrared_status',
    'red_status',
  ];

  static const List<String> _sleepEpochHeader = <String>[
    'participant_id',
    'sleep_session_id',
    'document_id',
    'batch_id',
    'epoch_start_ms',
    'epoch_start_utc',
    'epoch_end_ms',
    'epoch_end_utc',
    'sleep_probability',
    'is_sleep',
    'movement_std_g',
    'mean_gravity_deviation_g',
    'mean_gyroscope_rad_s',
    'mean_heart_rate',
    'step_events',
    'off_body_fraction',
    'data_coverage',
    'watch_schema_version',
    'heart_rate_quality_semantics_version',
    'estimator_version',
  ];
}
