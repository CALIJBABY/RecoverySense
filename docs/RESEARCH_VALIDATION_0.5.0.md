# RecoverySense Research Validation Notes — Version 0.5.0

Date: 2026-08-10

## Scope

This document records the evidence used to justify the version 0.5.0 dashboard, onboarding, EMA-timing, explainability, and visual-design choices. It is an evidence-to-design review, **not** evidence that RecoverySense has already achieved clinically valid craving prediction.

RecoverySense remains a behavioral-addiction research prototype. The current craving model framework must still be trained and evaluated on real repeated EMA-labeled data with participant-separated and temporal validation before model-triggered intervention claims are appropriate.

## 1. One-time baseline assessment plus repeated EMA

Version 0.5.0 separates two different instruments:

1. **Baseline Assessment:** a one-time onboarding questionnaire for relatively stable/contextual variables.
2. **Repeated EMA:** the brief 0–10 momentary craving item delivered during daily life.

This distinction is consistent with behavioral-addiction EMA research. Hawker et al. used pre-EMA measures including gambling severity, harms, motives, high-risk situations, mental-health variables, and addiction-related variables, followed by repeated momentary craving, self-efficacy, and gambling-behavior observations. In that study, momentary gambling cravings predicted gambling episodes. DOI: 10.1016/j.addbeh.2020.106574.

A later 28-day gambling EMA study used a pre-EMA survey of stable variables and twice-daily momentary measures; momentary coping, enhancement, and social motives were associated with increased gambling expenditure. DOI: 10.1037/adb0001110.

### RecoverySense design implication

The baseline assessment therefore captures candidate context such as:

- behavior of concern and current goal;
- recent behavior frequency and typical craving;
- self-perceived high-risk time/day patterns;
- trigger/cue categories;
- motives including coping/escape, enhancement/excitement, social, financial, habit, and boredom relief;
- schedule regularity and typical sleep/wake timing;
- typical activity level;
- confidence to resist and typical stress.

These answers are **not converted directly into feature weights**. They are contextual/candidate variables. Predictive importance must come from repeated labeled observations and properly validated models.

## 2. Time-stratified repeated EMA

A 2026 longitudinal gambling/smartwatch protocol enrolled 109 at-risk gamblers for 28 days and requested brief EMA surveys three times daily—morning, afternoon, and evening—while passively collecting smartwatch physiology and activity. The surveys included craving intensity, sleep quality, physical activity, boredom, vitality, depression, and anxiety. The paper describes planned prediction modeling; it does not report final predictive performance. DOI: 10.2196/82782.

### RecoverySense design implication

The old high-frequency app-active 45–75 minute prompting schedule is replaced with one randomized prompt in each of three broad local-time strata:

- morning: 09:00–11:59;
- afternoon: 13:00–16:59;
- evening: 18:00–21:59.

These windows are an engineering sampling schedule, not clinically validated risk windows. The schedule is intended to improve temporal coverage while keeping the recurring item short.

The current implementation uses in-process timers. It does **not** yet guarantee delivery when the app process is killed or suspended; a production notification/work-scheduling implementation and physical-device burden study remain required.

## 3. Higher-risk time-of-day display

The dashboard estimates personal time-of-day patterns only from independently timed EMA sources (`random`, `scheduled`, `scheduled_stratified`, and `watch_scheduled`). Manual and model-triggered EMA are excluded from the primary descriptive time-of-day ranking because their sampling mechanism is related to user choice or predicted risk and can bias the estimate.

RecoverySense stores `local_minute_of_day` and `timezone_offset_minutes` with the EMA so time-of-day analysis does not incorrectly reinterpret UTC clock time as the participant's local routine.

The display currently requires:

- at least 30 eligible repeated EMA observations overall; and
- at least 5 eligible observations in a two-hour window.

These thresholds are conservative **engineering display safeguards**, not evidence-based clinical cutoffs. They must be revisited during study analysis using uncertainty intervals, coverage diagnostics, and sensitivity analyses. Self-reported baseline high-risk periods may be shown while empirical data are insufficient, but they are explicitly labeled as baseline estimates.

## 4. Craving gauge versus model risk

The phone dashboard separates:

- **Craving Now:** the participant's latest 0–10 EMA self-report;
- **Current Model Estimate:** a model-generated elevated-craving probability when a current validated/non-demo prediction is available;
- **Top decision-tree contributors:** the largest positive local contributions from the interpretable companion decision tree.

This prevents the participant-reported label from being visually conflated with an algorithmic estimate.

## 5. Decision-tree explanations

Version 0.5.0 does not use global impurity importance as if it explained a single prediction. Instead, the interpretability companion decision tree is decomposed along the actual decision path for the current feature vector. At each parent-to-child split, the change in positive-class node probability is assigned to the feature used at that split. Repeated uses of a feature are accumulated.

For the decision-tree companion:

```text
root probability + sum(local path contributions) = leaf probability
```

The three largest **positive** contributions are shown. This is an exact additive decomposition of the companion tree's leaf probability for that case, subject to floating-point error.

If the selected risk model is not the decision tree (for example, a random forest or gradient-boosted model), the dashboard explicitly identifies the decision tree as a **parallel explanation view trained on the same feature set**, rather than pretending that the tree contributions exactly decompose the selected model's probability.

All displayed factors are predictive associations. They must never be described as causal triggers without a separate causal design/analysis.

## 6. Color and visual design

There is no defensible universal claim that one green is “the best color for gambling recovery.” Color response varies by context, culture, display, and user. A 2026 UI/UX study reported that cool blue/green combinations were perceived as more professional, calming, comfortable, and trustworthy than warm red/orange combinations in serious-domain interfaces. This supports a restrained cool-green direction, but not a gambling-specific therapeutic effect. DOI: 10.1080/14606925.2026.2663037.

RecoverySense therefore uses a deliberately non-neon, non-casino-like palette:

```text
Primary green: #3D844B
Dark green:    #2F6D3C
Soft green:    #DDF0E2
Background:    #F4FAF5
Border:        #B8D5BF
Primary text:  #111111
```

Calculated contrast for white text on `#3D844B` is approximately 4.56:1. WCAG 2.2 Success Criterion 1.4.3 specifies at least 4.5:1 for normal text at Level AA, so this combination clears that threshold. Contrast must still be checked for every text/background pair and disabled state.

## 7. Groupon-style EMA call-to-action

The user requested EMA actions with the visual proportions of Groupon's Buy action. Official Groupon pages confirm Buy/purchase actions are a central mobile checkout interaction, but the official pages reviewed did not publish a universal device-independent width/height/radius specification.

RecoverySense therefore implements a **visual-reference match**, not a claim of an official Groupon design specification:

```text
height: 48 logical px / dp
width:  full available content width
corner radius: 2 logical px / dp
bold centered label
```

The 48 dp height also aligns with Android accessibility guidance recommending a minimum 48 dp × 48 dp touch target for interactive elements. The dimensions are centralized so they can be adjusted after device screenshots/usability testing. The app does not copy Groupon branding, logos, copy, or proprietary assets.

## 8. Evidence that does not yet exist

Version 0.5.0 must not be described as having established:

- a validated physiological signature of behavioral-addiction craving;
- causal effects of heart rate, sleep, time, boredom, stress, or movement on craving;
- validated individual risk thresholds;
- validated optimal prompt frequency;
- validated sleep staging;
- validated raw-PPG/PRV features;
- clinical efficacy or diagnostic performance.

Required next evidence includes real EMA-labeled participant data, participant-held-out evaluation, chronological deployment-style testing, calibration, false-prompt burden, response-rate analysis, subgroup/failure analysis, and physical-device collection validation.

## Primary references

1. Hawker CO, Merkouris SS, Youssef GJ, Dowling NA. *Exploring the associations between gambling cravings, self-efficacy, and gambling episodes: An Ecological Momentary Assessment study.* Addictive Behaviors. 2021;112:106574. DOI: 10.1016/j.addbeh.2020.106574.
2. Hawker CO, Dias SE, Merkouris SS, Rodda SN, Dowling NA. *Exploring the associations between momentary gambling motives and gambling behavior: An ecological momentary assessment study.* Psychology of Addictive Behaviors. 2026;40(1):113-125. DOI: 10.1037/adb0001110.
3. *Identifying Predictors of Gambling Episodes and Craving Using Ecological Momentary Assessment and Smartwatch-Based Physiological Measures: Protocol for a Longitudinal Observational Study.* JMIR Research Protocols. 2026. DOI: 10.2196/82782.
4. Singh PK. *Colour psychology in UI and UX design: Eliciting emotional responses through colour combination choices.* The Design Journal. 2026. DOI: 10.1080/14606925.2026.2663037.
5. W3C. *Web Content Accessibility Guidelines (WCAG) 2.2*, Success Criterion 1.4.3 Contrast (Minimum).
