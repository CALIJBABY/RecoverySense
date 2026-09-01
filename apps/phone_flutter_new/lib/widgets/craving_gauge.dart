import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class CravingGauge extends StatelessWidget {
  const CravingGauge({
    super.key,
    required this.probability,
    this.timestamp,
  });

  final double? probability;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final normalized = probability?.clamp(0.0, 1.0).toDouble();
    final percent = normalized == null ? null : (normalized * 100).round();

    return Semantics(
      container: true,
      label: percent == null
          ? 'No current model estimate is available.'
          : 'Current model-estimated elevated craving probability is $percent percent.',
      child: Column(
        children: [
          SizedBox(
            width: 238,
            height: 150,
            child: Stack(
              children: [
                CustomPaint(
                  size: const Size(238, 142),
                  painter: _GaugePainter(progress: normalized ?? 0),
                ),
                Align(
                  alignment: const Alignment(0, 0.32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        percent == null ? '--' : '$percent%',
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textBlack,
                            ),
                      ),
                      Text(
                        percent == null ? 'Learning' : 'model estimate',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Positioned(
                  left: 13,
                  bottom: 0,
                  child: Text('0%', style: TextStyle(color: AppTheme.textMuted)),
                ),
                const Positioned(
                  right: 5,
                  bottom: 0,
                  child: Text('100%', style: TextStyle(color: AppTheme.textMuted)),
                ),
              ],
            ),
          ),
          Text(
            timestamp == null ? 'No recent prediction' : _relativeTime(timestamp!),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  static String _relativeTime(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.isNegative || difference.inMinutes < 1) {
      return 'Updated just now';
    }
    if (difference.inMinutes < 60) {
      return 'Updated ${difference.inMinutes} min ago';
    }
    return 'Updated ${difference.inHours} h ago';
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.82);
    final radius = math.min(size.width * 0.42, size.height * 0.72);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = math.pi;
    const sweep = math.pi;
    final trackPaint = Paint()
      ..color = AppTheme.softGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    final valuePaint = Paint()
      ..color = AppTheme.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweep, false, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        startAngle,
        sweep * progress.clamp(0.0, 1.0).toDouble(),
        false,
        valuePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
