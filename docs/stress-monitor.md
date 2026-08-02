# Stress Monitor

## Meaning and source

Stress Monitor displays a non-diagnostic physiological activation proxy. It does not measure emotional stress and must not be interpreted as anxiety, illness, or a medical diagnosis.

The interactive daily timeline consumes the existing `DaytimeStress` calculation. Raw heart-rate and R–R observations are grouped into local waking-hour buckets (06:00–22:00). An hour requires at least 300 heart-rate samples. Mean heart rate and, when available, RMSSD are compared with that day's quiet waking reference and mapped to the existing 0–3 logistic scale. This redesign does not change that calculation.

Today and Stress Monitor call the same canonical day loader and use its latest timestamped valid bucket. The Today cache never substitutes a maximum, threshold, chart bound, imported daily score, or missing-value fallback for that current observation.

The older daily score path remains distinct: a stored `my-whoop/stress` value is preferred, with a 30-day resting-heart-rate/HRV fallback. Imported wearable daily stress values are daily aggregates and are not presented as intraday observations.

## Scale and zones

- Low: `0.0..<1.0`
- Medium: `1.0..<2.0`
- High: `2.0...3.0`

The thresholds live in `StressPresentation.Zone` and are shared by integration, colors, labels, summaries, and comparisons. Exact values of 1.0 and 2.0 enter Medium and High respectively.

## Time in zone and coverage

Scored observations are sorted and duplicate timestamps are resolved deterministically. Each hourly bucket contributes no more than 60 minutes to its zone. Missing buckets and longer gaps are never bridged or classified as Low. Today's final bucket is clipped at the current time.

Observed coverage is scored duration divided by the 16-hour waking window. Zone percentages use observed time, not 24 hours. A day needs at least 60% coverage to participate in historical comparison.

Local day windows are created with `Calendar.current`, so midnight boundaries and 23/25-hour DST days are respected. The existing `DaytimeStress` API accepts one timezone offset for a read; the screen supplies the selected day's noon offset. A stress read spanning an intra-day DST transition therefore retains that existing hourly-bucketing limitation.

## Typical weekday comparison

For a selected weekday, the screen reads up to the eight immediately preceding matching weekdays. It never includes the selected day or future data. At least three days with 60% coverage are required. Each zone is compared using the median proportion of valid observed time, which prevents one extreme day from dominating the baseline.

If the minimum is not met, the UI says that it is building the weekday baseline and shows no fabricated zero comparison.

## Interaction, sleep, and freshness

The gauge defaults to the latest valid hourly observation for the selected day. Dragging the timeline selects the nearest real observation; no values are interpolated. Selection remains pinned until **Return to latest** is tapped, so repository refreshes do not unexpectedly replace the inspected value.

The chart draws thin straight segments between adjacent real hourly observations. It breaks the path when timestamps are more than 90 minutes apart; this is display-only and creates no selectable or analytical samples.

For today, an observation more than 90 minutes old is labeled stale. Past days are labeled as historical rather than live. Sleep shading is displayed only for real stored sleep sessions overlapping the selected local day.

## Limitations

- Intraday cadence is hourly, not minute-level or live beat-by-beat stress.
- A score describes physiological activation and cannot identify its cause.
- Exercise, posture, missing R–R coverage, and sensor quality can affect the proxy.
- The daily stored score and hourly timeline have historically used different baselines; this redesign preserves both calculations rather than presenting them as mathematically identical.
