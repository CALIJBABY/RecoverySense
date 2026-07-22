import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../../widgets/section_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _signOut(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionCard(
            title: 'Project Status',
            child: Text(
              'Firebase, Wear OS data, notifications, and ML triggers will be added in later milestones.',
            ),
          ),
          SectionCard(
            title: 'Account',
            child: ElevatedButton(
              onPressed: () => _signOut(context),
              child: const Text('Sign Out'),
            ),
          ),
        ],
      ),
    );
  }
}
