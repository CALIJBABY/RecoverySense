# RecoverySense EMA and Baseline Instruments — Version 0.5.1

## Required repeated EMA

RecoverySense uses one required repeated momentary item on both the Galaxy Watch and phone fallback screen:

> How strong is your urge or craving right now?
>
> 0 = none, 10 = extreme

This single 0–10 value is the primary supervised-learning label stored as `craving_score`. The phone and watch both require deliberate participant interaction before the visually neutral slider position can be saved; an untouched control is treated as no response, not as a midpoint rating.

## Why the repeated EMA is intentionally short

A consistent rapid label is more useful for time-aligning the answer with the preceding sensor window than a long form that participants delay or skip. The watch queues the answer through the Wear Data Layer, so the phone does not need to be open at the exact moment of entry.

The event record also preserves:

- prompt/open/submit timestamps when available;
- response delay;
- prompt source (manual, scheduled, model, etc.);
- response device (`watch` or `phone`);
- associated watch session ID when available;
- local minute-of-day and timezone offset in v0.5+ (captured for participant-local routine analysis);
- model probability/version metadata for future model-triggered prompts.

## One-time Baseline Assessment v1

The longer onboarding form is a **baseline assessment**, not an EMA. It is completed once for an authenticated participant when `baseline_v1` is absent/incomplete. It provides contextual/candidate variables and does not directly set model weights.

Current domains:

- behavior of concern;
- current goal;
- days engaged in the behavior during the past 30 days;
- typical craving intensity;
- typical episode duration;
- self-reported high-risk time blocks and days;
- common cue/trigger categories;
- motive categories;
- schedule regularity;
- typical bedtime/wake time;
- activity level;
- confidence to resist;
- typical stress.

Visible default-looking numeric/time controls in Baseline Assessment v1 also require explicit confirmation before completion, so a displayed default cannot silently become research data.

The baseline intentionally avoids free-text personal identifiers. If a future protocol requires a validated disorder-specific severity scale or demographics, those should be added as a separately versioned, IRB/protocol-approved instrument rather than silently changing baseline v1.

## Other occasional research forms

Detailed mood, coping, behavioral-outcome, end-of-day, or disorder-specific questionnaires should remain separate versioned instruments if the approved protocol needs them. They are not part of the required repeated micro-EMA.
