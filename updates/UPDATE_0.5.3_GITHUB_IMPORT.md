# RecoverySense v0.5.3 GitHub Import

## Summary

This update brings the mature RecoverySense v0.5.3 research prototype into the existing GitHub repository while preserving the original project history.

## Major Updates

- Updated the Flutter phone application to version 0.5.3+10.
- Updated the Wear OS application to version 0.5.3, versionCode 7.
- Added the current five-section phone navigation: Home, Live, Check-in, Sleep, and History.
- Added dedicated live-sensor and sleep-context screens.
- Added heart-rate quality validation and corrected off-body sensor semantics.
- Added participant-scoped Firebase/Firestore research storage.
- Added repeated 0-10 ecological momentary assessment (EMA) collection.
- Added the current sleep/wake estimation and prior-night sleep-context pipeline.
- Added the offline machine-learning framework for craving-risk research.
- Added candidate Decision Tree, Logistic Regression, SVM, Random Forest, Gradient Boosting, and Gaussian Naive Bayes classifiers.
- Added participant-aware and temporal model-validation safeguards.
- Added a sensor-backed craving-risk dashboard that separates self-reported craving from model-generated probability.
- Added up to three positive local companion decision-tree contributors for model interpretation.
- Added research-data export and reproducible analysis tooling.
- Added expanded backend, ML, research documentation, validation tests, and repository-audit tooling.

## Research Interpretation

RecoverySense remains a research prototype.

- EMA responses are the supervised 0-10 craving labels used for future training and validation.
- Model probability is displayed separately from the participant's latest EMA response.
- The three displayed contributor patterns are predictive associations, not causal factors.
- When the selected model is not a Decision Tree, the displayed contributors come from a companion Decision Tree rather than representing exact Random Forest, SVM, or boosting weights.
- Real craving-prediction performance has not yet been established using repeated participant EMA-labeled data.
- Sleep output remains estimated sleep/wake context rather than validated sleep staging.
- Raw Samsung PPG remains disabled pending appropriate sensor access and validation.

## Version Context

This commit represents the mature v0.5.3 checkpoint before later daily-step and research-export stability patches.
