import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

/// Focused stress presentation. The physiological score itself remains owned by
/// `DaytimeStress`; this view only selects, integrates and compares its real buckets.
struct StressView: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var summary: StressPresentation.Day?
    @State private var baseline: StressPresentation.Baseline?
    @State private var sleepIntervals: [DateInterval] = []
    @State private var scrubbed: StressPresentation.Sample?
    @State private var loading = true
    @State private var showBreathe = false

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var isToday: Bool { calendar.isDate(selectedDay, inSameDayAs: today) }
    private var displayed: StressPresentation.Sample? { scrubbed ?? summary?.latest }

    var body: some View {
        ScreenScaffold(title: "Stress Monitor", subtitle: "Physiological activation through your day",
                       lazy: true) {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                daySelector
                if loading && summary == nil {
                    ComingSoon(what: "Reading stress observations…")
                } else if let summary, !summary.samples.isEmpty {
                    gaugeCard(summary)
                    timelineCard(summary)
                    interpretationCard(summary)
                    if let point = displayed, StressPresentation.Zone(score: point.value) == .high {
                        downshiftCard
                    }
                    comparisonCard(summary)
                    methodologyCard
                } else {
                    emptyState
                }
            }
        }
        .task(id: LoadKey(day: selectedDay, refresh: repo.refreshSeq)) { await loadDay() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if !Task.isCancelled, isToday,
                   let refreshed = await repo.canonicalStressSummary(for: selectedDay, now: Date(), calendar: calendar) {
                    // A pinned scrub remains the displayed point; Latest mode advances naturally.
                    summary = refreshed
                }
            }
        }
        .sheet(isPresented: $showBreathe) {
            NavigationStack {
                BreathingView()
                    .toolbar { ToolbarItem { Button("Done") { showBreathe = false } } }
            }
        }
    }

    private var daySelector: some View {
        HStack(spacing: 12) {
            Button { moveDay(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            Spacer()
            Text(isToday ? String(localized: "TODAY") : selectedDay.formatted(.dateTime.month(.abbreviated).day()))
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            Button { moveDay(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(isToday).opacity(isToday ? 0.3 : 1)
        }
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityElement(children: .contain)
    }

    private func gaugeCard(_ day: StressPresentation.Day) -> some View {
        let zone = displayed.map { StressPresentation.Zone(score: $0.value) } ?? .low
        return NoopCard(tint: zoneColor(zone)) {
            VStack(spacing: 14) {
                HStack {
                    Text(isToday ? "CURRENT STATE" : "DAY SNAPSHOT").strandOverline()
                    Spacer()
                    Label(isToday ? "Updates every minute" : "Recorded observation", systemImage: "clock")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                StressArcGauge(value: displayed?.value, zone: displayed.map { StressPresentation.Zone(score: $0.value) })
                    .frame(height: 210)
                if let point = displayed {
                    Text(scrubbed == nil ? latestLabel(point) : "SELECTED · \(time(point.timestamp))")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    if scrubbed != nil {
                        Button("Return to latest") { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scrubbed = nil } }
                            .font(StrandFont.caption)
                    }
                }
                HStack(spacing: 4) {
                    stressBandKey("LOW", range: "0–1", zone: .low, active: zone == .low)
                    stressBandKey("MEDIUM", range: "1–2", zone: .medium, active: zone == .medium)
                    stressBandKey("HIGH", range: "2–3", zone: .high, active: zone == .high)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(gaugeAccessibility)
        }
    }

    private func stressBandKey(_ title: String, range: String, zone: StressPresentation.Zone,
                               active: Bool) -> some View {
        VStack(spacing: 3) {
            Text(title).font(StrandFont.overline).foregroundStyle(active ? zoneColor(zone) : StrandPalette.textTertiary)
            Text(range).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 9)
        .background(active ? zoneColor(zone).opacity(0.13) : StrandPalette.surfaceInset,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(active ? zoneColor(zone).opacity(0.4) : Color.clear, lineWidth: 1))
    }

    private func timelineCard(_ day: StressPresentation.Day) -> some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("DAILY STRESS").strandOverline()
                    Spacer()
                    Text("\(Int((day.distribution.coverage * 100).rounded()))% observed")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                StressTimeline(samples: day.samples, selected: scrubbed, sleep: sleepIntervals) { scrubbed = $0 }
                    .frame(height: 190)
                    .accessibilityLabel("Daily stress timeline. Drag to select the nearest recorded observation.")
                HStack {
                    Text("6 AM"); Spacer(); Text("2 PM"); Spacer(); Text("10 PM")
                }
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                if day.distribution.coverage < StressPresentation.qualifiedCoverage {
                    Label("Limited coverage—comparisons are withheld for sparse days.", systemImage: "exclamationmark.circle")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
                }
            }
        }
    }

    private func interpretationCard(_ day: StressPresentation.Day) -> some View {
        let dominant = StressPresentation.Zone.allCases.max {
            day.distribution.duration(for: $0) < day.distribution.duration(for: $1)
        } ?? .low
        let title: String = switch dominant {
        case .low: "Mostly Low Stress"
        case .medium: "Moderate Stress"
        case .high: "High Stress Load"
        }
        return NoopCard(tint: zoneColor(dominant)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(interpretation(day, dominant: dominant))
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var downshiftCard: some View {
        NoopCard(tint: StrandPalette.statusWarning) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "wind").font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(StrandPalette.statusWarning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A moment to downshift").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text("High physiological activation is present in the latest scored hour.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                NoopButton("Start a breathing session", systemImage: "lungs.fill", kind: .primary, fullWidth: true) {
                    showBreathe = true
                }
            }
        }
    }

    private func comparisonCard(_ day: StressPresentation.Day) -> some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()) STRESS VS. TYPICAL \(selectedDay.formatted(.dateTime.weekday(.wide)).uppercased())")
                    .strandOverline()
                ZoneStackedBar(distribution: day.distribution)
                if let baseline {
                    TypicalStackedBar(baseline: baseline)
                    ForEach(StressPresentation.Zone.allCases, id: \.self) { zone in
                        zoneRow(zone, day: day, baseline: baseline)
                    }
                } else {
                    Text("Building your typical \(selectedDay.formatted(.dateTime.weekday(.wide))) baseline.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private var methodologyCard: some View {
        Text("Stress is a non-diagnostic physiological activation proxy on a 0–3 scale. Durations include only scored hourly buckets; missing periods are never assigned to low stress. Typical-day comparisons use the median of up to eight qualified prior matching weekdays.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        NoopCard(tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text("No stress observations").font(StrandFont.headline)
                Text("This day does not contain enough heart-rate data to calculate an hourly physiological stress timeline.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func moveDay(_ amount: Int) {
        guard let date = calendar.date(byAdding: .day, value: amount, to: selectedDay) else { return }
        selectedDay = min(calendar.startOfDay(for: date), today)
        scrubbed = nil
    }

    @MainActor private func loadDay() async {
        loading = true; scrubbed = nil; baseline = nil
        let selected = await readSummary(for: selectedDay)
        guard !Task.isCancelled else { return }
        summary = selected
        let bounds = dayBounds(selectedDay)
        let sessions = await repo.sleepSessions(from: Int(bounds.start.timeIntervalSince1970),
                                                to: Int(bounds.end.timeIntervalSince1970), limit: 100)
        sleepIntervals = sessions.compactMap {
            let start = max(Date(timeIntervalSince1970: TimeInterval($0.effectiveStartTs)), bounds.start)
            let end = min(Date(timeIntervalSince1970: TimeInterval($0.endTs)), bounds.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        var prior: [StressPresentation.Day] = []
        for week in 1...StressPresentation.maximumBaselineDays {
            guard !Task.isCancelled, let date = calendar.date(byAdding: .day, value: -7 * week, to: selectedDay) else { break }
            if let value = await readSummary(for: date) { prior.append(value) }
        }
        baseline = StressPresentation.baseline(selectedDate: selectedDay, candidates: prior)
        loading = false
    }

    @MainActor private func readSummary(for date: Date) async -> StressPresentation.Day? {
        await repo.canonicalStressSummary(for: date, now: Date(), calendar: calendar)
    }

    private func dayBounds(_ date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    private func latestLabel(_ point: StressPresentation.Sample) -> String {
        if isToday && StressPresentation.isStale(point, now: Date()) { return "STALE · UPDATED \(time(point.timestamp))" }
        return isToday ? "LATEST · \(time(point.timestamp))" : "LAST RECORDED · \(time(point.timestamp))"
    }

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    private var gaugeAccessibility: String {
        guard let point = displayed else { return "Stress unavailable" }
        let zone = StressPresentation.Zone(score: point.value).rawValue
        return "Stress \(String(format: "%.1f", point.value)), \(zone), \(scrubbed == nil ? "latest" : "selected") at \(time(point.timestamp))."
    }

    private func interpretation(_ day: StressPresentation.Day, dominant: StressPresentation.Zone) -> String {
        let pct = Int((day.distribution.proportion(for: dominant) * 100).rounded())
        if let baseline, day.distribution.coverage >= StressPresentation.qualifiedCoverage {
            let delta = day.distribution.proportion(for: .high) - baseline.proportion(for: .high)
            if abs(delta) >= 0.05 {
                return "\(pct)% of observed time was \(dominant.rawValue) stress. High-stress periods were \(delta > 0 ? "more" : "less") frequent than on your typical \(selectedDay.formatted(.dateTime.weekday(.wide)))."
            }
        }
        return "\(pct)% of valid observed time was recorded in the \(dominant.rawValue)-stress zone."
    }

    private func zoneRow(_ zone: StressPresentation.Zone, day: StressPresentation.Day,
                         baseline: StressPresentation.Baseline) -> some View {
        let typical = baseline.proportion(for: zone)
        let typicalDuration = baseline.coverage * StressPresentation.expectedDayDuration * typical
        let deltaDuration = day.distribution.duration(for: zone) - typicalDuration
        return HStack {
            Circle().fill(zoneColor(zone)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.rawValue.uppercased()).font(StrandFont.overline)
                Text(duration(day.distribution.duration(for: zone))).font(StrandFont.headline)
            }
            Spacer()
            Text("\(duration(abs(deltaDuration))) \(deltaDuration >= 0 ? "more" : "less") than typical")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                .accessibilityLabel("\(duration(abs(deltaDuration))) \(deltaDuration >= 0 ? "more" : "less") than typical")
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded()), hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }

    private struct LoadKey: Equatable { let day: Date; let refresh: Int }
}

@MainActor
extension Repository {
    /// One canonical intraday read shared by Today and Stress Monitor.
    func canonicalStressSummary(for date: Date, now: Date, calendar input: Calendar) async -> StressPresentation.Day? {
        let calendar = input
        let start = calendar.startOfDay(for: date)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let end = min(nextDay, now)
        guard end > start else { return nil }
        let from = Int(start.timeIntervalSince1970), to = Int(end.timeIntervalSince1970)
        let hr = await hrSamples(from: from, to: to, limit: 200_000)
        guard hr.count >= DaytimeStress.minHourHRSamples else { return nil }
        let store = await storeHandle()
        let rr = (try? await store?.rrIntervals(deviceId: deviceId, from: from, to: to, limit: 200_000)) ?? []
        let gravity = (try? await store?.gravitySamples(deviceId: deviceId, from: from, to: to, limit: 200_000)) ?? []
        // Query the selected day directly rather than a "recent N days" helper, so historical Stress
        // views retain activity context too. Gravity remains the primary movement signal.
        var activityRows: [WorkoutRow] = []
        for id in Set([deviceId, "my-whoop", "apple-health", "lifting", "activity-file"]) {
            activityRows += (try? await store?.workouts(deviceId: id, from: from, to: to, limit: 1_000)) ?? []
        }
        let activities = activityRows.map { DaytimeStress.ActivityInterval(startTs: $0.startTs, endTs: $0.endTs) }
        let noon = calendar.date(byAdding: .hour, value: 12, to: start) ?? start
        let offset = calendar.timeZone.secondsFromGMT(for: noon)
        // `Repository` is MainActor-isolated for its published caches, but this analysis is a pure
        // full-day transform over captured value arrays. Sorting up to 200k HR/RR/gravity rows and
        // building the rolling five-minute windows on the main actor caused a visible once-per-minute
        // hitch on Today (and a second copy while Stress Monitor was open). Keep all reads and score
        // semantics identical; only move the CPU work to utility priority.
        let result = await Task.detached(priority: .utility) {
            DaytimeStress.analyze(hr: hr, rr: rr, gravity: gravity,
                                  activities: activities, tzOffsetSeconds: offset)
        }.value
        return StressPresentation.summarize(date: start, points: result.hours,
                                            end: calendar.isDate(date, inSameDayAs: now) ? now : nil)
    }
}

private func zoneColor(_ zone: StressPresentation.Zone) -> Color {
    switch zone {
    case .low: StrandPalette.accent
    case .medium: StrandPalette.statusPositive
    case .high: StrandPalette.statusWarning
    }
}

private struct StressArcGauge: View {
    let value: Double?
    let zone: StressPresentation.Zone?
    var body: some View {
        ZStack {
            Canvas { context, size in
                let rect = CGRect(x: 18, y: 18, width: size.width - 36, height: (size.width - 36))
                var track = Path(); track.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                                                startAngle: .degrees(155), endAngle: .degrees(385), clockwise: false)
                context.stroke(track, with: .color(StrandPalette.surfaceRaised), style: .init(lineWidth: 20, lineCap: .round))
                context.stroke(track, with: .linearGradient(Gradient(colors: [zoneColor(.low), zoneColor(.medium), zoneColor(.high)]),
                                                            startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)),
                               style: .init(lineWidth: 13, lineCap: .round))
                if let value {
                    let angle = (155 + min(max(value / 3, 0), 1) * 230) * Double.pi / 180
                    let point = CGPoint(x: rect.midX + cos(angle) * rect.width / 2,
                                        y: rect.midY + sin(angle) * rect.width / 2)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)),
                                 with: .color(.white))
                }
            }
            VStack(spacing: 4) {
                Text(value.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 58, weight: .bold, design: .rounded)).foregroundStyle(StrandPalette.textPrimary)
                Text(zone?.rawValue.uppercased() ?? "NO DATA")
                    .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(zone.map(zoneColor) ?? StrandPalette.textTertiary)
            }.offset(y: 18)
        }
    }
}

private struct StressTimeline: View {
    let samples: [StressPresentation.Sample]
    let selected: StressPresentation.Sample?
    let sleep: [DateInterval]
    let onSelect: (StressPresentation.Sample) -> Void

    var body: some View {
        GeometryReader { geo in
            let start = Calendar.current.startOfDay(for: samples.first?.timestamp ?? Date()).addingTimeInterval(6 * 3600)
            let span = StressPresentation.expectedDayDuration
            let axisWidth: CGFloat = 30
            let plotWidth = max(1, geo.size.width - axisWidth)
            ZStack(alignment: .topLeading) {
                ForEach(0...3, id: \.self) { value in
                    let y = geo.size.height * (1 - CGFloat(value) / 3)
                    Text("\(value).0")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .offset(x: 0, y: min(max(y - 6, 0), geo.size.height - 12))
                    Rectangle().fill(StrandPalette.hairline.opacity(value == 0 ? 0.8 : 0.45))
                        .frame(width: plotWidth, height: 1).offset(x: axisWidth, y: y)
                }
                Rectangle().fill(zoneColor(.high).opacity(0.025))
                    .frame(width: plotWidth, height: geo.size.height / 3).offset(x: axisWidth)
                Rectangle().fill(zoneColor(.medium).opacity(0.018))
                    .frame(width: plotWidth, height: geo.size.height / 3)
                    .offset(x: axisWidth, y: geo.size.height / 3)
                ForEach(Array(sleep.enumerated()), id: \.offset) { _, interval in
                    let x1 = axisWidth + x(interval.start, start: start, width: plotWidth, span: span)
                    let x2 = axisWidth + x(interval.end, start: start, width: plotWidth, span: span)
                    Rectangle().fill(StrandPalette.accent.opacity(0.08))
                        .frame(width: max(0, x2 - x1)).offset(x: x1)
                }
                Canvas { context, size in
                    for run in StressPresentation.lineSegments(samples) {
                        for pair in zip(run, run.dropFirst()) {
                            let a = CGPoint(x: axisWidth + x(pair.0.timestamp, start: start, width: plotWidth, span: span),
                                            y: size.height * (1 - pair.0.value / 3))
                            let b = CGPoint(x: axisWidth + x(pair.1.timestamp, start: start, width: plotWidth, span: span),
                                            y: size.height * (1 - pair.1.value / 3))
                            var path = Path(); path.move(to: a); path.addLine(to: b)
                            context.stroke(path,
                                with: .linearGradient(
                                    Gradient(colors: [zoneColor(.init(score: pair.0.value)),
                                                      zoneColor(.init(score: pair.1.value))]),
                                    startPoint: a, endPoint: b),
                                style: .init(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                if let selected {
                    let sx = axisWidth + x(selected.timestamp, start: start, width: plotWidth, span: span)
                    Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1).offset(x: sx)
                    Circle().fill(zoneColor(.init(score: selected.value))).overlay(Circle().stroke(.white, lineWidth: 2))
                        .frame(width: 12, height: 12).offset(x: sx - 6, y: geo.size.height * (1 - selected.value / 3) - 6)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                let plotX = min(max(gesture.location.x - axisWidth, 0), plotWidth)
                let date = start.addingTimeInterval(Double(plotX / plotWidth) * span)
                if let sample = StressPresentation.nearestSample(to: date, in: samples) { onSelect(sample) }
            })
        }
    }

    private func x(_ date: Date, start: Date, width: CGFloat, span: TimeInterval) -> CGFloat {
        min(max(CGFloat(date.timeIntervalSince(start) / span) * width, 0), width)
    }
}

private struct ZoneStackedBar: View {
    let distribution: StressPresentation.Distribution
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SELECTED DAY").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(StressPresentation.Zone.allCases, id: \.self) { zone in
                        zoneColor(zone).frame(width: max(0, geo.size.width * distribution.duration(for: zone) /
                                                        StressPresentation.expectedDayDuration - 2))
                    }
                    StrandPalette.surfaceRaised.frame(width: max(0, geo.size.width * (1 - distribution.coverage) - 2))
                }.clipShape(Capsule())
            }.frame(height: 12)
        }
    }
}

private struct TypicalStackedBar: View {
    let baseline: StressPresentation.Baseline
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TYPICAL · \(baseline.validDayCount) DAYS").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(StressPresentation.Zone.allCases, id: \.self) { zone in
                        zoneColor(zone).opacity(0.65).frame(width: max(0, geo.size.width * baseline.proportion(for: zone) * baseline.coverage - 2))
                    }
                    StrandPalette.surfaceRaised.frame(width: max(0, geo.size.width * (1 - baseline.coverage) - 2))
                }.clipShape(Capsule())
            }.frame(height: 12)
        }
    }
}
