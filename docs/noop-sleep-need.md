# NOOP Sleep Need model (version 2)

NOOP Sleep Need is a transparent planning estimate. It does not reproduce WHOOP's proprietary algorithm
and does not change NOOP's Charge, Effort, Rest, Recovery, sleep staging, or canonical sleep totals.

For each cycle, the engine uses only earlier main sleeps plus strain and true naps available for that cycle.
The baseline is 450 minutes until seven valid main sleeps exist. It then uses the 70th percentile of the
latest 28 main sleeps, clamped to 450–540 minutes. Confidence is fallback below 7 nights, limited from 7–20,
and established at 21 or more.

Carried debt is updated chronologically against the requirement before prior debt is added:

```
base requirement = max(360, baseline + strain adjustment - nap credit)
deficit = max(0, base requirement - main sleep)
repayment = max(0, main sleep - base requirement) * 0.75
carried = max(0, previous carried + deficit - repayment)
tonight debt adjustment = min(carried * 0.50, 120 minutes)
```

The carried balance is deliberately not capped at 240 minutes. Only the amount added to one night's
recommendation is capped, at 120 minutes. Keeping those concepts separate lets the balance continue to
reflect short nights while allowing adequate and surplus sleep to reduce it predictably.

Strain adds zero minutes through 50 on NOOP's 0–100 scale, rises linearly to 30 minutes at 100, and is
capped. True nap sleep credits 80%, capped at 120 minutes. Total need cannot fall below 360 minutes.

When at least seven prior efficiency samples exist, their median is clamped to 0.75–0.98 and recommended
time in bed is `Sleep Need / expected efficiency`. Otherwise time in bed is omitted.

Imported WHOOP Sleep Need and debt remain untouched reference values. They are carried alongside, but never
mixed into, the locally-derived NOOP history. The local series is derived on demand from canonical records;
there is no migration, cache, or Cloud Sync contract change.
