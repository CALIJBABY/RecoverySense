# Current RecoverySense Update — 0.5.3

RecoverySense 0.5.3 cleans up the phone and watch interfaces, separates major participant tasks into dedicated screens, and makes the dashboard fail closed unless a current risk value is explicitly proven to come from a completed sensor window.

## Interface refresh

- Uses the requested lighter button green, `#4F9B17`, with dark text.
- Uses 50 logical-pixel primary actions with 14-pixel rounded corners.
- Adds a five-icon phone navigation bar: Home, Live, Check-in, Sleep, and History.
- Leaves Settings in the dashboard app bar.
- Moves live watch readings to **Live Sensors** and sleep context to **Sleep**.
- Adds a ten-block sleep-efficiency score bar.
- Simplifies participant-facing copy and removes the duplicated latest-sleep summary.
- Updates the Wear OS interface to two compact pages with rounded controls: Sensors and Check-in.

## Craving-risk display

**Craving Risk Now** is no longer the latest 0–10 EMA value. It is a recent approved model probability from `risk_predictions`.

A prediction is displayable only when it includes schema-2 provenance showing that it came from a complete sensor window plus available prior context, identifies actual input modalities, explicitly says the current EMA was not used as a direct input, carries a real model name/version, is not demo data, and is approved for participant display.

The model badge shows the actual selected model. It says **Random forest** only when the persisted `model_name` is `random_forest`.

The three boxes below the gauge automatically sort and refresh the strongest positive local explanation patterns. When another model is selected, those boxes come from the companion decision tree and are not presented as exact random-forest weights or causal triggers.

See `docs/UI_DESIGN_SYSTEM_0.5.3.md` and `updates/UPDATE_0.5.3_UI_CLEANUP.md` for the exact screen, color, provenance, and validation contracts.
