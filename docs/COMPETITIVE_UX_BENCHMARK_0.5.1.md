# RecoverySense Competitive UX Benchmark — Version 0.5.1

**Review date:** 2026-08-11  
**Scope:** participant-facing interaction patterns only. This is not a claim that the reviewed products are clinically equivalent to RecoverySense or that their outcomes validate this prototype.

## Products reviewed

The v0.5.1 UX audit reviewed current public product material/screenshots for:

- Reframe — https://www.reframeapp.com/why-reframe
- I Am Sober — https://iamsober.com/en/site/home
- SMART Recovery mobile app — https://smartrecovery.org/smart-recovery-mobile-app
- Evive gambling support — https://www.getevive.com/
- Evive App Store listing — https://apps.apple.com/us/app/evive-gambling-support/id6450926060
- Betttr gambling recovery — https://apps.apple.com/us/app/betttr-quit-gambling-recovery/id6756128282
- GamQuit — https://apps.apple.com/us/app/gamquit/id6765764837

## Visual benchmark notes

Public screenshots were also reviewed, not just feature descriptions. Evive's current gambling-support dashboard uses a clean white surface, large numeric progress cards, restrained pale-green supporting surfaces, and a clear check-in state. Reframe's craving/toolkit screens use one conspicuous craving action with supportive tools beneath it rather than exposing technical health data. These observations support RecoverySense's current hierarchy: one dominant craving state/action, muted supporting cards, and research/model detail below the participant task.

RecoverySense deliberately does **not** copy streak-loss pressure, casino-like reward visuals, product logos, proprietary illustrations, or exact layouts. Its dashboard remains a research interface centered on EMA validity and transparent prediction provenance.

## Recurring design patterns

1. **One dominant progress/current-state element.** Strong products make the user's current state or progress visually obvious instead of presenting a technical dashboard first.
2. **A craving/urge action is easy to find.** Reframe exposes craving-management tools, SMART Recovery has a dedicated Manage Urges path, and gambling-recovery apps emphasize rapid urge support/check-ins.
3. **Daily or repeated check-ins are short.** Repeated interaction is treated as a lightweight action; education, journaling, and longer content are separate.
4. **Personal patterns/progress are summarized in plain language.** Users see understandable trends rather than raw sensor fields or backend diagnostics.
5. **Supportive, nonjudgmental wording dominates.** Current gambling-recovery products explicitly emphasize privacy, personalization, and reduced stigma.
6. **Technical detail is secondary.** Model provenance, sensor diagnostics, schema information, and research-export details should not compete with the primary participant action.
7. **Calm visual systems outperform casino cues for this use case.** RecoverySense intentionally avoids neon, jackpot-like, celebratory gambling graphics, and manipulative reward mechanics.

## RecoverySense decisions based on the benchmark

RecoverySense does **not** copy any product. The benchmark is used to establish interaction hierarchy:

```text
1. Craving Now
   latest participant 0–10 EMA self-report

2. Record / update craving rating
   single high-visibility CTA

3. Personalized Risk Estimate
   only when a complete, approved, non-demo model record exists

4. What may be contributing
   up to three positive local companion-tree contributions

5. Higher-Risk Times
   descriptive repeated-EMA pattern with minimum-data safeguards

6. Live Watch Data / Sleep
   supporting context rather than the dominant participant task

7. History / Settings / Research Export
   secondary navigation
```

The participant's 0–10 rating and the model probability are intentionally separated. The model UI uses association language, not causal language. Engineering status, raw upload counts, session identifiers, raw exception strings, and backend diagnostics are excluded from the main participant surface.

## Deliberate differences from commercial apps

RecoverySense is a research prototype, not a sobriety streak product. It therefore does not use streak-loss pressure, financial reward animations, coins, jackpots, or engagement mechanics that could confound study behavior. The dashboard prioritizes measurement validity and transparent model status over retention gamification.

The long one-time onboarding instrument is called a **Baseline Assessment**, while the repeated momentary 0–10 question remains the **EMA**. Baseline responses are candidate context variables and do not directly set feature weights.

## Release review questions

Before each participant-facing release, verify:

- Can the participant identify the craving rating and primary action within a few seconds?
- Is self-report visually distinct from model inference?
- Does every model explanation have provenance and a noncausal disclaimer?
- Are model/demo/legacy records prevented from masquerading as current predictions?
- Are no raw engineering errors or identifiers shown to participants?
- Can any default questionnaire value be stored without deliberate participant interaction?
- Are research details available when needed without overwhelming the main experience?
