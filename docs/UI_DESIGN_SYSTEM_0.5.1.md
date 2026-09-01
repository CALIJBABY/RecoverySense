# RecoverySense Participant UI Design System — Version 0.5.1

## Design intent

RecoverySense should look calm, credible, modern, and research-oriented. It should not resemble a casino, betting product, reward game, or developer diagnostics panel.

## Color palette

```text
Primary action green     #3D844B
Primary dark green       #2F6D3C
Soft green               #DDF0E2
Screen background        #F4FAF5
Card surface             #FFFFFF
Border green             #B8D5BF
Primary text             #111111
Muted text               #5B635D
```

Primary green with white button text is retained for the main participant action. The softer greens are used for gauge tracks, progress backgrounds, and supporting cards. Bright casino/neon greens and gambling-reward palettes are deliberately avoided.

## Main phone hierarchy

1. **Craving Now** — largest participant metric; semicircular 0–10 gauge.
2. **Record/Update craving rating** — full-width primary CTA.
3. **Personalized Risk Estimate** — percentage plus progress bar, explicitly labeled as a model estimate.
4. **What may be contributing** — up to three plain-language local tree contributors.
5. **Higher-Risk Times** — data-derived patterns only after data-sufficiency checks.
6. **Live Watch Data / Sleep** — supporting sensing context.
7. **History and Settings** — app-bar secondary destinations.

## Primary EMA button

Participant-facing EMA CTAs use the requested compact Groupon-like visual proportions:

```text
height             48 logical px/dp
width              full available width
corner radius      2 logical px/dp
text               18 sp/px-equivalent, bold
fill               #3D844B
foreground         white
```

This is a **visual-reference implementation**, not an assertion that Groupon publishes a universal 48 dp × 2 dp official specification. Exact physical appearance varies by device density, platform text metrics, and Groupon app version.

## Cards and spacing

- Card radius: 16 dp.
- Main horizontal screen padding: 18 dp.
- Card surface: white with a restrained border and no decorative shadow dependency.
- Technical detail should use expandable/secondary disclosure rather than top-level cards.

## Research-safe wording

Use:

- `Craving Now`
- `Personalized Risk Estimate`
- `What may be contributing`
- `Higher-Risk Times`
- `Learning your pattern`
- `These are predictive associations, not causes.`

Avoid:

- `The model knows...`
- `This caused your craving.`
- `Clinical risk` unless clinically validated.
- `Relapse prediction` unless that endpoint has actually been defined and validated.
- raw collection IDs, timestamps in milliseconds, stack traces, database errors, or model internals on primary participant screens.

## Questionnaire interaction rule

A visible default value must never silently become a research response. EMA, baseline numeric sliders, and morning sleep-confirmation fields require explicit participant interaction before saving. This protects label quality and makes a nonresponse distinguishable from a genuine midpoint/zero response.

## Watch UI

The watch should remain faster and simpler than the phone:

- RecoverySense title
- four softly styled live measurements
- one 0–10 craving question
- one full-width 48 dp `Save rating` action
- short success/failure feedback

Recorder mode, PPG state, heart-rate age, screen state, queue counts, and other engineering diagnostics remain internal/exportable and are not shown in the normal participant view.

## Accessibility/release checks

- Do not encode meaning using color alone.
- Preserve text labels for gauge/probability values.
- Maintain minimum touch targets.
- Avoid tiny participant controls.
- Provide semantic labels for custom visualizations.
- Check text scaling, compact Watch4 layouts, and Android TalkBack before field deployment.
