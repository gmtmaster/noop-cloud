# Health Monitor and Healthspan

NOOP separates live Health Monitor vitals from the long-term Healthspan model. Healthspan is a deterministic
wellness comparison, not a biological age, diagnosis, lifespan prediction, or disease-risk assessment.

## Canonical Healthspan v2

`NoopAgeEngine` is the only source of Noop Age and Pace of Aging. It produces completed Saturday-ending
weekly snapshots with strict cutoff filtering. Today and Healthspan consume those same results; the identical
values are projected to `noop_age` and `noop_pace` for Trends. The older `fitness_age`, `body_age`, `vitality`,
`FitnessAgeEngine`, and `VitalityEngine` remain available under their legacy names but do not feed Healthspan.

### Windows and aggregation

- Noop Age uses a hard trailing 180-day window ending at each weekly cutoff, or all available history when
  less than 180 days exists.
- Pace uses the most recent 30 days ending at the same cutoff.
- Daily observations are winsorized at the window's 5th/95th percentiles and exponentially weighted with a
  75-day half-life. Activity minutes are converted to weekly equivalents after aggregation.
- Missing metrics remain absent. Available metrics are averaged within their domain, then available domains
  are averaged, so extra sensors in one domain cannot dominate merely by count.
- Every historical result sees only data on or before its cutoff. Future imports cannot change it.

### Contributors and coefficient set

WHOOP's production curves and structural-equation overlap factors are proprietary. `noop-healthspan-v2` is a
transparent approximation of WHOOP's published contributor families. Each metric produces a log-hazard
relative to a health-oriented reference. Available metrics inside a domain receive equal weight; every domain
receives an overlap shrink of `0.82`. Effective years are:

`age impact = ln(combined hazard ratio) / ln(1.10)`

| Contributor | Noop v2 curve |
| --- | --- |
| Sleep duration | 7–8 h neutral; log-hazard `0.11` per hour outside that band |
| Sleep timing consistency | Circular SD of actual sleep/wake clock times; score 70% neutral; coefficient `0.45` |
| Steps | 8,000/day target below age 60, 7,000 at 60+; `0.064` per 1,000-step difference, bounded |
| Zones 1–3 | 100 min/week target; coefficient `0.18` across a bounded target deficit/surplus |
| Zones 4–5 | 10 min/week target; coefficient `0.08` |
| Strength | 40 min/week target, benefit capped at 120 min; coefficient `0.12` |
| Resting HR | 60 bpm reference; log-hazard `0.10` per 10 bpm, bounded |
| VO₂ max | age-reference `clamp(52 − 0.30 × (age − 20), 24, 52)`; `0.13` per 3.5 ml/kg/min, bounded |
| Lean mass | optional real lean-mass percentage only; age-neutral target 70%, 65% at 65+; downside-only `0.08` |

HRV, Recovery, Sleep Debt, workout count, generic strain, and Lab Book data are intentionally excluded.
Lean mass is used only when compatible lean-mass and weight readings exist for the same day. VO₂ max can be
an imported reading or the separately labeled Noop estimate. No missing value is converted to zero.

### Confidence and stability

Wear days require at least two of sleep, RHR, and activity evidence. Missing proportion is calculated across
the required sleep/RHR/activity observations.

| State | Coverage gate | Adjustment cap | New weekly estimate weight |
| --- | --- | ---: | ---: |
| Calibrating | ≥7 calendar/wear/sleep/RHR/activity days, ≥2 domains, ≤40% missing | ±3 y | 20% |
| Developing | ≥30 calendar days, 21 wear, 18 sleep/RHR/activity, 4 weeks, 3 domains, ≤30% missing | ±5 y under 60 days; ±7.5 y at 60–179 | 30%; then 40% |
| Established | ≥180 days, 126 wear, 108 sleep/RHR/activity, 22 weeks, 3 domains, ≤30% missing | ±10 y | 50% |

The first provisional estimate is blended from chronological age using the same maturity weight. Subsequent
weekly snapshots blend from the prior displayed snapshot. Calibrating UI rounds the displayed Age to a whole
year; the result model retains full precision.

### Pace of Aging

The recent 30-day contributor state is used to project Age after six months. The projection includes 0.5 years
of chronological aging:

`projectedSixMonthAge = chronologicalAge + 0.5 + recentContributorAdjustment`

`pace = (projectedSixMonthAge − currentNoopAge) / 0.5`

Pace is clamped to `-1.0x...3.0x`; 1.0x means normal chronological aging. It requires 21 valid recent wear
days, 28 older valid comparison days outside the recent window, eight valid weeks overall, and at least two
domains in both periods. Otherwise it remains unavailable while the older baseline builds.

## Data sources and limitations

Daily metrics supply sleep duration, steps, and RHR. Main sleep-session timestamps supply real sleep and wake
timing. Generic metric series supply imported zone minutes, strength time, VO₂ max, estimated VO₂ max, lean
mass, and weight. Device and import routes differ, so coverage and unavailable contributor keys are included
in every result.

NOOP follows the public WHOOP window, contributor-family, effective-age, and projected-Pace architecture, but
does not claim coefficient parity. WHOOP's exact curves, covariance matrix, missing-data rules, and smoothing
are not public.
