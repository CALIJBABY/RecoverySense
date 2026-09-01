import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/section_card.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to view EMA history.')),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('participants')
        .doc(user.uid)
        .collection('ema_events')
        .orderBy('timestamp_ms', descending: true)
        .limit(20)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load history: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final events = snapshot.data!.docs;
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              SectionCard(
                title: 'Recent EMA Check-Ins',
                child: events.isEmpty
                    ? const Text('No EMA responses have been submitted yet.')
                    : Column(
                        children: events.map((document) {
                          final event = document.data();
                          final score = event['craving_score'];
                          final source = event['source'] ?? 'manual';
                          final timestampMs = event['timestamp_ms'];
                          final timestamp = timestampMs is num
                              ? DateTime.fromMillisecondsSinceEpoch(
                                  timestampMs.toInt(),
                                  isUtc: true,
                                ).toLocal()
                              : null;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Text(score?.toString() ?? '--'),
                            ),
                            title: Text('Craving ${score ?? '--'}/10'),
                            subtitle: Text(
                              '${timestamp == null ? 'Unknown time' : _formatTime(timestamp)} · '
                              '${source.toString().replaceAll('_', ' ')}',
                            ),
                          );
                        }).toList(growable: false),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}
