import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth/auth_service.dart';
import '../../services/ema/ema_prompt_service.dart';
import '../../widgets/research_data_export_card.dart';
import '../../widgets/section_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _signOut(BuildContext context) async {
    await AuthService().signOut();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final promptService = EmaPromptService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionCard(
            title: 'Study Check-Ins',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RecoverySense schedules brief craving check-ins across the day to learn personal patterns without relying only on moments when an urge is already noticeable.',
                  style: TextStyle(height: 1.4),
                ),
                if (promptService.nextPromptAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Next app-active check-in window is scheduled for ${_formatDateTime(promptService.nextPromptAt!)}.',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Current prototype limitation: these reminders use an app-process timer and are not yet guaranteed after the phone app is fully terminated.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          if (kDebugMode)
            SectionCard(
              title: 'Developer Tools',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('App-active EMA scheduler'),
                    subtitle: const Text(
                      'Debug control for the morning, afternoon, and evening research schedule.',
                    ),
                    value: promptService.randomPromptsEnabled,
                    onChanged: (enabled) {
                      setState(() => promptService.setRandomPromptsEnabled(enabled));
                    },
                  ),
                  OutlinedButton(
                    onPressed: promptService.triggerTestPrompt,
                    child: const Text('Trigger test check-in'),
                  ),
                ],
              ),
            ),
          const ResearchDataExportCard(),
          SectionCard(
            title: 'Account',
            child: OutlinedButton(
              onPressed: () => _signOut(context),
              child: const Text('Sign Out'),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
