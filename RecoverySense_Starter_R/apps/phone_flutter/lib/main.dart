import 'package:flutter/material.dart';

import 'src/core/app_theme.dart';
import 'src/features/auth/login_screen.dart';
import 'src/features/dashboard/dashboard_screen.dart';
import 'src/features/ema/ema_screen.dart';
import 'src/services/mock_auth_service.dart';
import 'src/services/mock_sensor_repository.dart';

void main() {
  runApp(const RecoverySenseApp());
}

class RecoverySenseApp extends StatefulWidget {
  const RecoverySenseApp({super.key});

  @override
  State<RecoverySenseApp> createState() => _RecoverySenseAppState();
}

class _RecoverySenseAppState extends State<RecoverySenseApp> {
  final authService = MockAuthService();
  final sensorRepository = MockSensorRepository();
  bool isLoggedIn = false;

  void _handleLogin(String email) {
    authService.signIn(email: email);
    setState(() => isLoggedIn = true);
  }

  void _handleLogout() {
    authService.signOut();
    setState(() => isLoggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RecoverySense',
      theme: buildAppTheme(),
      routes: {
        EmaScreen.routeName: (_) => EmaScreen(repository: sensorRepository),
      },
      home: isLoggedIn
          ? DashboardScreen(
              userEmail: authService.currentEmail,
              repository: sensorRepository,
              onLogout: _handleLogout,
            )
          : LoginScreen(onLogin: _handleLogin),
    );
  }
}
