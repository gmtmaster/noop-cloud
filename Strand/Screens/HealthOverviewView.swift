import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandImport
import WhoopStore

/// Root of the Health tab. It composes previews from the same live-HR, Healthspan and vital-range
/// sources as their full screens; it owns no thresholds, subscriptions or age calculations.
struct HealthOverviewView: View {
    var body: some View {
        ScreenScaffold(title: "Health", subtitle: "Your current health and long-term trajectory",
                       onRefresh: { await refresh() }, lazy: true) {
            NavigationLink { HealthspanView() } label: { HealthspanPreviewCard() }
                .buttonStyle(.plain)
            NavigationLink { LabBookView() } label: { AdvancedLabsPreviewCard() }
                .buttonStyle(.plain)
            NavigationLink { HealthView() } label: { HealthMonitorPreviewCard() }
                .buttonStyle(.plain)
        }
    }

    @EnvironmentObject private var repo: Repository
    private func refresh() async { await repo.refresh() }
}

// MARK: - Advanced Labs

/// The landing-card contract is deliberately classification-agnostic. Lab Book currently stores
/// user-entered values and the report's reference range verbatim; it does not ship medical ranges.
/// A future lab-domain classifier can populate these three counts without changing this view or ring.
private struct AdvancedLabsSummary: Equatable {
    static let capacity = 65

    var recordedCount: Int
    var optimalCount: Int
    var sufficientCount: Int
    var outOfRangeCount: Int
    var unclassifiedCount: Int
    var lastUpdated: Date?

    static let empty = AdvancedLabsSummary(recordedCount: 0, optimalCount: 0,
                                           sufficientCount: 0, outOfRangeCount: 0, unclassifiedCount: 0,
                                           lastUpdated: nil)
}

private struct AdvancedLabsPreviewCard: View {
    @EnvironmentObject private var repo: Repository
    @State private var summary = AdvancedLabsSummary.empty

    var body: some View {
        SolidHealthMonitorCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("ADVANCED LABS").strandOverline()
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(StrandPalette.textTertiary)
                }

                HStack(alignment: .center, spacing: 12) {
                    statusColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    ring
                        .frame(minWidth: 132, idealWidth: 164, maxWidth: 178,
                               minHeight: 132, idealHeight: 164, maxHeight: 178)
                }

                if summary.recordedCount == 0 {
                    HStack(spacing: 7) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(StrandPalette.metricCyan)
                        Text("No labs added yet")
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                        Spacer()
                        Text("Add results")
                            .font(StrandFont.footnote.weight(.semibold))
                            .foregroundStyle(StrandPalette.metricCyan)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens Advanced Labs")
        .task(id: repo.refreshSeq) { await load() }
    }

    private var ring: some View {
        AdvancedLabsBiomarkerRing(totalCapacity: AdvancedLabsSummary.capacity,
                                   recordedCount: summary.recordedCount,
                                   optimalCount: summary.optimalCount,
                                   sufficientCount: summary.sufficientCount,
                                   outOfRangeCount: summary.outOfRangeCount)
    }

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 11) {
            statusRow("Optimal", symbol: "checkmark", count: summary.optimalCount,
                      color: StrandPalette.statusPositive)
            statusRow("Sufficient", symbol: "circle.fill", count: summary.sufficientCount,
                      color: StrandPalette.metricCyan)
            statusRow("Out of Range", symbol: "exclamationmark", count: summary.outOfRangeCount,
                      color: StrandPalette.statusWarning)
            if summary.unclassifiedCount > 0 {
                HStack(spacing: 6) {
                    Circle().fill(StrandPalette.textTertiary.opacity(0.5)).frame(width: 6, height: 6)
                    Text("\(summary.unclassifiedCount) unclassified")
                }.font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
            Text(lastUpdatedLabel)
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                .padding(.top, 3)
                .lineLimit(2)
        }
    }

    private func statusRow(_ title: LocalizedStringKey, symbol: String, count: Int, color: Color) -> some View {
        HStack(spacing: 9) {
            Label(title, systemImage: symbol)
                .font(StrandFont.footnote.weight(.semibold)).foregroundStyle(color)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Text("\(count)").font(StrandFont.number(20)).foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private var lastUpdatedLabel: String {
        guard let date = summary.lastUpdated else { return String(localized: "Last updated: No results yet") }
        return String(localized: "Last updated: \(date.formatted(date: .abbreviated, time: .omitted))")
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        var rows: [LabMarkerRow] = []
        for category in LabMarkerCategory.allCases {
            rows += (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? []
        }
        guard !Task.isCancelled else { return }
        let results = rows.map {
            BiomarkerRecordedResult(markerKey: $0.markerKey, value: $0.value, unit: $0.unit,
                                    reportRangeText: $0.referenceText,
                                    timestamp: Date(timeIntervalSince1970: TimeInterval($0.takenAt)))
        }
        let classified = AdvancedLabsClassificationSummary.build(results: results)
        summary = AdvancedLabsSummary(
            recordedCount: min(classified.recordedCount, AdvancedLabsSummary.capacity),
            optimalCount: classified.optimalCount, sufficientCount: classified.sufficientCount,
            outOfRangeCount: classified.outOfRangeCount,
            unclassifiedCount: classified.unclassifiedCount,
            lastUpdated: rows.map(\.takenAt).max().map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

/// Reusable 65-position gummy ring. Classified positions are coloured; recorded-but-unclassified
/// positions use a lighter neutral gel so the UI never implies a medical judgement.
struct AdvancedLabsBiomarkerRing: View {
    let totalCapacity: Int
    let recordedCount: Int
    let optimalCount: Int
    let sufficientCount: Int
    let outOfRangeCount: Int

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let segmentWidth = max(3.2, side * 0.027)
            let segmentHeight = max(11, side * 0.105)
            let radius = (side - segmentHeight) / 2
            ZStack {
                ForEach(0..<max(totalCapacity, 1), id: \.self) { index in
                    gummySegment(index: index, width: segmentWidth, height: segmentHeight)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(Double(index) / Double(max(totalCapacity, 1)) * 360 - 90))
                }
                VStack(spacing: 5) {
                    Text("\(min(recordedCount, totalCapacity))/\(totalCapacity)")
                        .font(StrandFont.number(side * 0.22)).foregroundStyle(StrandPalette.textPrimary)
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text("BIOMARKERS").strandOverline().foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(recordedCount) of \(totalCapacity) biomarkers recorded")
    }

    private func gummySegment(index: Int, width: CGFloat, height: CGFloat) -> some View {
        let color = segmentColor(index)
        return Capsule(style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.98), color.opacity(0.52)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Capsule(style: .continuous)
                .stroke(Color.white.opacity(index < classifiedCount ? 0.16 : 0.035), lineWidth: 0.7))
            .shadow(color: color.opacity(index < classifiedCount ? 0.24 : 0.08), radius: 3, y: 1)
            .frame(width: width, height: height)
    }

    private var classifiedCount: Int {
        min(totalCapacity, max(0, optimalCount) + max(0, sufficientCount) + max(0, outOfRangeCount))
    }

    private func segmentColor(_ index: Int) -> Color {
        if index < max(0, optimalCount) { return StrandPalette.statusPositive }
        if index < max(0, optimalCount) + max(0, sufficientCount) { return StrandPalette.metricCyan }
        if index < classifiedCount { return StrandPalette.statusWarning }
        if index < min(recordedCount, totalCapacity) { return StrandPalette.textSecondary.opacity(0.72) }
        return StrandPalette.textTertiary.opacity(0.18)
    }
}

private struct HealthspanPreviewCard: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var summary: HealthspanResultSummary?
    @State private var days: [HealthspanDay] = []

    private var result: NoopAgeWeekResult? { summary?.result }
    private var previous: NoopAgeWeekResult? { summary?.previous }
    private var chronologicalAge: Double { summary?.chronologicalAge ?? Double(profile.age) }
    private var hasResult: Bool { result?.noopAge != nil }
    private var snapshotIdentity: HealthspanSnapshotIdentity {
        HealthspanSnapshotIdentity(repo: repo, profile: profile)
    }

    var body: some View {
        SolidHealthMonitorCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("HEALTHSPAN").strandOverline()
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(StrandPalette.textTertiary)
                        }
                        Text("PACE OF AGING").strandOverline()
                        if let pace = result?.paceOfAging {
                            Text(HealthspanPacePresentation.value(pace))
                                .font(StrandFont.number(32)).foregroundStyle(StrandPalette.textPrimary)
                            Text(paceTrend(pace)).font(StrandFont.footnote.weight(.semibold))
                                .foregroundStyle(pace <= 1 ? StrandPalette.statusPositive : StrandPalette.statusWarning)
                        } else {
                            Text("Data is building up").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                            Text(calibrationDetail).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)

                    NoopAgeOrb(age: result?.noopAge ?? chronologicalAge,
                               chronologicalAge: chronologicalAge,
                               confidence: result?.confidence ?? .calibrating,
                               neutralPreview: !hasResult,
                               labelMode: hasResult ? .ageOnly : .hidden)
                        .frame(width: 142, height: 142)
                        .accessibilityHidden(true)
                }
                if let delta = summary?.ageDifference {
                    HStack(spacing: 6) {
                        Text(String(format: "%.1f years %@", abs(delta), delta >= 0 ? "younger" : "older"))
                            .foregroundStyle(delta >= 0 ? StrandPalette.statusPositive : StrandPalette.statusWarning)
                        Text("vs. actual age").foregroundStyle(StrandPalette.textTertiary)
                    }.font(StrandFont.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Healthspan")
        .task(id: snapshotIdentity) { await load(identity: snapshotIdentity) }
    }

    private func load(identity: HealthspanSnapshotIdentity) async {
        let snapshot = await repo.noopAgeSnapshot(profile: profile)
        guard !Task.isCancelled, identity == snapshotIdentity else { return }
        days = snapshot.observations
        summary = HealthspanResultSummary.current(snapshot: snapshot, profile: profile)
    }

    private func paceTrend(_ pace: Double) -> String {
        guard let old = previous?.paceOfAging else { return pace < 1 ? "Slower aging trajectory" : pace > 1 ? "Faster aging trajectory" : "Stable trajectory" }
        let delta = pace - old
        if abs(delta) < 0.02 { return "Stable vs. last week" }
        return delta < 0 ? "Slower vs. last week" : "Faster vs. last week"
    }

    private var calibrationDetail: String {
        let cutoff = result?.weekEndDay ?? HealthspanWeekCutoff.latestCompletedWeekEnd(now: Date(), calendar: .current)
        return HealthspanPacePresentation.calibrationDetail(NoopAgeEngine.paceEligibility(days: days, cutoff: cutoff))
    }
}

private struct HealthMonitorPreviewCard: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric,
                                     override: temperatureRaw)
    }

    var body: some View {
        let readings = BodyVitalSigns.readings(sourceRows: repo.vitalMetricRows, temperatureUnit: temperatureUnit)
        let available = readings.filter { $0.value != nil && $0.typicalRangePosition != nil }
        let within = available.filter { $0.typicalRangePosition == .within }.count
        let outside = available.count - within
        SolidHealthMonitorCard(padding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("HEALTH MONITOR").strandOverline()
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(StrandPalette.textTertiary)
                }
                HStack(spacing: 0) {
                    ForEach(readings) { reading in vital(reading) }
                }
                HStack(spacing: 9) {
                    Image(systemName: outside > 0 ? "exclamationmark" : available.isEmpty ? "minus" : "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(outside > 0 ? StrandPalette.statusWarning : available.isEmpty ? StrandPalette.textTertiary : StrandPalette.statusPositive)
                    Text(summary(available: available.count, within: within, outside: outside))
                        .font(StrandFont.footnote.weight(.semibold)).foregroundStyle(StrandPalette.textSecondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Opens Health Monitor")
    }

    private func vital(_ reading: BodyVitalReading) -> some View {
        let position = reading.typicalRangePosition
        let color: Color = position == .within ? StrandPalette.statusPositive
            : position == nil ? StrandPalette.textTertiary : StrandPalette.statusWarning
        let status = position == .within ? "within range" : position == nil ? "unavailable" : "outside range"
        return VStack(spacing: 7) {
            Image(systemName: symbol(reading.key)).font(.system(size: 18)).foregroundStyle(StrandPalette.textTertiary)
            Text(abbreviation(reading.key)).strandOverline()
            Image(systemName: position == .within ? "checkmark.square.fill" : position == nil ? "minus.square" : "exclamationmark.square.fill")
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.label), \(status)")
    }

    private func summary(available: Int, within: Int, outside: Int) -> String {
        if available == 0 { return "No metrics with a typical range yet" }
        if outside > 0 { return "\(outside) \(outside == 1 ? "metric needs" : "metrics need") attention" }
        return "\(within)/\(available) metrics within range"
    }
    private func abbreviation(_ key: String) -> String { ["resp":"RESP", "spo2":"SpO₂", "rhr":"RHR", "hrv":"HRV", "skin":"TEMP"][key] ?? key.uppercased() }
    private func symbol(_ key: String) -> String { ["resp":"lungs.fill", "spo2":"drop.fill", "rhr":"heart.fill", "hrv":"waveform.path.ecg", "skin":"thermometer.medium"][key] ?? "waveform" }
}

// MARK: - Preview

#if DEBUG
#Preview("Health Overview") {
    // Match the app-owned preview setup used by Settings and other screens. AppModel supplies the
    // canonical Repository/device identity plus the corresponding ProfileStore and LiveState.
    let model = AppModel()
    model.repo.days = [
        DailyMetric(
            day: Repository.dayString(Date()),
            totalSleepMin: 462, efficiency: 92,
            deepMin: 96, remMin: 108, lightMin: 240, disturbances: 7,
            restingHr: 52, avgHrv: 74, recovery: 81, strain: 11.4,
            exerciseCount: 1,
            spo2Pct: 97, skinTempDevC: 34.2, respRateBpm: 14.6
        )
    ]
    model.repo.loaded = true
    model.live.connected = true
    model.live.bonded = true
    model.live.heartRate = 107

    return NavigationStack {
        HealthOverviewView()
    }
    .environmentObject(model)
    .environmentObject(model.repo)
    .environmentObject(model.live)
    .environmentObject(model.profile)
    .environmentObject(NavRouter())
    .frame(width: 402, height: 900)
    .preferredColorScheme(.dark)
}
#endif
