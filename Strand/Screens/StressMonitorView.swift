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
                    comparisonCard(summary)
                    methodologyCard
                } else {
                    emptyState
                }
            }
        }
        .task(id: LoadKey(day: selectedDay, refresh: repo.refreshSeq)) { await loadDay() }
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
        NoopCard(tint: zoneColor(displayed.map { StressPresentation.Zone(score: $0.value) } ?? .low)) {
            VStack(spacing: 10) {
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
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(gaugeAccessibility)
        }
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
                    .accessibilityLabel("Daily stress timeline. Drag to select the nearest recorded hour.")
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
        let bounds = dayBounds(date)
        let from = Int(bounds.start.timeIntervalSince1970), to = Int(min(bounds.end, Date()).timeIntervalSince1970)
        guard to > from else { return nil }
        let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
        guard hr.count >= DaytimeStress.minHourHRSamples else { return nil }
        let rr = (try? await repo.storeHandle()?.rrIntervals(deviceId: repo.deviceId, from: from, to: to, limit: 200_000)) ?? []
        let noon = calendar.date(byAdding: .hour, value: 12, to: bounds.start) ?? bounds.start
        let offset = calendar.timeZone.secondsFromGMT(for: noon)
        let result = DaytimeStress.analyze(hr: hr, rr: rr, tzOffsetSeconds: offset)
        let end = calendar.isDate(date, inSameDayAs: today) ? Date() : nil
        return StressPresentation.summarize(date: calendar.startOfDay(for: date), points: result.hours, end: end)
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
        let current = day.distribution.proportion(for: zone), typical = baseline.proportion(for: zone)
        let delta = current - typical
        return HStack {
            Circle().fill(zoneColor(zone)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.rawValue.uppercased()).font(StrandFont.overline)
                Text(duration(day.distribution.duration(for: zone))).font(StrandFont.headline)
            }
            Spacer()
            Text("\(abs(Int((delta * 100).rounded()))) pts \(delta >= 0 ? "more" : "less") than typical")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                .accessibilityLabel("\(abs(Int((delta * 100).rounded()))) percentage points \(delta >= 0 ? "more" : "less") than typical")
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded()), hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }

    private struct LoadKey: Equatable { let day: Date; let refresh: Int }
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
            ZStack(alignment: .topLeading) {
                ForEach(Array(sleep.enumerated()), id: \.offset) { _, interval in
                    let x1 = x(interval.start, start: start, width: geo.size.width, span: span)
                    let x2 = x(interval.end, start: start, width: geo.size.width, span: span)
                    Rectangle().fill(StrandPalette.accent.opacity(0.08))
                        .frame(width: max(0, x2 - x1)).offset(x: x1)
                }
                Canvas { context, size in
                    for sample in samples {
                        let sx = x(sample.timestamp, start: start, width: size.width, span: span)
                        let sy = size.height * (1 - sample.value / 3)
                        let endX = min(size.width, sx + size.width / 16)
                        var segment = Path(); segment.move(to: CGPoint(x: sx, y: sy)); segment.addLine(to: CGPoint(x: endX, y: sy))
                        context.stroke(segment, with: .color(zoneColor(.init(score: sample.value))), style: .init(lineWidth: 3, lineCap: .round))
                    }
                }
                if let selected {
                    let sx = x(selected.timestamp, start: start, width: geo.size.width, span: span)
                    Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1).offset(x: sx)
                    Circle().fill(zoneColor(.init(score: selected.value))).overlay(Circle().stroke(.white, lineWidth: 2))
                        .frame(width: 12, height: 12).offset(x: sx - 6, y: geo.size.height * (1 - selected.value / 3) - 6)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                let date = start.addingTimeInterval(Double(gesture.location.x / max(geo.size.width, 1)) * span)
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
                        zoneColor(zone).frame(width: max(0, geo.size.width * distribution.proportion(for: zone) - 2))
                    }
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
                        zoneColor(zone).opacity(0.65).frame(width: max(0, geo.size.width * baseline.proportion(for: zone) - 2))
                    }
                }.clipShape(Capsule())
            }.frame(height: 12)
        }
    }
}
