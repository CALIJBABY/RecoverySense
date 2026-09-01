import 'package:flutter/material.dart';

import '../core/theme/app_dimensions.dart';
import '../core/theme/app_theme.dart';

/// Rounded participant-facing primary action used by EMA and onboarding.
class EmaPrimaryButton extends StatelessWidget {
  const EmaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppDimensions.emaCtaHeight,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryGreen,
          foregroundColor: AppTheme.textBlack,
          disabledBackgroundColor: AppTheme.softGreen,
          disabledForegroundColor: AppTheme.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.emaCtaRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppTheme.textBlack,
                ),
              )
            : Text(label),
      ),
    );
  }
}
