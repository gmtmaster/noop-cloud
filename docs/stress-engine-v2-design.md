# Stress Engine V2: rolling physiological activation

Status: implementation design, 3 August 2026

## Current algorithm

`DaytimeStress` currently groups stored HR and R–R observations into fixed clock hours between 06:00 and 22:00. An hour requires 300 HR readings. It calculates mean HR and optional hourly RMSSD, compares both with a calm-end reference derived from the same day's waking hours, sums z-scores, and maps the result to 0–3 with a logistic curve. The Stress screen rebuilds the day once per minute, but a new value is effectively available only when an hourly bucket changes. Gravity and workout context are not inputs.

Strengths are honest missing-data gaps, a personalized scale, robust HRV cleaning and bounded output. Weaknesses are up to an hour of latency, dilution of short events, clock-boundary artifacts, self-normalization that changes as the day grows, and false elevation from movement.

## Public evidence used

WHOOP says Stress Monitor uses HR and HRV “in the moment,” compares them with a dynamically updated personal baseline (launch material specifies 14 days), accounts for motion, and updates continuously. WHOOP does not publish its production formula or publication cadence.

A 2023 WHOOP-affiliated PLOS ONE study—not proof of the production Stress Monitor—calculated motionless HR and RMSSD from five-minute moving blocks stepped every 30 seconds. It is credible public evidence for the signal-processing shape: overlapping short windows, frequent updates, motion artifact handling and personal/time-aware normalization.

Sources:

- https://www.whoop.com/thelocker/introducing-stress-monitor-a-new-way-to-monitor-manage-stress/
- https://support.whoop.com/s/article/Get-to-Know-the-Stress-Monitor?language=en_US
- https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0285332

## Proposed algorithm

All tuning lives in `DaytimeStress.Configuration`.

1. Build observations every 60 seconds from a trailing five-minute window. This matches the public research window while avoiding needless recomputation faster than NOOP normally persists standard HR/R–R batches (~30 readings).
2. Reject implausible HR, require minimum sample count and temporal coverage, and use a trimmed mean so one optical spike cannot dominate a window.
3. Calculate RMSSD with NOOP's existing beat cleaner. HRV enriches a score only when enough clean R–R evidence exists.
4. Estimate motion from changes in the stored gravity vector. Motion attenuates the HR contribution because an elevated HR while moving is less specific to non-metabolic activation. It does not force stress to zero: workouts are still physiological load and low HRV may remain informative.
5. Use robust calm-end references from the day's valid rolling windows, with spread floors to prevent tiny natural variance from creating huge z-scores. This preserves current-data compatibility. A persisted, time-of-day 14-day baseline remains a future improvement; pretending overnight HRV is directly interchangeable with daytime five-minute RMSSD would be less credible.
6. Combine weighted HR-up and RMSSD-down evidence and map it to 0–3. Reduce confidence when coverage is weak, HRV is missing, or movement is high; pull low-confidence estimates toward neutral instead of inventing certainty.
7. Apply an asymmetric EMA (faster attack, slower release) and a per-step slew limit. Overlapping windows already smooth the signal; this final stage removes isolated jumps while allowing a sustained event or breathing response to become visible within minutes.
8. Keep the high-resolution series derived from durable raw streams rather than duplicating it in a new database table. A 16-hour day at one-minute cadence is at most 960 small observations in memory. Raw HR/R–R/gravity remain the source of truth, so tuning can replay history without a migration or stale cached scores.

## Expected behavior

- A sustained HR rise or HRV suppression should appear after one qualified five-minute window instead of at the end of an hour.
- Meetings, driving or public speaking can produce visible multi-minute rises when cardiovascular evidence persists.
- Breathing or quiet recovery can lower the curve over several minutes; release smoothing intentionally prevents an implausible instantaneous collapse.
- Optical spikes and brief missing patches should have limited impact.
- Movement/workouts should rely less on HR alone and should no longer be automatically interpreted like still-state activation.
- The chart becomes a dense one-minute trace with honest gaps.

## Tradeoffs and cost

- Five minutes is responsive but cannot attribute cause or separate every emotional and metabolic stressor.
- Same-day calm references are available offline and replayable but are not equivalent to WHOOP's reported 14-day baseline. Early-day confidence is lower and history may shift slightly as more of the day arrives.
- Gravity is an orientation/movement proxy, not a validated activity classifier. Missing gravity leaves the score cardiovascular-only.
- A straightforward rolling implementation is linear after sorting and uses moving indices; at 1 Hz HR, one day is ~86,400 samples and ~960 windows. R–R and gravity are similarly streamed through moving bounds. Memory is bounded to the raw day already loaded plus the observation array.

## Compatibility

- The public `DaytimeStress.analyze` entry point and `HourPoint` shape remain source compatible; points simply occur every minute rather than every hour and gain optional quality/context fields.
- Existing imported daily `stress` metric-series values are untouched.
- Historical charts are recomputed from existing raw streams. Days without adequate raw data retain honest gaps.
- Presentation duration, freshness and line-gap constants must follow the configured one-minute cadence rather than the former one-hour cadence.

