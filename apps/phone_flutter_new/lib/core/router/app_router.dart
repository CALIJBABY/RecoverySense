import 'package:flutter/material.dart';

import '../../screens/dashboard/dashboard_screen.dart';
import '../../screens/ema/ema_screen.dart';
import '../../screens/history/history_screen.dart';
import '../../screens/login/login_screen.dart';
import '../../screens/register/register_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/splash/splash_screen.dart';
import '../../screens/watch/watch_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const dashboard = '/dashboard';
  static const ema = '/ema';
  static const watch = '/watch';
  static const history = '/history';
  static const settings = '/settings';
}

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    Widget screen;

    switch (settings.name) {
      case AppRoutes.splash:
        screen = const SplashScreen();
        break;
      case AppRoutes.login:
        screen = const LoginScreen();
        break;
      case AppRoutes.register:
        screen = const RegisterScreen();
        break;
      case AppRoutes.dashboard:
        screen = const DashboardScreen();
        break;
      case AppRoutes.ema:
        screen = const EmaScreen();
        break;
      case AppRoutes.watch:
        screen = const WatchScreen();
        break;
      case AppRoutes.history:
        screen = const HistoryScreen();
        break;
      case AppRoutes.settings:
        screen = const SettingsScreen();
        break;
      default:
        screen = const LoginScreen();
    }

    return MaterialPageRoute(builder: (_) => screen);
  }
}
