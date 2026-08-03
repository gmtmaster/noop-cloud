# Stress Monitor

## Meaning and source

Stress Monitor displays a non-diagnostic physiological activation proxy. It does not measure emotional stress and must not be interpreted as anxiety, illness, or a medical diagnosis.

The interactive daily timeline consumes `DaytimeStress` V2. Raw heart-rate, R–R and gravity observations are analyzed in trailing five-minute windows every minute during local waking hours (06:00–22:00). A window must meet both sample-count and temporal-coverage gates. Trimmed HR and, when available, cleaned RMSSD are compared with a robust personal reference and mapped to the 0–3 scale. Motion and recorded workout overlap attenuate the non-specific HR contribution; confidence and asymmetric smoothing limit noisy jumps.

Today and Stress Monitor call the same canonical day loader and use its latest timestamped valid bucket. The Today cache never substitutes a maximum, threshold, chart bound, imported daily score, or missing-value fallback for that current observation.

The older daily score path remains distinct: a stored `my-whoop/stress` value is preferred, with a 30-day resting-heart-rate/HRV fallback. Imported wearable daily stress values are daily aggregates and are not presented as intraday observations.

## Scale and zones

- Low: `0.0..<1.0`
- Medium: `1.0..<2.0`
- High: `2.0...3.0`

The thresholds live in `StressPresentation.Zone` and are shared by integration, colors, labels, summaries, and comparisons. Exact values of 1.0 and 2.0 enter Medium and High respectively.

## Time in zone and coverage

Scored observations are sorted and duplicate timestamps are resolved deterministically. Each rolling observation contributes no more than one minute to its zone. Missing observations and longer gaps are never bridged or classified as Low. Today's final observation is clipped at the current time.

Observed coverage is scored duration divided by the 16-hour waking window. Zone percentages use observed time, not 24 hours. A day needs at least 60% coverage to participate in historical comparison.

Local day windows are created with `Calendar.current`, so midnight boundaries and 23/25-hour DST days are respected. `DaytimeStress` accepts one timezone offset for a read; the screen supplies the selected day's noon offset. A stress read spanning an intra-day DST transition therefore retains that limitation.

## Typical weekday comparison

For a selected weekday, the screen reads up to the eight immediately preceding matching weekdays. It never includes the selected day or future data. At least three days with 60% coverage are required. Each zone is compared using the median proportion of valid observed time, which prevents one extreme day from dominating the baseline.

If the minimum is not met, the UI says that it is building the weekday baseline and shows no fabricated zero comparison.

## Interaction, sleep, and freshness

The gauge defaults to the latest valid rolling observation for the selected day. Dragging the timeline selects the nearest real observation; no values are interpolated. Selection remains pinned until **Return to latest** is tapped, so repository refreshes do not unexpectedly replace the inspected value.

The chart draws thin straight segments between adjacent real observations. It breaks the path after two missed updates; this is display-only and creates no selectable or analytical samples.

For today, an observation more than three minutes old is labeled stale. Past days are labeled as historical rather than live. Sleep shading is displayed only for real stored sleep sessions overlapping the selected local day.

## Limitations

- Intraday output cadence is one minute from overlapping five-minute evidence; it is not beat-by-beat stress.
- A score describes physiological activation and cannot identify its cause.
- Exercise, posture, missing R–R or gravity coverage, and sensor quality can affect the proxy.
- The daily stored score and rolling timeline use different baselines and must not be presented as mathematically identical.
