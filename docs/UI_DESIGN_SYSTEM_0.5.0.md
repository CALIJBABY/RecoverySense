# RecoverySense Participant UI Design System — Version 0.5.0

## Design intent

RecoverySense should look calm, credible, and research-oriented. It should not use casino-style neon color, celebratory reward animation, urgency tricks, streak-loss pressure, or other patterns that could resemble gambling reinforcement.

## Color tokens

```text
primaryGreen      #3D844B
primaryGreenDark  #2F6D3C
softGreen         #DDF0E2
surfaceGreen      #F4FAF5
cardSurface       #FFFFFF
borderGreen       #B8D5BF
textBlack         #111111
textMuted         #5B635D
```

White text on `#3D844B` has a calculated WCAG contrast ratio of approximately 4.56:1. Normal-size primary CTA labels therefore clear the WCAG 2.2 4.5:1 Level-AA contrast threshold, but every new state/pair must be checked separately.

## Primary participant CTA

The requested Groupon Buy-action visual reference is implemented as a consistent RecoverySense component rather than copied branding:

```text
height           48 logical px / dp
width            full available content width
corner radius    2 logical px / dp
label            18 logical px, bold, centered
fill             #3D844B
text             white
```

No official universal Groupon device-independent dimension specification was identified in the official pages reviewed; 48/2 is therefore a visual-reference implementation. The 48 dp height also matches Android's recommended minimum touch-target dimension.

Component:

```text
apps/phone_flutter_new/lib/widgets/ema_primary_button.dart
```

Centralized dimensions:

```text
apps/phone_flutter_new/lib/core/theme/app_dimensions.dart
```

The Wear OS EMA button uses the same 48 dp height and 2 dp corner radius.

## Dashboard information hierarchy

Order is intentional:

1. **Craving Now** — participant's latest 0–10 self-report.
2. **Current Model Estimate** — separate algorithmic probability when available.
3. **Top decision-tree contributors** — up to three positive local companion-tree contributions.
4. **Higher-Risk Times** — descriptive personal repeated-EMA pattern after minimum data coverage.
5. Live sensor snapshot.
6. Sleep context.
7. Research-data status.

This order prevents a model prediction from masquerading as the participant's label and keeps the explanation/provenance close to the prediction it describes.

## Craving gauge

- Semicircular, restrained single-color progress arc.
- Center value is the latest self-reported 0–10 EMA.
- Missing state displays `--` rather than a synthetic/default craving score.
- Timestamp is relative to the latest completed EMA.
- Semantic label announces the score for accessibility.
- The gauge must never display model probability as if it were the self-reported craving score.

## Model explanation language

Allowed:

```text
Top decision-tree contributors
contributing to the estimate
predictive association
parallel explanation view
```

Avoid:

```text
caused your craving
triggered your addiction
proof that X causes risk
```

If the selected model is not the companion decision tree, the UI must disclose that the contributor list is not an exact decomposition of the selected model probability.

## Time-of-day language

Use **Higher-Risk Times** or **Higher-craving time windows**, not deterministic terms such as “danger time.” Display the number of eligible observations and describe the output as a personal descriptive pattern.

## Motion/reward behavior

No confetti, flashing CTA, spinning reward, variable-ratio reward animation, countdown-to-loss pattern, or gambling-like celebratory reinforcement should be added to craving reporting. Feedback should be immediate, brief, and neutral.
