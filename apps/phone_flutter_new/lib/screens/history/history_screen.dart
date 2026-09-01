import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/app_bottom_navigation.dart';
import '../../widgets/section_card.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to view history.')),
      );
    }

    final participant = FirebaseFirestore.instance
        .collection('participants')
        .doc(user.uid);
    final emaStream = participant
        .collection('ema_events')
        .orderBy('timestamp_ms', descending: true)
        .limit(20)
        .snapshots();
    final sleepStream = participant
        .collection('sleep_sessions')
        .orderBy('recording_start_ms', descending: true)
        .limit(30)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      bottomNavigationBar: const AppBottomNavigation(currentIndex: 4),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: sleepStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const SectionCard(
                  title: 'Recent Sleep Check-Ins',
                  child: Text('Sleep history is temporarily unavailable. Please try again.'),
                );
              }
              if (!snapshot.hasData) {
                return const SectionCard(
                  title: 'Recent Sleep Check-Ins',
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final sessions = snapshot.data!.docs
                  .where((doc) => doc.data()['status'] == 'confirmed')
                  .take(14)
                  .toList(growable: false);
              return SectionCard(
                title: 'Recent Sleep Check-Ins',
                child: sessions.isEmpty
                    ? const Text('No confirmed sleep records yet.')
                    : Column(
                        children: sessions.map((document) {
                          final session = document.data();
                          final quality = (session['sleep_quality'] as num?)?.toInt();
                          final onsetMs = (session['reported_sleep_onset_ms'] as num?)?.toInt();
                          final wakeMs = (session['reported_wake_ms'] as num?)?.toInt();
                          final onset = onsetMs == null
                              ? null
                              : DateTime.fromMillisecondsSinceEpoch(onsetMs, isUtc: true).toLocal();
                          final wake = wakeMs == null
                              ? null
                              : DateTime.fromMillisecondsSinceEpoch(wakeMs, isUtc: true).toLocal();
                          final minutes = onset != null && wake != null && wake.isAfter(onset)
                              ? wake.difference(onset).inMinutes
                              : (session['estimated_total_sleep_minutes'] as num?)?.toInt();
                          final hours = minutes == null ? '--' : (minutes / 60.0).toStringAsFixed(1);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(child: Icon(Icons.bedtime_outlined)),
                            title: Text('$hours hours · quality ${quality ?? '--'}/5'),
                            subtitle: Text(
                              wake == null ? 'Wake time not available' : 'Woke ${_formatTime(wake)}',
                            ),
                          );
                        }).toList(growable: false),
                      ),
              );
            },
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: emaStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const SectionCard(
                  title: 'Recent Craving Check-Ins',
                  child: Text('Craving history is temporarily unavailable. Please try again.'),
                );
              }
              if (!snapshot.hasData) {
                return const SectionCard(
                  title: 'Recent Craving Check-Ins',
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final events = snapshot.data!.docs;
              return SectionCard(
                title: 'Recent Craving Check-Ins',
                child: events.isEmpty
                    ? const Text('No craving check-ins have been submitted yet.')
                    : Column(
                        children: events.map((document) {
                          final event = document.data();
                          final score = (event['craving_score'] as num?)?.toInt();
                          final source = event['source']?.toString() ?? 'manual';
                          final timestampMs = (event['timestamp_ms'] as num?)?.toInt();
                          final timestamp = timestampMs == null
                              ? null
                              : DateTime.fromMillisecondsSinceEpoch(
                                  timestampMs,
                                  isUtc: true,
                                ).toLocal();
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(child: Text(score?.toString() ?? '--')),
                            title: Text('Craving ${score ?? '--'}/10'),
                            subtitle: Text(
                              '${timestamp == null ? 'Time unavailable' : _formatTime(timestamp)} · '
                              '${_sourceLabel(source)}',
                            ),
                          );
                        }).toList(growable: false),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _sourceLabel(String source) => switch (source) {
        'scheduled_stratified' => 'Scheduled check-in',
        'random' => 'Research check-in',
        'model' => 'Model-timed check-in',
        'watch_manual' => 'Watch check-in',
        'manual' => 'Manual check-in',
        _ => 'Check-in',
      };

  static String _formatTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.year}-$month-$day $hour:$minute $period';
  }
}
