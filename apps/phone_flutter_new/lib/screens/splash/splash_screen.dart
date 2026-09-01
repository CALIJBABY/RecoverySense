import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../services/firebase/baseline_assessment_repository.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _startupFailed = false;

  @override
  void initState() {
    super.initState();
    _routeAfterStartup();
  }

  Future<void> _routeAfterStartup() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final signedIn = FirebaseAuth.instance.currentUser != null;
    if (!signedIn) {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
      return;
    }

    try {
      final complete = await BaselineAssessmentRepository().isComplete();
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        complete ? AppRoutes.dashboard : AppRoutes.baseline,
      );
    } catch (error, stackTrace) {
      debugPrint('Startup baseline check failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _startupFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.favorite_border,
                size: 72,
                color: AppTheme.primaryGreen,
              ),
              const SizedBox(height: 18),
              const Text(
                AppStrings.appName,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.tagline,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              if (!_startupFailed)
                const CircularProgressIndicator()
              else ...[
                const Text(
                  'Unable to verify your baseline status. Check your connection and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    setState(() => _startupFailed = false);
                    _routeAfterStartup();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
