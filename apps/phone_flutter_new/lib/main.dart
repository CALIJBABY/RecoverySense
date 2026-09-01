import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'services/ingestion/sensor_ingestion_service.dart';
import 'services/sleep/sleep_session_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Render the application before starting watch-backlog ingestion. This keeps
  // a large Wear OS backlog from blocking or exhausting memory during startup.
  runApp(const RecoverySenseApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_startBackgroundServices());
  });
}

Future<void> _startBackgroundServices() async {
  try {
    await SleepSessionService.instance.start();
    await SensorIngestionService.instance.start();
  } catch (error, stackTrace) {
    debugPrint('RecoverySense background-service startup failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class RecoverySenseApp extends StatelessWidget {
  const RecoverySenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RecoverySense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
