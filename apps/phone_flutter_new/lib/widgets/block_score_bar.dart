import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class BlockScoreBar extends StatelessWidget {
  const BlockScoreBar({
    super.key,
    required this.value,
    this.blocks = 10,
    this.height = 16,
  });

  /// A normalized value from 0 to 1. Null renders an empty learning state.
  final double? value;
  final int blocks;
  final double height;

  @override
  Widget build(BuildContext context) {
    final normalized = value?.clamp(0.0, 1.0).toDouble();
    final filled = normalized == null ? 0 : (normalized * blocks).round();
    final percent = normalized == null ? null : (normalized * 100).round();

    return Semantics(
      label: percent == null
          ? 'No score available yet.'
          : 'Score $percent percent, $filled of $blocks blocks filled.',
      child: Row(
        children: List<Widget>.generate(
          blocks,
          (index) => Expanded(
            child: Container(
              height: height,
              margin: EdgeInsets.only(right: index == blocks - 1 ? 0 : 4),
              decoration: BoxDecoration(
                color: index < filled
                    ? AppTheme.primaryGreen
                    : AppTheme.softGreen,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: index < filled
                      ? AppTheme.primaryGreen
                      : AppTheme.borderGreen,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
