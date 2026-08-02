# NOOP Sleep Planning model (version 3)

NOOP Sleep Planning is a transparent, local, WHOOP-inspired estimate. It is not WHOOP's proprietary
formula and does not change Charge, Effort, Rest, recovery, sleep staging, or canonical sleep totals.

## Recent sleep debt

Debt uses at most the latest 14 valid main sleeps. Each night is measured against the requirement known
before that night:

```text
base requirement = max(360, personalized baseline + strain adjustment - nap credit)
deficit = max(0, base requirement - main sleep)
surplus repayment = max(0, main sleep - base requirement) × 0.75
raw change = deficit - surplus repayment
recent debt = max(0, Σ(raw change × 0.90^age))
```

The latest sleep has full weight. Each older sleep has 90% of the weight of the sleep after it, and a
contribution disappears after 14 valid sleeps. Missing nights do not create debt or advance the window.
Debt is floored at zero; NOOP does not bank sleep credit. Because the model is bounded, repository history
older than the configured baseline and debt windows cannot change the current plan.

## Personalized baseline and confidence

The baseline is 450 minutes until seven prior valid main sleeps exist. It then uses the 70th percentile of
the latest 28 main sleeps, clamped to 450–540 minutes. Confidence is fallback below 7 prior sleeps, limited
from 7–20, and established at 21 or more. Each historical calculation uses only earlier sleeps.

## Tonight's Sleep Need

Effort is NOOP's native 0–100 scale. Its adjustment follows a smooth quadratic curve from 0 minutes at zero
Effort to 30 minutes at 100, capped there. This keeps low Effort negligible while progressively recognizing
moderate and high load.

Qualifying naps receive 80% credit based on estimated asleep time, capped at 120 minutes. Naps are selected
separately from the main sleep so they are never counted twice.

Recent debt contributes a gradual recovery target:

```text
debt recovery = min(recent debt × 0.25, 60 minutes)
Sleep Need = max(360, baseline + strain adjustment - nap credit + debt recovery)
```

The full recent debt and tonight's recovery target are deliberately separate concepts. A multi-hour debt
balance never means the user should add all of it to one night.

## Time in Bed and bedtime

Sleep Need is estimated asleep time. Time in Bed accounts for expected sleep efficiency:

```text
Time in Bed = Sleep Need / expected efficiency
recommended bedtime = planned wake time - Time in Bed
```

Expected efficiency is the median of up to 14 recent valid samples once seven exist, clamped to 75–98%.
Before then, the planner uses a 90% fallback. A bedtime is only shown when the user has explicitly enabled a
wake alarm or wind-down plan; NOOP does not silently invent a wake time.

Imported WHOOP Sleep Need and Sleep Debt remain untouched reference values. They never replace or alter the
local planner result.
