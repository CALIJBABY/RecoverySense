# RecoverySense Participant UI Design System — 0.5.3

## Purpose

This document defines the current phone and Wear OS participant interface. It supersedes the 0.5.0 and 0.5.1 visual specifications while preserving their research safeguards.

## Palette

The primary action green was sampled from the supplied rounded-button reference.

| Token | Value | Use |
|---|---:|---|
| Primary green | `#4F9B17` | Filled buttons, active gauge/bar segments, selected navigation |
| Dark green | `#356E0C` | Icons and emphasis on pale surfaces |
| Soft green | `#EAF6DF` | Navigation indicator, cards, inactive score segments |
| App background | `#F8FBF4` | Screen background |
| Border green | `#CDE4B9` | Card and control outlines |
| Primary text | `#111111` | Body text and text on the brighter primary button |
| Muted text | `#5D655B` | Secondary labels and timestamps |

Use dark text on the brighter primary green. Do not assume white text has adequate contrast on every bright-green state.

## Shape and spacing

- Primary phone action: 50 logical px high, 14 px radius.
- Secondary phone action: at least 48 logical px high, 14 px radius.
- Standard card: 20 px radius.
- Compact metric/factor card: 16 px radius.
- Wear primary action and navigation: 14 dp radius.
- Avoid square participant actions and dense full-width text blocks.

## Phone navigation

The fixed bottom navigation contains five destinations:

1. Home
2. Live
3. Check-in
4. Sleep
5. History

Only the selected destination shows its text label; all destinations retain icons and accessibility labels. Settings remains the top-right dashboard action and is not moved into the bottom navigation.

## Screen responsibilities

### Home

- **Craving Risk Now** model probability gauge.
- Actual selected model badge.
- Three highest positive local explanation patterns.
- Separate latest 0–10 check-in line.
- Higher-Risk Times descriptive repeated-EMA summary after data-sufficiency safeguards.

### Live

- Watch connection state.
- Heart rate, motion, rotation, and step measurements.
- Heart-rate signal-quality status.

### Check-in

- One deliberate 0–10 craving response.
- Save remains disabled until the participant moves the control.

### Sleep

- Ten-block sleep-efficiency bar.
- Duration, estimated awakenings, and estimator confidence.
- Overnight start/stop controls, sleep/wake timeline, and deliberate morning confirmation.
- Output is labeled as an estimated sleep/wake context, not medical staging.

### History

- Recent confirmed sleep records.
- Recent craving check-ins and source/timestamp context.

## Craving-risk data contract

The gauge must never copy the latest EMA score. A participant-visible prediction must satisfy all of the following:

- probability is finite and between 0 and 1;
- timestamp and model identity are present;
- prediction is recent enough for the current dashboard;
- `participant_display_allowed` is true;
- `demo_only` is false;
- prediction schema is at least 2;
- `prediction_basis` is `sensor_window_plus_prior_context`;
- `current_ema_direct_input` is false;
- at least one recorded input modality is a wearable sensor modality.

EMA is the repeated outcome label used to train and validate the model. Available sleep and local-time context may be included alongside recent wearable sensor windows.

## Three explanation boxes

- Parse only positive finite contributors marked `increasing`.
- Sort by contribution in descending order.
- Display at most three.
- Refresh from the Firestore prediction stream whenever a new approved prediction arrives.
- Show the local probability-point contribution for transparency.
- If the selected model is not the interpretability model, disclose through the information tooltip that the boxes come from a companion decision tree trained on the same features. They are not exact random-forest weights.
- Never describe predictive contributors as causes.

## Wear OS interface

The watch has two compact participant pages selected from rounded bottom controls:

- **Sensors:** heart rate, motion, rotation, and steps.
- **Check-in:** deliberate 0–10 craving slider and rounded save action.

Engineering recorder diagnostics remain outside the participant-facing watch surface.
