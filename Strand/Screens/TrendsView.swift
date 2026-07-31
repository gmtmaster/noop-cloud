import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Trends
//
// The longitudinal view, rebuilt on the locked Noop component system so every
// surface, height and gap is identical: one SegmentedPillControl for the range,
// a hero recovery ChartCard, a uniform grid of HRV / Resting HR / Day Strain
// ChartCards (all NoopMetrics.chartHeight tall), and the whole history as a
// recovery YearHeatStrip in a NoopCard. No hand-sized cards anywhere.

struct TrendsView: View {
    @EnvironmentObject var repo: Repository
    // NOTE: deliberately does NOT observe LiveState — Trends shows historical data only, and
    // observing it forced a full re-render of this subtree on every ~1 Hz live-HR tick.

    // The shared range control: W(7) / M(30) / 3M(90) / 6M(180) / 1Y(365) / ALL.
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90, half = 180, year = 365, all = 0
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week:    return String(localized: "W")
            case .month:   return String(localized: "M")
            case .quarter: return String(localized: "3M")
            case .half:    return String(localized: "6M")
            case .year:    return String(localized: "1Y")
            case .all:     return String(localized: "ALL")
            }
        }
        /// Trailing-day window, or nil for "all history".
        var days: Int? { self == .all ? nil : rawValue }

        /// This range plus every LARGER range, ascending — the auto-expand search
        /// order when the selected window holds zero points.
        var widening: [Range] {
            let order: [Range] = [.week, .month, .quarter, .half, .year, .all]
            guard let i = order.firstIndex(of: self) else { return [.all] }
            return Array(order[i...])
        }
    }

    @State private var range: Range = .quarter

    private enum TrendMetric: String, CaseIterable, Identifiable {
        case strain, recovery, sleep, hrv, restingHR
        var id: String { rawValue }
        var title: String {
            switch self {
            case .strain: return String(localized: "Strain")
            case .recovery: return String(localized: "Recovery")
            case .sleep: return String(localized: "Sleep")
            case .hrv: return "HRV"
            case .restingHR: return "RHR"
            }
        }
    }

    private enum TrendMode: String, CaseIterable, Identifiable {
        case summary, bars, line
        var id: String { rawValue }
        var label: String {
            switch self {
            case .summary: return String(localized: "SUMMARY")
            case .bars: return String(localized: "BARS")
            case .line: return String(localized: "LINE")
            }
        }
    }

    @State private var selectedMetric: TrendMetric = .strain
    @State private var trendMode: TrendMode = .summary

    // #436 — shareable offline trends report (PDF over a date range). The sheet owns its
    // own range picker; this just presents it with the loaded history.
    @State private var showingReport = false

    /// Rest's per-day series, keyed by "yyyy-MM-dd". Rest is the sleep_performance COMPOSITE (the same
    /// number the Today Rest score + the Sleep Rest-detail plot, #614 follow-up) — NOT raw efficiency,
    /// which read differently under the same "Rest" label and made the Trends Rest graph disagree with
    /// the Today Rest score (#732). sleep_performance is a metricSeries, not a DailyMetric field, so load
    /// it once (mirroring TodayView's restScore source) and key by day for `resolve` below.
    @State private var sleepPerfByDay: [String: Double] = [:]
    @State private var sleepSessions: [CachedSleepSession] = []
    @State private var habitualMidsleepSec: Int?

    // #710 — browse previous weeks in the Week-in-review digest. 0 = the week containing today; each step
    // back is one Mon–Sun week earlier. Clamped so it never runs past the earliest day we hold (see
    // `weekAnchorDay` / `stepWeek`). The Trends RANGE control below is independent of this — it scopes the
    // long-form charts; this only moves the weekly digest at the top.
    @State private var weekOffset = 0

    // Effort display scale (#268) — routes the Effort small-multiple's numbers + unit. Display-only.
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    // yyyy-MM-dd → Date (en_US_POSIX, UTC), per task spec.
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private func date(_ day: String) -> Date? { Self.dayParser.date(from: day) }

    // MARK: Window selection (relative to the LATEST day, with auto-expand)

    /// The latest recorded day across all history (anchors every window).
    private var latestDay: Date? {
        guard let d = repo.days.last?.day else { return nil }
        return date(d)
    }

    /// Days for a given range, taken RELATIVE TO TODAY (the phone's local date) — not the latest
    /// recorded day, which on a stale import anchored W/M/3M to months-old data so it looked current
    /// (issue #23). Empty short windows auto-widen (see `resolve`), so old imports surface under a
    /// wider range / All history instead of masquerading as recent. `.all` returns everything.
    /// ISO yyyy-MM-dd compares chronologically.
    private func days(for r: Range) -> [DailyMetric] {
        guard let n = r.days else { return repo.days }
        let cutoffKey = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(n - 1), to: Date()) ?? Date())
        return repo.days.filter { $0.day >= cutoffKey }
    }

    /// Build trend points from a metric accessor over a day slice.
    private func points(_ days: ArraySlice<DailyMetric>, _ value: (DailyMetric) -> Double?) -> [TrendPoint] {
        days.compactMap { d in
            guard let v = value(d), let dt = date(d.day) else { return nil }
            return TrendPoint(date: dt, value: v)
        }
    }
    private func points(_ days: [DailyMetric], _ value: (DailyMetric) -> Double?) -> [TrendPoint] {
        points(days[...], value)
    }

    // MARK: Resolved metric (memoized per body)
    //
    // days(for:) / points each re-filter the full multi-year `repo.days` array,
    // and the subviews used to fan out to them many times per render (caption +
    // widened + windowPoints, ×4 metrics). `resolve(_:)` walks the widening order
    // ONCE per metric (the smallest range ≥ selected whose window holds ≥1 point,
    // else ALL), captures that window's points and its effective range, then
    // derives the caption / widened flag from those — so a single body evaluation
    // filters each metric's window once instead of dozens of times. Identical
    // results to the old per-helper (effectiveRange / windowPoints / caption /
    // widened) computation.
    private struct ResolvedMetric {
        var points: [TrendPoint]
        var effective: Range
        var widened: Bool
        var caption: String
    }

    private func resolve(_ value: (DailyMetric) -> Double?) -> ResolvedMetric {
        // Find the smallest range ≥ selected whose window has ≥1 point, keeping
        // that window's points so we don't re-filter to read them back.
        for r in range.widening {
            let pts = points(days(for: r), value)
            if !pts.isEmpty {
                return ResolvedMetric(points: pts, effective: r,
                                      widened: r != range, caption: caption(count: pts.count, eff: r))
            }
        }
        // No range held data: fall back to ALL (matches effectiveRange()).
        let pts = points(days(for: .all), value)
        return ResolvedMetric(points: pts, effective: .all,
                              widened: .all != range, caption: caption(count: pts.count, eff: .all))
    }

    /// Caption text from an already-resolved count + effective range. Mirrors
    /// `caption(_:)` exactly but takes precomputed inputs to avoid re-filtering.
    private func caption(count n: Int, eff: Range) -> String {
        if eff != range {
            return n == 1
                ? String(localized: "1 reading · sparse, widened to \(name(for: eff))")
                : String(localized: "\(n) readings · sparse, widened to \(name(for: eff))")
        }
        return n == 1
            ? String(localized: "1 reading · \(name(for: range))")
            : String(localized: "\(n) readings · \(name(for: range))")
    }

    /// A padded value range for a series so the line isn't flat against the axis.
    private func valueRange(_ pts: [TrendPoint], fallback: ClosedRange<Double>, pad: Double = 0.12) -> ClosedRange<Double> {
        let vals = pts.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return fallback }
        if hi <= lo { return (lo - 1)...(hi + 1) }
        let span = hi - lo
        return (lo - span * pad)...(hi + span * pad)
    }

    private func mean(_ pts: [TrendPoint]) -> Double? {
        guard !pts.isEmpty else { return nil }
        return pts.map(\.value).reduce(0, +) / Double(pts.count)
    }

    /// The window's trend as a signed mean-of-recent-half minus mean-of-earlier-half. Drives a
    /// TrendChip so the card reads its direction at a glance, like Today's deltas. nil for a window
    /// too short to split. `higherIsBetter == nil` (e.g. Effort) keeps the chip neutral.
    private func periodChange(_ pts: [TrendPoint]) -> Double? {
        guard pts.count >= 4 else { return nil }
        let mid = pts.count / 2
        let earlier = pts.prefix(mid).map(\.value)
        let recent = pts.suffix(pts.count - mid).map(\.value)
        guard !earlier.isEmpty, !recent.isEmpty else { return nil }
        let e = earlier.reduce(0, +) / Double(earlier.count)
        let r = recent.reduce(0, +) / Double(recent.count)
        return r - e
    }

    /// A TrendChip for a window's period change, coloured green/rose by whether the move is good for
    /// THIS metric (`higherIsBetter`); neutral when direction has no valence or the change is flat.
    @ViewBuilder
    private func changeChip(_ pts: [TrendPoint], higherIsBetter: Bool?, fmt: @escaping (Double) -> String) -> some View {
        if let d = periodChange(pts), abs(d) > 0.0001 {
            let sign = d >= 0 ? "+" : "−"
            let color: Color = {
                guard let better = higherIsBetter else { return StrandPalette.textTertiary }
                return (d > 0) == better ? StrandPalette.statusPositive : StrandPalette.metricRose
            }()
            TrendChip(text: "\(sign)\(fmt(abs(d))) vs prev", color: color)
        }
    }

    /// "Trailing 90 days" / "All history" — used as a card subtitle.
    private var rangeSubtitle: String {
        guard let n = range.days else { return String(localized: "All history") }
        return String(localized: "Trailing \(n) days")
    }

    private func name(for r: Range) -> String {
        switch r {
        case .week:    return String(localized: "week")
        case .month:   return String(localized: "month")
        case .quarter: return String(localized: "3 months")
        case .half:    return String(localized: "6 months")
        case .year:    return String(localized: "year")
        case .all:     return String(localized: "all history")
        }
    }

    var body: some View {
        // The liquid metric cards now tap through to their MetricDetailView (matching Today's card
        // taps + Explore's rows). On iOS each tab already supplies a NavigationStack, so those pushes
        // land in the ambient stack. On macOS the .trends detail pane has NO enclosing NavigationStack
        // (RootView), so — exactly like MetricExplorerView (#753) — wrap the scaffold in one here so the
        // pushes get Back chrome instead of hanging. The SAME shared scaffold renders on both.
        #if os(macOS)
        NavigationStack { scaffold }
        #else
        scaffold
        #endif
    }

    private var scaffold: some View {
        ScreenScaffold(title: "Trends", subtitle: "The thread of you over time.",
                       // PERF (scroll): lazy column — byte-identical layout (LazyVStack == eager VStack
                       // alignment/spacing/header). The content is one inner eager VStack, so the staggered
                       // section reveal is unchanged; this only defers building that stack until it scrolls in.
                       onRefresh: { await repo.refresh() },
                       lazy: true,
                       topBackground: liquidScaffoldSky()) {
            if repo.days.isEmpty {
                ComingSoon(what: repo.loaded
                    ? "Trends need history to draw. Import your WHOOP export in Data Sources to see weeks, months and years instantly."
                    : "Loading your history…")
            } else {
                // Resolve each metric's window ONCE per body and pass the results
                // down — rangeBar/heroRecovery/smallMultiples all reuse these
                // instead of re-filtering repo.days through caption/widened/
                // windowPoints on every render (hover, animation, 1 Hz HR tick).
                let recovery = resolve { $0.recovery }
                let hrv = resolve { $0.avgHrv }
                let rhr = resolve { $0.restingHr.map(Double.init) }
                let respiratory = resolve { $0.respRateBpm }
                let skinTemp = resolve { $0.skinTempDevC }
                let strain = resolve { $0.strain }
                // Rest = the sleep_performance composite — the same number the Today Rest score shows
                // (#732); see sleepPerfByDay. resolve() still does the windowing/widening.
                let rest = resolve { sleepPerfByDay[$0.day] }
                let localDebt = Dictionary(sleepDebtHistory.compactMap { point in
                    point.carriedDebtMinutes.map { (point.day, $0) }
                }, uniquingKeysWith: { _, last in last })
                let sleepDebt = resolve { localDebt[$0.day] }
                performanceDashboard(recovery: recovery, strain: strain, rest: rest, hrv: hrv, rhr: rhr,
                                     respiratory: respiratory, skinTemp: skinTemp, sleepDebt: sleepDebt)
            }
        }
        // #436 — present the offline trends-report exporter (range picker + PDF export).
        .sheet(isPresented: $showingReport) {
            TrendsReportSheet(days: repo.days)
        }
        // #732 — load the resolved sleep_performance series so Rest plots the SAME composite the Today
        // Rest score uses (not raw efficiency). Mirrors TodayView's restScore read. Keyed on the day
        // count so a newly-banked/-scored night refreshes Rest reactively, like the other metrics that
        // read `repo.days` directly (and like the Android LaunchedEffect(days) twin).
        .task(id: repo.days.count) {
            let s = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
            sleepPerfByDay = Dictionary(s.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
            sleepSessions = await repo.allSleepSessions()
            habitualMidsleepSec = await repo.habitualMidsleepSec()
        }
    }

    // MARK: - WHOOP-inspired metric explorer

    private func performanceDashboard(
        recovery: ResolvedMetric, strain: ResolvedMetric, rest: ResolvedMetric,
        hrv: ResolvedMetric, rhr: ResolvedMetric, respiratory: ResolvedMetric,
        skinTemp: ResolvedMetric, sleepDebt: ResolvedMetric
    ) -> some View {
        let selected = selectedResolved(recovery: recovery, strain: strain, rest: rest, hrv: hrv, rhr: rhr)
        return VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            trendDateRangeHeader
            metricTabs
            SegmentedPillControl(TrendMode.allCases, selection: $trendMode) { $0.label }

            Group {
                switch trendMode {
                case .summary:
                    trendSummary(metric: selectedMetric, resolved: selected)
                case .bars:
                    trendChart(metric: selectedMetric, resolved: selected, bars: true)
                case .line:
                    trendChart(metric: selectedMetric, resolved: selected, bars: false)
                }
            }
            .animation(StrandMotion.interactive, value: trendMode)

            trendStatistics(metric: selectedMetric, resolved: selected)

            // Keep every previously-supported signal one tap away, below the focused explorer.
            smallMultiples(hrv: hrv, rhr: rhr, respiratory: respiratory, skinTemp: skinTemp,
                           strain: strain, rest: rest, sleepDebt: sleepDebt)
            yearStrip
            exportReportRow
        }
    }

    private var trendDateRangeHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { stepRange(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 32, height: 32)
                }
                Spacer()
                Text(rangeSubtitle.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Button { stepRange(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 32, height: 32)
                }
            }
            .foregroundStyle(StrandPalette.textSecondary)
            .background(StrandPalette.surfaceInset, in: Capsule())
            SegmentedPillControl(Range.allCases, selection: $range) { $0.label }
        }
    }

    private func stepRange(_ delta: Int) {
        guard let index = Range.allCases.firstIndex(of: range) else { return }
        let next = min(Range.allCases.count - 1, max(0, index + delta))
        withAnimation(StrandMotion.interactive) { range = Range.allCases[next] }
    }

    private var metricTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(TrendMetric.allCases) { metric in
                    Button {
                        withAnimation(StrandMotion.interactive) { selectedMetric = metric }
                    } label: {
                        VStack(spacing: 7) {
                            Text(metric.title.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(0.8)
                            Capsule()
                                .fill(selectedMetric == metric ? trendTint(metric) : Color.clear)
                                .frame(height: 2)
                        }
                        .foregroundStyle(selectedMetric == metric ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedMetric == metric ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func selectedResolved(recovery: ResolvedMetric, strain: ResolvedMetric, rest: ResolvedMetric,
                                  hrv: ResolvedMetric, rhr: ResolvedMetric) -> ResolvedMetric {
        switch selectedMetric {
        case .strain: return strain
        case .recovery: return recovery
        case .sleep: return rest
        case .hrv: return hrv
        case .restingHR: return rhr
        }
    }

    private func trendTint(_ metric: TrendMetric) -> Color {
        switch metric {
        case .strain: return StrandPalette.strain066
        case .recovery: return StrandPalette.recovery100
        case .sleep: return StrandPalette.restColor
        case .hrv: return StrandPalette.metricPurple
        case .restingHR: return StrandPalette.metricRose
        }
    }

    private func trendRange(_ metric: TrendMetric, points: [TrendPoint]) -> ClosedRange<Double> {
        switch metric {
        case .strain, .recovery, .sleep: return 0...100
        case .hrv: return valueRange(points, fallback: 20...120)
        case .restingHR: return valueRange(points, fallback: 40...80)
        }
    }

    private func trendValue(_ metric: TrendMetric, _ value: Double) -> String {
        switch metric {
        case .strain: return UnitFormatter.effortDisplay(value, scale: effortScale)
        case .recovery, .sleep: return "\(Int(value.rounded()))%"
        case .hrv: return "\(Int(value.rounded())) ms"
        case .restingHR: return "\(Int(value.rounded())) bpm"
        }
    }

    private func trendSummary(metric: TrendMetric, resolved: ResolvedMetric) -> some View {
        let latest = resolved.points.last?.value
        let tint = trendTint(metric)
        let maximum: Double = metric == .strain ? 100 : (metric == .hrv ? max(120, resolved.points.map(\.value).max() ?? 120) : 100)
        let fraction = min(1, max(0, (latest ?? 0) / maximum))
        return VStack(spacing: NoopMetrics.gap) {
            NavigationLink { metricDetail(metricKey(metric)) } label: {
                ZStack {
                    Circle().stroke(StrandPalette.surfaceInset, lineWidth: 14)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 5) {
                        Text(metric.title.uppercased()).strandOverline()
                        Text(latest.map { trendValue(metric, $0) } ?? "—")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .minimumScaleFactor(0.72)
                        if metric == .strain, let count = repo.today?.exerciseCount {
                            Text("\(count) \(count == 1 ? "ACTIVITY" : "ACTIVITIES")")
                                .font(StrandFont.captionNumber).foregroundStyle(tint)
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .overlay(Capsule().stroke(tint.opacity(0.8), lineWidth: 1))
                        }
                    }
                }
                .frame(width: 230, height: 230)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidPressStyle())

            NoopCard(tint: tint) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: trendSymbol(metric)).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(trendContextTitle(metric, latest: latest))
                            .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text(trendContextDetail(metric, points: resolved.points))
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func trendChart(metric: TrendMetric, resolved: ResolvedMetric, bars: Bool) -> some View {
        let points = resolved.points
        let tint = trendTint(metric)
        let range = trendRange(metric, points: points)
        return ChartCard(title: LocalizedStringKey(metric.title), subtitle: resolved.caption,
                         trailing: points.last.map { trendValue(metric, $0.value) },
                         height: 250, tint: tint) {
            if points.count >= 2 {
                if bars {
                    RoundedBarTrendChart(points: points, valueRange: range, tint: tint,
                                         valueFormat: { trendValue(metric, $0) },
                                         accessibilityLabel: String(localized: "\(metric.title) bar chart"))
                } else {
                    glowChart(points: points, gradient: gradient(tint), valueRange: range, tip: tint,
                              valueFormat: { trendValue(metric, $0) },
                              accessibilityLabel: String(localized: "\(metric.title) line chart"))
                }
            } else {
                sparsePlaceholder
            }
        } footer: {
            ChartFooter([
                ("Average", mean(points).map { trendValue(metric, $0) } ?? "—"),
                ("Peak", points.map(\.value).max().map { trendValue(metric, $0) } ?? "—"),
                ("Days", "\(points.count)")
            ])
        }
    }

    private func trendStatistics(metric: TrendMetric, resolved: ResolvedMetric) -> some View {
        let points = resolved.points
        let periodDays = days(for: resolved.effective)
        let averageHR = periodDays.compactMap(\.restingHr).map(Double.init)
        let calories = periodDays.compactMap(\.activeKcalEst)
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Statistics", overline: LocalizedStringKey(rangeSubtitle))
            HStack(spacing: 0) {
                trendStat("AVERAGE", mean(points).map { trendValue(metric, $0) } ?? "—", trendTint(metric))
                trendStat(metric == .strain ? "AVG RHR" : "HIGH",
                          metric == .strain
                            ? meanValues(averageHR).map { "\(Int($0.rounded())) bpm" } ?? "—"
                            : points.map(\.value).max().map { trendValue(metric, $0) } ?? "—",
                          StrandPalette.textSecondary)
                trendStat(metric == .strain ? "CALORIES" : "LOW",
                          metric == .strain
                            ? meanValues(calories).map { "\(Int($0.rounded())) kcal" } ?? "—"
                            : points.map(\.value).min().map { trendValue(metric, $0) } ?? "—",
                          StrandPalette.textSecondary)
            }
            .padding(.vertical, 14)
            .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(StrandPalette.hairline, lineWidth: 0.75))
        }
    }

    private func trendStat(_ label: LocalizedStringKey, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Text(label).font(StrandFont.overline).foregroundStyle(StrandPalette.textTertiary)
            Text(value).font(StrandFont.captionNumber).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func meanValues(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func metricKey(_ metric: TrendMetric) -> String {
        switch metric {
        case .strain: return "strain"
        case .recovery: return "recovery"
        case .sleep: return "sleep_performance"
        case .hrv: return "hrv"
        case .restingHR: return "rhr"
        }
    }

    private func trendSymbol(_ metric: TrendMetric) -> String {
        switch metric {
        case .strain: return "figure.run"
        case .recovery: return "gauge.with.dots.needle.50percent"
        case .sleep: return "moon.zzz.fill"
        case .hrv: return "waveform.path.ecg"
        case .restingHR: return "heart.fill"
        }
    }

    private func trendContextTitle(_ metric: TrendMetric, latest: Double?) -> String {
        guard let latest else { return String(localized: "More history needed") }
        switch metric {
        case .strain:
            return latest >= 70 ? String(localized: "Strenuous exertion") : String(localized: "Measured exertion")
        case .recovery: return String(localized: "Recovery context")
        case .sleep: return String(localized: "Sleep consistency")
        case .hrv: return String(localized: "HRV trend")
        case .restingHR: return String(localized: "Resting heart rate trend")
        }
    }

    private func trendContextDetail(_ metric: TrendMetric, points: [TrendPoint]) -> String {
        guard !points.isEmpty else { return String(localized: "Record more days to see a personal trend.") }
        let change = periodChange(points)
        let direction = change.map { $0 > 0 ? String(localized: "rising") : String(localized: "falling") }
            ?? String(localized: "steady")
        switch metric {
        case .strain: return String(localized: "Your recorded daily cardiovascular load is \(direction) across this period.")
        case .recovery: return String(localized: "Your recovery scores are \(direction) across this period.")
        case .sleep: return String(localized: "Your sleep performance is \(direction) across this period.")
        case .hrv: return String(localized: "Your overnight HRV is \(direction) relative to the earlier half of this period.")
        case .restingHR: return String(localized: "Your resting heart rate is \(direction) relative to the earlier half of this period.")
        }
    }

    // MARK: Week-in-review digest with prev/next week browsing (#710)

    /// The earliest "yyyy-MM-dd" we hold (history is oldest → newest), used to clamp how far back the
    /// week stepper can go.
    private var earliestDay: String? { repo.days.first?.day }

    /// The most negative `weekOffset` allowed: the number of whole weeks between the earliest day's week
    /// and this week. Beyond that there's no data to digest, so the back chevron disables. 0 when history
    /// is empty or unparseable (so we stay on this week).
    private var minWeekOffset: Int {
        guard
            let earliest = earliestDay,
            let earliestMon = WeeklyDigestEngine.mondayOfWeek(containing: earliest),
            let thisMon = WeeklyDigestEngine.mondayOfWeek(containing: Repository.localDayKey(Date()))
        else { return 0 }
        // Walk weeks back from this Monday until we pass the earliest week. Bounded by history length.
        var off = 0
        var mon = thisMon
        while mon > earliestMon && off > -520 {           // hard cap ~10 years so a bad date can't spin
            mon = WeeklyDigestEngine.addDays(mon, -7)
            off -= 1
        }
        return off
    }

    /// The anchor day (any day in the target week) for the current `weekOffset`: today shifted back by
    /// `weekOffset` whole weeks. The engine snaps it to that week's Monday.
    private var weekAnchorDay: String {
        WeeklyDigestEngine.addDays(Repository.localDayKey(Date()), weekOffset * 7)
    }

    /// Move the digest one week earlier (-1) or later (+1), clamped to [minWeekOffset, 0] — never into a
    /// future week, never past the earliest week we hold.
    private func stepWeek(_ delta: Int) {
        let next = weekOffset + delta
        weekOffset = max(minWeekOffset, min(0, next))
    }

    /// The week-in-review digest for the selected week, with prev/next chevrons in its header. The digest
    /// for `weekAnchorDay` is built straight from the shared `WeeklyDigestSource` (the same builder the
    /// standalone WeeklyDigestCard uses) so past weeks render in the identical format. The whole block
    /// self-hides only when there's no data in ANY week (an all-empty history), matching the old card.
    @ViewBuilder
    private var weeklyDigestNav: some View {
        let digest = WeeklyDigestSource.digest(from: repo.days, anchorDay: weekAnchorDay)
        // Only hide the navigation entirely when the WHOLE history is empty — an empty PAST week still
        // shows the header + chevrons so the user can step to a week that does hold data.
        if repo.days.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                weekNavBar
                if digest.isEmpty {
                    // This particular week had no readings — keep the chevrons above so the user can move on.
                    DataPendingNote(
                        title: "No readings this week",
                        message: "Step to another week with the arrows above to see its review.")
                } else {
                    WeeklyDigestContent(digest: digest, compact: true)
                }
            }
        }
    }

    /// Prev/next week stepper. Back is clamped at the earliest week we hold; forward is clamped at this
    /// week (no future weeks). Mirrors the FullDayChartView day stepper's flat accent chevrons (#597).
    private var weekNavBar: some View {
        let atOldest = weekOffset <= minWeekOffset
        let atNewest = weekOffset >= 0
        return HStack(spacing: NoopMetrics.cardInnerSpacing) {
            Button { stepWeek(-1) } label: {
                Image(systemName: "chevron.left").font(StrandFont.headline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(atOldest ? StrandPalette.textTertiary : StrandPalette.accent)
            .disabled(atOldest)
            .accessibilityLabel("Previous week")

            Spacer()
            VStack(spacing: 2) {
                Text(weekOffset == 0 ? String(localized: "This week") : weekOffsetLabel)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("Week in review")
                    .strandOverline()
            }
            Spacer()

            Button { stepWeek(1) } label: {
                Image(systemName: "chevron.right").font(StrandFont.headline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(atNewest ? StrandPalette.textTertiary : StrandPalette.accent)
            .disabled(atNewest)
            .accessibilityLabel("Next week")
        }
        .padding(.horizontal, NoopMetrics.space1)
        .accessibilityElement(children: .contain)
    }

    /// "Last week" for -1, else the count of weeks back ("3 weeks ago") for the stepper's centre label.
    private var weekOffsetLabel: String {
        let n = -weekOffset
        if n == 1 { return String(localized: "Last week") }
        return String(localized: "\(n) weeks ago")
    }

    // MARK: Week in Review — the Charge / Effort / Rest trio in pip language

    /// The three daily scores as NOOP pip rows over the resolved window: Charge (recovery, 0–100),
    /// Effort (strain, shown on the WHOOP 0–21 scale per the unit toggle) and Rest (sleep_performance
    /// composite, 0–100 — the same metric the Today Rest score shows, #732). Each value ticks up via
    /// `CountUpText`; the segmented `PipBar` cascades on appear. Self-
    /// hides when none of the three carry a window mean, so an empty history shows nothing here.
    @ViewBuilder
    private func weekInReview(charge: ResolvedMetric, effort: ResolvedMetric, rest: ResolvedMetric) -> some View {
        let chargeAvg = mean(charge.points)
        let effortAvg = mean(effort.points)   // stored 0–100 internal Effort scale
        let restAvg = mean(rest.points)
        if chargeAvg != nil || effortAvg != nil || restAvg != nil {
            NoopCard(tint: StrandPalette.chargeColor) {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    SectionHeader("Week in review", overline: "Charge · Effort · Rest")
                    if let v = chargeAvg {
                        pipScoreRow(label: "Charge", value: v, range: 0...100,
                                    tint: StrandPalette.chargeColor, frac: v / 100,
                                    format: { "\(Int($0.rounded()))" })
                    }
                    if let v = effortAvg {
                        // Effort is stored 0–100 but reads on the WHOOP 0–21 scale per the unit toggle:
                        // convert the displayed number + bar position to the user's chosen Effort scale so
                        // the pip fill and the count-up value agree (both on the same scale).
                        let display = UnitFormatter.effortValue(v, scale: effortScale)
                        let maxV = UnitFormatter.effortValue(100, scale: effortScale)
                        // On the 0–21 WHOOP scale Effort reads to one decimal (e.g. "9.0"); on the 0–100
                        // scale it's a whole number — match `effortScaleMax` so the count-up format agrees.
                        let oneDecimal = effortScale == .whoop
                        // The vessel fills off the stored 0–100 internal scale (v), so it agrees with the
                        // Charge/Rest vessels regardless of the displayed Effort unit.
                        pipScoreRow(label: "Effort", value: display, range: 0...maxV,
                                    tint: StrandPalette.effortColor, frac: v / 100,
                                    format: { oneDecimal ? String(format: "%.1f", $0) : "\(Int($0.rounded()))" })
                    }
                    if let v = restAvg {
                        pipScoreRow(label: "Rest", value: v, range: 0...100,
                                    tint: StrandPalette.restColor, frac: v / 100,
                                    format: { "\(Int($0.rounded()))" })
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// One pip row matching `PipBarRow`'s layout, but with the value driven by `CountUpText` so the big
    /// number ticks up. UPPERCASE label + a small liquid vessel (the score as a fill) beside the big white
    /// count-up value, over the segmented count-up bar. `frac` (0…1) is the score on the shared 0–100
    /// internal scale so the three vessels read against the same fill — a small liquid accent on a single
    /// headline metric, exactly where it reads well (not on a chart).
    private func pipScoreRow(label: LocalizedStringKey, value: Double, range: ClosedRange<Double>,
                             tint: Color, frac: Double, format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(label)
                .font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(StrandPalette.textSecondary)
            HStack(spacing: NoopMetrics.space3) {
                // Static (posed) vessel — a small liquid gauge, not a live 60fps canvas, so the three
                // in this card cost a single cached frame each (same call as Today's small vessels).
                LiquidVessel(value: max(0, min(1, frac)), tint: tint, animated: false)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                CountUpText(value: value, format: format,
                            font: StrandFont.number(30, weight: .bold),
                            color: StrandPalette.textPrimary)
            }
            PipBar(value: value, range: range, tint: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(format(value)))
    }

    // MARK: Export trends report (#436)

    /// A footer entry that opens the shareable-report sheet. Flat WHOOP card with a blue accent
    /// action — the icon, label and "Export" CTA all read in the accent (blue) world, no gold.
    private var exportReportRow: some View {
        NoopCard(tint: StrandPalette.accent) {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: "doc.richtext")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("Export trends report").strandOverline()
                    Text("A shareable one-page PDF of recovery, sleep, HRV, resting HR and strain over a range, saved on your \(Platform.deviceNoun).")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: NoopMetrics.space2)
                // The card's call-to-action — routed through the unified button system (secondary kind:
                // a quiet raised capsule that reads as the card action, not the one primary on the page).
                NoopButton("Export", systemImage: "square.and.arrow.up", kind: .secondary) {
                    showingReport = true
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Range control

    private func rangeBar(recovery: ResolvedMetric) -> some View {
        let cap = recovery.caption
        let isWide = recovery.widened
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack {
                SegmentedPillControl(Range.allCases, selection: $range) { $0.label }
                Spacer()
                Text(rangeSubtitle).strandOverline()
            }
            Text(cap)
                .font(StrandFont.footnote)
                .foregroundStyle(isWide ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                .accessibilityLabel(cap)
        }
    }

    // MARK: Hero — recovery over time

    @ViewBuilder
    private func heroRecovery(recovery: ResolvedMetric) -> some View {
        let pts = recovery.points
        let avg = mean(pts)
        // Charge world — recovery percentage over time, rendered as rounded native bars so the
        // longitudinal hierarchy reads closer to the score-card language.
        let card = ChartCard(
            title: "Charge",
            // The range bar above already prints the authoritative reading-count caption;
            // the hero only names its window so the count isn't doubled in one card height.
            subtitle: rangeSubtitle,
            trailing: avg.map { "\(Int($0.rounded()))" },
            height: NoopMetrics.chartHeight,
            tint: StrandPalette.chargeColor,
            chart: {
                if pts.count >= 2 {
                    RoundedBarTrendChart(points: pts, valueRange: 0...100,
                                         tint: StrandPalette.chargeColor,
                                         valueFormat: { "\(Int($0.rounded()))" },
                                         accessibilityLabel: String(localized: "Charge trend"))
                } else {
                    sparsePlaceholder
                }
            },
            footer: {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    HStack {
                        ChartFooter([
                            ("Avg", avg.map { "\(Int($0.rounded()))" } ?? "—"),
                            ("Peak", pts.map(\.value).max().map { "\(Int($0.rounded()))" } ?? "—"),
                            ("Low", pts.map(\.value).min().map { "\(Int($0.rounded()))" } ?? "—"),
                            ("Days", "\(pts.count)"),
                        ])
                        changeChip(pts, higherIsBetter: true, fmt: { "\(Int($0.rounded()))" })
                    }
                }
            }
        )
        // Tap the hero to open the full Charge (recovery) metric detail — matching Today's card taps.
        // LiquidPressStyle gives the physical settle-inward on press (the liquid tap language). The card's
        // own rich labels (title + chart series + footer stats) are surfaced by the link's button element,
        // with a hint that a tap opens the detail.
        NavigationLink { metricDetail("recovery") } label: { card }
            .buttonStyle(LiquidPressStyle())
            .accessibilityHint(Text(String(localized: "Opens the full Charge metric.")))
    }

    /// The per-metric detail page (chart + history) for a catalog key — the same tap-through target Today
    /// and Explore use. Falls back to the metrics Explorer if the key isn't in the catalog.
    @ViewBuilder
    private func metricDetail(_ key: String) -> some View {
        if key == "sleep_debt_min" {
            SleepDebtDetailView(history: sleepDebtHistory)
        } else if let m = MetricCatalog.all.first(where: { $0.key == key }) {
            MetricDetailView(metric: m)
        } else {
            MetricExplorerView()
        }
    }

    private var sleepDebtHistory: [SleepDebtHistoryPoint] {
        let parts = sleepSessionParts
        return SleepNeedEngine.history(repo.days.map { day in
            let split = parts[day.day]
            return SleepNeedNightInput(day: day.day,
                mainSleepMinutes: split?.main ?? day.totalSleepMin,
                napSleepMinutes: split?.naps ?? 0, strain: day.strain, efficiency: day.efficiency,
                importedWhoopNeedMinutes: repo.importedSleep[day.day]?.needMin,
                importedWhoopDebtMinutes: repo.importedSleep[day.day]?.debtMin)
        })
    }

    private var sleepSessionParts: [String: (main: Double, naps: Double)] {
        let grouped = Dictionary(grouping: sleepSessions) {
            Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.endTs)))
        }
        return grouped.reduce(into: [:]) { result, pair in
            let sessions = pair.value.sorted { $0.effectiveStartTs < $1.effectiveStartTs }
            let main = Set(SleepView.mainNightGroup(sessions, habitualMidsleepSec: habitualMidsleepSec).map(\.startTs))
            func asleep(_ session: CachedSleepSession) -> Double {
                let duration = Double(max(0, session.endTs - session.effectiveStartTs)) / 60
                guard let raw = session.efficiency else { return duration }
                return duration * min(max(raw > 1 ? raw / 100 : raw, 0), 1)
            }
            result[pair.key] = sessions.reduce(into: (main: 0, naps: 0)) { totals, session in
                if main.contains(session.startTs) { totals.main += asleep(session) }
                else { totals.naps += asleep(session) }
            }
        }
    }

    // MARK: Small multiples — physiologic lines + score bars

    private func smallMultiples(
        hrv: ResolvedMetric,
        rhr: ResolvedMetric,
        respiratory: ResolvedMetric,
        skinTemp: ResolvedMetric,
        strain: ResolvedMetric,
        rest: ResolvedMetric,
        sleepDebt: ResolvedMetric
    ) -> some View {
        let cols = [GridItem(.adaptive(minimum: 320), spacing: NoopMetrics.gap)]
        let hrvPts = hrv.points
        let rhrPts = rhr.points
        let respPts = respiratory.points
        let skinPts = skinTemp.points
        let strainPts = strain.points
        let restPts = rest.points
        let debtPts = sleepDebt.points

        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            // No trailing window label — the range bar's overline already states it.
            SectionHeader("Daily signals", overline: "Trends")
            LazyVGrid(columns: cols, alignment: .leading, spacing: NoopMetrics.gap) {
                // HRV / Resting HR are Charge sub-signals → the Charge (green) card world, each line
                // keeping its established metric hue for legibility. Effort is the WHOOP blue strain world.
                metricChart(
                    title: "Heart rate variability", unit: "ms",
                    accessibilityTitle: String(localized: "Heart rate variability"),
                    metricKey: "hrv",
                    points: hrvPts,
                    gradient: gradient(StrandPalette.metricPurple),
                    tip: StrandPalette.metricPurple,
                    tint: StrandPalette.chargeColor,
                    higherIsBetter: true,
                    range: valueRange(hrvPts, fallback: 20...120),
                    fmt: { "\(Int($0.rounded()))" }
                )
                metricChart(
                    title: "Resting heart rate", unit: "bpm",
                    accessibilityTitle: String(localized: "Resting heart rate"),
                    metricKey: "rhr",
                    points: rhrPts,
                    gradient: gradient(StrandPalette.metricRose),
                    tip: StrandPalette.metricRose,
                    tint: StrandPalette.chargeColor,
                    higherIsBetter: false,
                    range: valueRange(rhrPts, fallback: 40...80),
                    fmt: { "\(Int($0.rounded()))" }
                )
                metricChart(
                    title: "Respiratory rate", unit: "rpm",
                    accessibilityTitle: String(localized: "Respiratory rate"),
                    metricKey: "resp_rate",
                    points: respPts,
                    gradient: gradient(StrandPalette.metricCyan),
                    tip: StrandPalette.metricCyan,
                    tint: StrandPalette.chargeColor,
                    higherIsBetter: nil,
                    range: valueRange(respPts, fallback: 10...22, pad: 0.18),
                    fmt: { String(format: "%.1f", $0) }
                )
                metricChart(
                    title: "Skin temperature", unit: "°C",
                    accessibilityTitle: String(localized: "Skin temperature"),
                    metricKey: "skin_temp",
                    points: skinPts,
                    gradient: gradient(StrandPalette.metricAmber),
                    tip: StrandPalette.metricAmber,
                    tint: StrandPalette.chargeColor,
                    higherIsBetter: nil,
                    range: valueRange(skinPts, fallback: -2...2, pad: 0.22),
                    fmt: { String(format: "%.1f", $0) }
                )
                metricBarChart(
                    // Plotted points stay on the stored 0–100 scale; only the displayed numbers + unit follow
                    // the Effort-scale toggle, converted inside `fmt`. (#268)
                    title: "Effort", unit: "/ \(UnitFormatter.effortScaleMax(effortScale))",
                    accessibilityTitle: String(localized: "Effort"),
                    metricKey: "strain",
                    points: strainPts,
                    tint: StrandPalette.effortColor,
                    higherIsBetter: nil,
                    range: 0...100,
                    fmt: { UnitFormatter.effortDisplay($0, scale: effortScale) }
                )
                metricBarChart(
                    title: "Rest", unit: "%",
                    accessibilityTitle: String(localized: "Rest"),
                    metricKey: "sleep_performance",
                    points: restPts,
                    tint: StrandPalette.restColor,
                    higherIsBetter: true,
                    range: 0...100,
                    fmt: { "\(Int($0.rounded()))" }
                )
                metricBarChart(
                    title: "Sleep debt", unit: "min",
                    accessibilityTitle: String(localized: "Sleep debt"),
                    metricKey: "sleep_debt_min",
                    points: debtPts,
                    tint: StrandPalette.statusWarning,
                    higherIsBetter: false,
                    range: valueRange(debtPts, fallback: 0...120),
                    fmt: { "\(Int($0.rounded()))" }
                )
            }
        }
    }

    @ViewBuilder
    private func metricChart(
        title: LocalizedStringKey, unit: String,
        // Plain-string series name for VoiceOver (the `title` is a LocalizedStringKey and can't be
        // re-read as a String); supplied by callers so the line announces e.g. "HRV trend".
        accessibilityTitle: String,
        // MetricCatalog key this small-multiple taps through to (its full MetricDetailView).
        metricKey: String,
        points pts: [TrendPoint],
        subtitle: String? = nil,
        gradient: Gradient,
        tip: Color,
        tint: Color,
        higherIsBetter: Bool?,
        range: ClosedRange<Double>,
        fmt: @escaping (Double) -> String
    ) -> some View {
        let avg = mean(pts)
        let card = ChartCard(
            title: title,
            subtitle: subtitle,
            trailing: avg.map(fmt),
            height: NoopMetrics.chartHeight,
            tint: tint,
            chart: {
                if pts.count >= 2 {
                    glowChart(points: pts, gradient: gradient, valueRange: range,
                              tip: tip, valueFormat: { "\(fmt($0)) \(unit)" },
                              accessibilityLabel: String(localized: "\(accessibilityTitle) trend"))
                } else {
                    sparsePlaceholder
                }
            },
            footer: {
                HStack {
                    trendStatsFooter(pts, avg: avg, unit: unit, higherIsBetter: higherIsBetter, fmt: fmt)
                    changeChip(pts, higherIsBetter: higherIsBetter, fmt: fmt)
                }
            }
        )
        // Each small-multiple taps through to its own metric detail (like Today's cards / Explore's rows),
        // with the liquid press settle. The chart itself is left uncluttered — no vessel over it (task).
        NavigationLink { metricDetail(metricKey) } label: { card }
            .buttonStyle(LiquidPressStyle())
            .accessibilityHint(Text(String(localized: "Opens the full \(accessibilityTitle) metric.")))
    }

    @ViewBuilder
    private func metricBarChart(
        title: LocalizedStringKey, unit: String,
        accessibilityTitle: String,
        metricKey: String,
        points pts: [TrendPoint],
        tint: Color,
        higherIsBetter: Bool?,
        range: ClosedRange<Double>,
        fmt: @escaping (Double) -> String
    ) -> some View {
        let avg = mean(pts)
        let card = ChartCard(
            title: title,
            trailing: avg.map(fmt),
            height: NoopMetrics.chartHeight,
            tint: tint,
            chart: {
                if pts.count >= 2 {
                    RoundedBarTrendChart(points: pts, valueRange: range, tint: tint,
                                         valueFormat: { "\(fmt($0)) \(unit)" },
                                         accessibilityLabel: String(localized: "\(accessibilityTitle) trend"))
                } else {
                    sparsePlaceholder
                }
            },
            footer: {
                HStack {
                    trendStatsFooter(pts, avg: avg, unit: unit, higherIsBetter: higherIsBetter, fmt: fmt)
                    changeChip(pts, higherIsBetter: higherIsBetter, fmt: fmt)
                }
            }
        )
        NavigationLink { metricDetail(metricKey) } label: { card }
            .buttonStyle(LiquidPressStyle())
            .accessibilityHint(Text(String(localized: "Opens the full \(accessibilityTitle) metric.")))
    }

    private func trendStatsFooter(
        _ pts: [TrendPoint],
        avg: Double?,
        unit: String,
        higherIsBetter: Bool?,
        fmt: @escaping (Double) -> String
    ) -> ChartFooter {
        let values = pts.map(\.value)
        let low = values.min()
        let high = values.max()
        let best: Double?
        let worst: Double?
        let bestLabel: LocalizedStringKey
        let worstLabel: LocalizedStringKey
        switch higherIsBetter {
        case .some(true):
            best = high
            worst = low
            bestLabel = "Best"
            worstLabel = "Worst"
        case .some(false):
            best = low
            worst = high
            bestLabel = "Best"
            worstLabel = "Worst"
        case .none:
            best = high
            worst = low
            bestLabel = "High"
            worstLabel = "Low"
        }

        return ChartFooter([
            ("Avg", avg.map { formattedStat($0, unit: unit, fmt: fmt) } ?? "—"),
            (bestLabel, best.map { formattedStat($0, unit: unit, fmt: fmt) } ?? "—"),
            (worstLabel, worst.map { formattedStat($0, unit: unit, fmt: fmt) } ?? "—"),
        ])
    }

    private func formattedStat(_ value: Double, unit: String, fmt: (Double) -> String) -> String {
        let number = fmt(value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    // MARK: Year heat-strip

    private var yearStrip: some View {
        // Always show at least a full year for context; expand to all history on ALL.
        let stripDays = max(range.days ?? repo.days.count, 365)
        let recent = repo.days.suffix(stripDays)
        let recoveryDays: [RecoveryDay] = recent.compactMap { d in
            guard let dt = date(d.day) else { return nil }
            return RecoveryDay(date: dt, score: d.recovery)
        }
        let title = (range == .all && repo.days.count > 365) ? String(localized: "Charge (all history)") : String(localized: "Charge (past year)")
        return NoopCard(tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                SectionHeader("\(title)", overline: "Calendar", trailing: String(localized: "\(recoveryDays.filter { $0.score != nil }.count) days"))
                if recoveryDays.isEmpty {
                    sparsePlaceholder.frame(height: 120)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        YearHeatStrip(days: recoveryDays).padding(.vertical, NoopMetrics.space1 / 2)
                    }
                    Divider().overlay(StrandPalette.hairline)
                    legend
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: NoopMetrics.space2) {
            Text("Depleted").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            LinearGradient(gradient: StrandPalette.recoveryGradient, startPoint: .leading, endPoint: .trailing)
                .frame(width: 120, height: 8)
                .clipShape(Capsule())
            Text("Peaked").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Spacer()
        }
    }

    // MARK: Shared bits

    /// Single-color gradient (for metric lines that aren't a value ramp).
    private func gradient(_ color: Color) -> Gradient {
        Gradient(stops: [
            .init(color: color.opacity(0.55), location: 0.0),
            .init(color: color, location: 1.0),
        ])
    }

    /// A domain-tinted `TrendChart` with a crisp flat line and a bright end-cap dot at the latest
    /// point. WHOOP-flat: no underglow blur layer — the single crisp line carries the data and the
    /// fill contrast does the rest. The "now" end-cap is a small dot pinned to the final sample.
    /// Pure presentation: it forwards every value to the locked `TrendChart` unchanged.
    @ViewBuilder
    private func glowChart(points pts: [TrendPoint], gradient: Gradient, valueRange: ClosedRange<Double>,
                           tip: Color, valueFormat: @escaping (Double) -> String,
                           accessibilityLabel: String) -> some View {
        // One crisp, interactive line + area — flat, no blurred glow copy underneath (WHOOP language).
        // The "now" end-cap is drawn INSIDE this chart (nowCapColor) so it's mapped by the chart's own
        // scales and lands on the line — the previous sibling overlay guessed the plot insets and
        // floated the dot left/below the curve (#458).
        TrendChart(points: pts, gradient: gradient, valueRange: valueRange,
                   showsArea: true, height: NoopMetrics.chartHeight, valueFormat: valueFormat,
                   accessibilityLabel: accessibilityLabel, nowCapColor: tip)
    }

    private var sparsePlaceholder: some View {
        Text("Not enough data for this window.")
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct RoundedBarTrendChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    let points: [TrendPoint]
    let valueRange: ClosedRange<Double>
    let tint: Color
    let valueFormat: (Double) -> String
    let accessibilityLabel: String

    var body: some View {
        GeometryReader { proxy in
            let plotHeight = max(1, proxy.size.height)
            let span = max(1, valueRange.upperBound - valueRange.lowerBound)
            let spacing = spacing(for: points.count)
            let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.42)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(points.enumerated()), id: \.element.date) { idx, point in
                    let normalized = min(1, max(0, (point.value - valueRange.lowerBound) / span))
                    let height = max(3, plotHeight * normalized)
                    let opacity = barOpacity(index: idx, total: points.count)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint.opacity(opacity))
                        .frame(maxWidth: .infinity,
                               maxHeight: appeared || reduceMotion ? height : 3,
                               alignment: .bottom)
                        .accessibilityLabel(Text(accessibilityLabel))
                        .accessibilityValue(Text(valueFormat(point.value)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .padding(.top, 2)
            .animation(animation, value: appeared)
        }
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
    }

    private func spacing(for count: Int) -> CGFloat {
        switch count {
        case 0...14: return 5
        case 15...45: return 3
        case 46...120: return 2
        default: return 1
        }
    }

    private func barOpacity(index: Int, total: Int) -> Double {
        guard total > 1 else { return 1 }
        let progress = Double(index) / Double(total - 1)
        return 0.35 + progress * 0.65
    }
}

private struct SleepDebtDetailView: View {
    let history: [SleepDebtHistoryPoint]

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var plotted: [TrendPoint] {
        history.compactMap { point in
            guard let debt = point.carriedDebtMinutes, let date = Self.parser.date(from: point.day) else { return nil }
            return TrendPoint(date: date, value: debt)
        }
    }
    private var latest: SleepDebtHistoryPoint? { history.last { $0.carriedDebtMinutes != nil } }
    private var recentPlotted: [TrendPoint] { Array(plotted.suffix(30)) }
    private var chartUpperBound: Double {
        let values = recentPlotted.map(\.value).sorted()
        guard values.count >= 5 else { return max(60, values.last ?? 60) }
        let p90 = values[Int((Double(values.count - 1) * 0.90).rounded(.down))]
        return max(60, p90 * 1.15)
    }
    private var chartPoints: [TrendPoint] {
        recentPlotted.map { TrendPoint(date: $0.date, value: min($0.value, chartUpperBound)) }
    }
    private var chartClipsOutlier: Bool {
        recentPlotted.contains { $0.value > chartUpperBound }
    }

    var body: some View {
        ScreenScaffold(title: "Sleep Debt", subtitle: "A NOOP estimate from your sleep history.", lazy: true) {
            if let latest {
                NoopCard(tint: StrandPalette.statusWarning) {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("CURRENT ESTIMATE").strandOverline()
                        Text(duration(latest.carriedDebtMinutes ?? 0))
                            .font(StrandFont.display(48)).foregroundStyle(StrandPalette.textPrimary)
                        Text("Surplus sleep repays carried debt gradually. Only the amount added to one night's recommendation is capped. This is an estimate, not a diagnosis or a proprietary WHOOP value.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        Text("Confidence: \(confidence(latest.breakdown.confidence))")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                if plotted.count >= 2 {
                    ChartCard(title: "Recent carried debt", trailing: duration(latest.carriedDebtMinutes ?? 0),
                              height: NoopMetrics.chartHeight, tint: StrandPalette.statusWarning,
                              chart: {
                        RoundedBarTrendChart(points: chartPoints, valueRange: 0...chartUpperBound,
                            tint: StrandPalette.statusWarning, valueFormat: duration,
                            accessibilityLabel: String(localized: "Carried sleep debt"))
                    }, footer: {
                        if chartClipsOutlier {
                            Text("The chart scale limits isolated outliers; exact debt values are shown above and below.")
                                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        }
                    })
                }
                recentChanges
            } else {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text("Sleep history needed").font(StrandFont.headline)
                        Text("Record at least one completed main sleep. Missing nights stay missing and are never treated as zero sleep.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
    }

    private var recentChanges: some View {
        let changes = history.filter {
            ($0.nightlyDeficitMinutes ?? 0) > 0 || ($0.repaymentMinutes ?? 0) > 0 || $0.breakdown.napCreditMinutes > 0
        }.suffix(10).reversed()
        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("What changed it", overline: "Recent nights")
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(changes), id: \.day) { point in
                        HStack(spacing: NoopMetrics.space3) {
                            Text(point.day).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                if let deficit = point.nightlyDeficitMinutes, deficit > 0 {
                                    Text("Added \(duration(deficit))")
                                } else if let repayment = point.repaymentMinutes, repayment > 0 {
                                    Text("Repaid \(duration(repayment))")
                                } else {
                                    Text("Nap reduced tonight's need by \(duration(point.breakdown.napCreditMinutes))")
                                }
                            }.font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            Text(point.carriedDebtMinutes.map(duration) ?? "—")
                                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        }.padding(NoopMetrics.cardInnerPadding)
                        if point.day != changes.last?.day { Divider().overlay(StrandPalette.hairline) }
                    }
                }
            }
        }
    }

    private func duration(_ minutes: Double) -> String {
        let rounded = max(0, Int(minutes.rounded()))
        return rounded >= 60 ? "\(rounded / 60)h \(rounded % 60)m" : "\(rounded)m"
    }
    private func confidence(_ value: SleepNeedConfidence) -> String {
        switch value { case .fallback: return String(localized: "Fallback"); case .limited: return String(localized: "Limited"); case .established: return String(localized: "Established") }
    }
}

#if DEBUG
@MainActor
private func previewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    let cal = Calendar(identifier: .gregorian)
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = TimeZone(identifier: "UTC")
    fmt.dateFormat = "yyyy-MM-dd"
    let today = Date()
    var seeded: [DailyMetric] = []
    let span = 365 * 3
    for i in stride(from: span - 1, through: 0, by: -1) {
        guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
        let phase = Double(span - 1 - i)
        let rec = 55 + 28 * sin(phase / 11.0) + Double((Int(phase) * 31) % 17) - 8
        let hrv = 58 + 16 * sin(phase / 9.0) + Double((Int(phase) * 13) % 11) - 5
        let rhr = 52 + 4 * sin(phase / 7.0) + Double((Int(phase) * 7) % 5) - 2
        let strain = 9 + 6 * sin(phase / 5.0 + 1.2) + Double((Int(phase) * 5) % 4) - 2
        let gap = Int(phase) % 23 == 0
        seeded.append(DailyMetric(
            day: fmt.string(from: d),
            totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 110, lightMin: 200,
            disturbances: 6, restingHr: gap ? nil : Int(rhr.rounded()),
            avgHrv: gap ? nil : max(15, hrv), recovery: gap ? nil : max(2, min(99, rec)),
            strain: gap ? nil : max(0, min(21, strain)), exerciseCount: 1
        ))
    }
    repo.days = seeded
    repo.loaded = true
    return repo
}

#Preview("Trends") {
    TrendsView()
        .environmentObject(previewRepo())
        .environmentObject(LiveState())
        .frame(width: 960, height: 960)
        .preferredColorScheme(.dark)
}
#endif
