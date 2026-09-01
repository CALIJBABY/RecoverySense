# RecoverySense Update 0.5.3 — UI Cleanup and Sensor-Backed Risk Dashboard

Date: 2026-08-11

## Scope

This update applies directly over the repaired 0.5.2 repository. It changes participant-facing phone/watch UI, prediction-display provenance, release metadata, tests, and documentation. It does not replace the repository or delete participant data.

## Phone interface

- Changes the primary UI green to `#4F9B17` and uses dark text on bright-green actions.
- Increases primary action corner radius to 14 px and standard card radius to 20 px.
- Adds bottom icon navigation for Home, Live, Check-in, Sleep, and History.
- Keeps Settings in its existing top-right dashboard location.
- Moves live sensor readings to their own **Live Sensors** page.
- Keeps sleep on a separate **Sleep** page and adds a ten-block sleep-efficiency bar.
- Removes the duplicated confirmed-night summary and shortens sleep/EMA copy.

## Dashboard model behavior

- Replaces the former latest-EMA Craving Now gauge with **Craving Risk Now**, driven by a recent approved model probability.
- Shows the actual persisted `model_name`; the UI says Random forest only for `random_forest`.
- Shows three sorted positive local contributor boxes, refreshed by the live prediction stream.
- Adds compact contributor point values and a tooltip explaining companion-tree provenance when another model supplies the probability.
- Shows the latest EMA separately as the latest check-in.

## Prediction provenance

Server-authored prediction records advance to schema 2 and add:

- `prediction_basis = sensor_window_plus_prior_context`
- `input_modalities`
- `current_ema_direct_input = false`
- `ema_role = training_and_validation_label`
- `sensor_window_end_ms`

The phone fails closed for legacy or incomplete records that do not prove a sensor-backed prediction basis. This prevents a direct EMA value from being displayed as a model probability.

## Wear OS participant interface

- Uses the same lighter green and rounded actions.
- Splits the visible UI into compact Sensors and Check-in pages.
- Adds small bottom symbols/labels for page switching.
- Retains deliberate-response protection before an EMA can be saved.
- Leaves background collection and Data Layer transport unchanged.

## Files added

- `apps/phone_flutter_new/lib/widgets/app_bottom_navigation.dart`
- `apps/phone_flutter_new/lib/widgets/block_score_bar.dart`
- `docs/UI_DESIGN_SYSTEM_0.5.3.md`
- `updates/UPDATE_0.5.3_UI_CLEANUP.md`

## Validation boundary

The package runs source/static checks plus Python ML/backend tests in the packaging environment. Flutter/Dart analysis, Wear OS Gradle compilation, emulator screenshots, and physical Galaxy device validation must still be run on the development machine with the required SDKs.
