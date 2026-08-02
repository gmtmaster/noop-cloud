# Health Monitor and Healthspan

NOOP deliberately separates two products:

- **Health Monitor** shows a genuinely live heart-rate stream when one exists and the freshest real nightly or daily respiratory rate, SpO₂, resting heart rate, HRV, and skin-temperature reading. Every stored vital names its day/source and whether it uses a trusted personal range, a labeled reference range while personal history develops, or has insufficient data.
- **Healthspan** shows a weekly **Noop Age** and a bounded recent trajectory. It is not a live-vitals page.

No blood-pressure tile is shown in Health Monitor. NOOP supports user-entered/imported blood pressure in the separate Lab Book, but it is not a wearable vital or live feed.

## Noop Age

Noop Age is a deterministic functional fitness and health comparison. It starts with chronological age and the existing published Nes/HUNT Fitness Age signal (weekly resting heart rate plus measured activity). It then applies bounded weekly adjustments:

| Input | Maximum age impact |
| --- | ---: |
| Nes/HUNT fitness comparison | ±8.0 years |
| HRV trend | ±1.0 year |
| Sleep consistency | ±1.0 year |
| Sleep duration | ±0.75 year |
| Weighted recent Sleep Debt | 0 to +1.25 years |
| Recovery consistency | ±0.75 year |
| Workout regularity | ±1.0 year |

The combined adjustment is capped at ±10 years and the displayed age is constrained to 20–80. Missing optional inputs are omitted. At least four resting-HR nights and an explicitly supplied chronological age are required.

Each raw weekly value is smoothed with a trailing three-week weighted mean (weights 1, 2, 3). A historical week uses only that week and earlier weeks; adding future data cannot alter an earlier projection.

Confidence is **insufficient** without minimum inputs, **developing** while coverage/history builds, and **established** after at least four valid weekly results with broad factor coverage.

## Pace of Aging

Pace uses the least-squares slope of four to eight smoothed weekly Noop Age points. `1.0 + slope / 0.25` is clamped to `0.7x...1.3x`. Below 1.0x means the recent modeled estimate is improving; above 1.0x means it is worsening. It is not literal biological aging speed.

## Limitations

This is a transparent WHOOP-inspired approximation, not WHOOP’s proprietary model. It is not biological age, diagnosis, lifespan prediction, or disease-risk assessment. Sensor gaps, imports, device capabilities, and the uncertainty of non-exercise fitness estimation limit the result.
