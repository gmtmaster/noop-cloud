import SwiftUI
import StrandAnalytics
import StrandDesign

enum HealthspanAnimationPolicy {
    static func animates(reduceMotion: Bool, sceneIsActive: Bool) -> Bool {
        !reduceMotion && sceneIsActive
    }
}

/// Pure motion math shared by Canvas and tests. Seeds stay fixed; elapsed time changes only phase,
/// so a refresh never reshuffles the field and a static accessibility rendering is always identical.
enum HealthspanOrbMotion {
    struct ParticleState: Equatable {
        let xDrift: Double
        let yDrift: Double
        let depth: Double
    }

    static func shellScale(at elapsed: TimeInterval) -> Double {
        // Keep the breathing amplitude restrained, but make the inhale/exhale cadence more present.
        1 + 0.012 * sin(elapsed * 1.16)
    }

    static func shellPhase(at elapsed: TimeInterval) -> Double {
        sin(elapsed * 0.36)
    }

    static func particle(index: Int, elapsed: TimeInterval) -> ParticleState {
        let seed = Double(index) + 1
        let speed = particleAngularSpeed(index: index)
        let phase = elapsed * speed
        return ParticleState(
            xDrift: 0.080 * sin(phase + seed),
            yDrift: 0.072 * sin(phase * 0.73 + seed * 0.71),
            depth: 0.15 * sin(phase * 0.51 + seed * 1.37)
        )
    }

    static func particleAngularSpeed(index: Int) -> Double {
        let seed = Double(index) + 1
        // Seeded depth matches the Canvas' base-depth field. Back particles move at roughly 1.7× the
        // former rate; foreground particles reach about 2.2×, producing parallax without more frames
        // or particles. The seed is stable, so view updates never restart or reshuffle motion.
        let depth = unit(seed * 12.9898) * 2 - 1
        let foregroundBoost = max(0, depth) * 0.15
        return 0.41 + unit(seed * 3.1) * 0.14 + foregroundBoost
    }

    static func unit(_ value: Double) -> Double {
        let raw = sin(value) * 43_758.5453
        return raw - floor(raw)
    }
}

/// One canonical local-coordinate model for every orb layer. Lighting may be asymmetric, geometry may not.
struct HealthspanOrbGeometry: Equatable {
    static let baseRadiusFactor: CGFloat = 0.455
    static let coreRadiusFactor: CGFloat = 0.60
    static let particleRadiusFactor: CGFloat = 0.95
    static let glowRadiusFactor: CGFloat = 1.01

    let bounds: CGRect
    let center: CGPoint
    let baseRadius: CGFloat

    init(size: CGSize) {
        bounds = CGRect(origin: .zero, size: size)
        center = CGPoint(x: bounds.midX, y: bounds.midY)
        baseRadius = min(bounds.width, bounds.height) * Self.baseRadiusFactor
    }

    func shellRadius(scale: Double) -> CGFloat { baseRadius * CGFloat(scale) }
    func coreRadius(scale: Double) -> CGFloat { shellRadius(scale: scale) * Self.coreRadiusFactor }
    func particleRadius(scale: Double) -> CGFloat { shellRadius(scale: scale) * Self.particleRadiusFactor }
    func glowRadius(scale: Double) -> CGFloat { shellRadius(scale: scale) * Self.glowRadiusFactor }

    func circle(radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    func project(normalizedX: Double, normalizedY: Double, scale: Double) -> CGPoint {
        let radius = particleRadius(scale: scale)
        return CGPoint(x: center.x + CGFloat(normalizedX) * radius,
                       y: center.y + CGFloat(normalizedY) * radius)
    }

    func containsAllLayers(scale: Double) -> Bool {
        bounds.contains(circle(radius: glowRadius(scale: scale)))
    }
}

/// Presentation-only mapping for the contributor scale. The engine's signed year adjustment remains the
/// sole source of truth; the cap only prevents one large value from making every other marker unreadable.
enum HealthspanContributorScale {
    static let visualCapYears = 2.0

    static func sorted(_ contributors: [NoopAgeContributor]) -> [NoopAgeContributor] {
        contributors.sorted {
            sortsBefore(lhsLabel: $0.label, lhsAdjustment: $0.recentAdjustmentYears ?? $0.adjustmentYears,
                        rhsLabel: $1.label, rhsAdjustment: $1.recentAdjustmentYears ?? $1.adjustmentYears)
        }
    }

    static func sortsBefore(lhsLabel: String, lhsAdjustment: Double,
                            rhsLabel: String, rhsAdjustment: Double) -> Bool {
        if abs(lhsAdjustment) == abs(rhsAdjustment) { return lhsLabel < rhsLabel }
        return abs(lhsAdjustment) > abs(rhsAdjustment)
    }

    /// -1 is the helping edge, 0 is neutral, and +1 is the holding-back edge.
    static func position(for adjustmentYears: Double) -> Double {
        max(-1, min(1, adjustmentYears / visualCapYears))
    }

    static func effect(for adjustmentYears: Double) -> String {
        switch abs(adjustmentYears) {
        case ..<0.1: return "Neutral"
        case ..<0.35: return "Slight"
        case ..<0.8: return "Moderate"
        default: return "Strong"
        }
    }
}

struct HealthspanView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var history: [NoopAgeWeekResult] = []
    @State private var healthspanDays: [HealthspanDay] = []
    @State private var selectedIndex = 0
    @State private var showsAllContributors = false
    @State private var expandedContributor: String?

    private var selected: NoopAgeWeekResult? { history.indices.contains(selectedIndex) ? history[selectedIndex] : nil }
    private var snapshotIdentity: HealthspanSnapshotIdentity {
        HealthspanSnapshotIdentity(repo: repo, profile: profile)
    }

    var body: some View {
        ScreenScaffold(title: "Healthspan", subtitle: "Your long-term fitness and health trajectory.",
                       onRefresh: { await load() }, lazy: true) {
            if !profile.ageIsExplicit && profile.birthDate == nil {
                missingAge
            } else if let result = selected, let age = result.noopAge {
                weekNavigation(result.weekEndDay)
                healthspanHero(result, age: age)
                interpretationCard(result)
                paceSection(result)
                contributorBreakdown(result)
                modelNote
            } else if let result = selected {
                weekNavigation(result.weekEndDay)
                calibratingHero(result)
                calibrationContributors(result)
                modelNote
            } else {
                ComingSoon(what: "Noop Age is calibrating. Keep wearing your device through sleep and daily activity so enough reliable coverage can build.", symbol: "heart.circle")
            }
        }
        .task(id: snapshotIdentity) { await load(identity: snapshotIdentity) }
        .onChange(of: selectedIndex) { _, _ in showsAllContributors = false }
    }

    private func healthspanHero(_ result: NoopAgeWeekResult, age: Double) -> some View {
        let summary = HealthspanResultSummary.resolve(result: result, previous: nil, profile: profile)
        let actual = summary.chronologicalAge
        return VStack(spacing: 8) {

               NoopAgeOrb(
                   age: age,
                   chronologicalAge: actual,
                   confidence: result.confidence
               )
               .frame(maxWidth: 360)
               .frame(maxWidth: .infinity)
            }
    }

    private func heroMetric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(StrandFont.number(24)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).strandOverline()
        }.accessibilityElement(children: .combine)
    }

    private func calibratingHero(_ result: NoopAgeWeekResult) -> some View {
        let eligibility = NoopAgeEngine.paceEligibility(days: healthspanDays, cutoff: result.weekEndDay)
        return SolidHealthMonitorCard(padding: 18) {
            VStack(spacing: 10) {
                NoopAgeOrb(age: Double(profile.age), chronologicalAge: Double(profile.age), confidence: .calibrating,
                           neutralPreview: true, labelMode: .hidden)
                    .frame(maxWidth: 340).frame(maxWidth: .infinity)
                Text("Building your Healthspan baseline").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                Text(HealthspanPacePresentation.calibrationDetail(eligibility))
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary).multilineTextAlignment(.center)
            }
        }
    }

    private func interpretationCard(_ result: NoopAgeWeekResult) -> some View {
        let ranked = HealthspanAttribution.ranked(result: result, chronologicalAge: chronologicalAge(for: result.weekEndDay))
        return SolidHealthMonitorCard(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(HealthspanAttribution.headline(result: result)).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(HealthspanAttribution.interpretation(ranked: ranked, confidence: result.confidence))
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                if result.confidence != .established {
                    Text("These estimates will become more reliable as additional valid days are collected.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private var missingAge: some View {
        NoopCard(tint: StrandPalette.statusWarning) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Add your age", systemImage: "person.crop.circle.badge.questionmark")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text("Noop Age starts from chronological age. NOOP will not guess it.")
                    .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                NavigationLink("Open Profile") { SettingsView() }
                    .foregroundStyle(StrandPalette.accent)
            }
        }
    }

    private func weekNavigation(_ day: String) -> some View {
        HStack {
            Button { selectedIndex = max(0, selectedIndex - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(selectedIndex == 0)
            Spacer()
            Text(weekLabel(day)).strandOverline()
            Spacer()
            Button { selectedIndex = min(history.count - 1, selectedIndex + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(selectedIndex >= history.count - 1)
        }
        .foregroundStyle(StrandPalette.textSecondary)
        .accessibilityElement(children: .contain)
    }

    private func paceSection(_ result: NoopAgeWeekResult) -> some View {
        let eligibility = NoopAgeEngine.paceEligibility(days: healthspanDays, cutoff: result.weekEndDay)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Pace of Aging", overline: "Recent 30 days vs. long-term")
            NoopCard(tint: paceColor(result.paceOfAging)) {
                VStack(spacing: 12) {
                    Text(HealthspanPacePresentation.value(result.paceOfAging))
                        .font(StrandFont.display(42)).foregroundStyle(StrandPalette.textPrimary)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(StrandPalette.surfaceInset).frame(height: 6)
                            Rectangle().fill(StrandPalette.hairlineStrong).frame(width: 1, height: 18)
                                .offset(x: proxy.size.width / 2)
                            if let pace = result.paceOfAging {
                                Circle().fill(paceColor(pace)).frame(width: 14, height: 14)
                                    .offset(x: max(0, min(proxy.size.width - 14,
                                        (pace - NoopAgeEngine.Configuration.minimumPace) /
                                        (NoopAgeEngine.Configuration.maximumPace - NoopAgeEngine.Configuration.minimumPace) * (proxy.size.width - 14))))
                            }
                        }
                    }.frame(height: 18)
                    HStack { Text("Slower"); Spacer(); Text("1.0x stable"); Spacer(); Text("Faster") }
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    if result.paceOfAging == nil {
                        Text("Calibrating Pace of Aging")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        Text(HealthspanPacePresentation.calibrationDetail(eligibility))
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("A projected six-month trajectory from your recent 30 days—not literal biological aging speed.")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    private func contributorBreakdown(_ result: NoopAgeWeekResult) -> some View {
        let actual = chronologicalAge(for: result.weekEndDay)
        let ranked = HealthspanAttribution.ranked(result: result, chronologicalAge: actual)
        let grouped = Dictionary(grouping: ranked.filter { !$0.isCombined }, by: \.domain)
        return VStack(alignment: .leading, spacing: 16) {
            SectionHeader("What Shapes Your Noop Age", overline: "180-day estimated age impact",
                          trailing: result.confidence.rawValue.capitalized)
            Text("Negative values contribute toward a younger Noop Age. Positive values contribute toward an older Noop Age.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            ForEach(HealthspanAttribution.domainOrder.filter { grouped[$0] != nil }, id: \.self) { domain in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(HealthspanAttribution.domainName(domain)).font(StrandFont.headline)
                        Spacer()
                        Text(HealthspanAttribution.years(grouped[domain, default: []].reduce(0) { $0 + $1.impact }))
                            .font(StrandFont.number(16)).foregroundStyle(HealthspanAttribution.color(grouped[domain, default: []].reduce(0) { $0 + $1.impact }))
                    }
                    ForEach(grouped[domain, default: []]) { item in
                        HealthspanContributorCard(item: item, isExpanded: expandedContributor == item.id) {
                            withAnimation(StrandMotion.interactive) { expandedContributor = expandedContributor == item.id ? nil : item.id }
                        }
                    }
                }
            }
            if let combined = ranked.first(where: \.isCombined), abs(combined.impact) >= 0.05 {
                SolidHealthMonitorCard(padding: 16) {
                    HStack { Text("Combined model effects").font(StrandFont.subhead); Spacer(); Text(HealthspanAttribution.years(combined.impact)).font(StrandFont.number(16)).foregroundStyle(HealthspanAttribution.color(combined.impact)) }
                    Text("Confidence weighting, smoothing, domain interaction and safety caps that cannot be assigned honestly to one metric.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Divider().overlay(StrandPalette.hairline)
            HStack {
                Text("Estimated total").font(StrandFont.headline)
                Spacer()
                Text(HealthspanAttribution.years(ranked.reduce(0) { $0 + $1.impact }))
                    .font(StrandFont.number(20)).foregroundStyle(HealthspanAttribution.color(ranked.reduce(0) { $0 + $1.impact }))
            }
        }
    }

    private func calibrationContributors(_ result: NoopAgeWeekResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("What Shapes Your Noop Age", overline: "Calibrating")
            ForEach(["Sleep", "Activity", "Cardiovascular fitness"], id: \.self) { title in
                SolidHealthMonitorCard(padding: 16) {
                    HStack { Text(title).font(StrandFont.headline); Spacer(); Image(systemName: "clock").foregroundStyle(StrandPalette.textTertiary) }
                    Text("Contribution will become available once enough valid days establish this baseline.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private func contributorCard(_ result: NoopAgeWeekResult) -> some View {
        let availability = HealthspanContributorAvailability.resolve(result)
        let sorted = availability == .valid
            ? HealthspanContributorScale.sorted(result.contributors.filter {
                abs($0.recentAdjustmentYears ?? $0.adjustmentYears) >= 0.05
            }) : []
        let visible = showsAllContributors ? sorted : Array(sorted.prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("What Is Moving Your Noop Age", overline: "Recent 30 days vs. long-term",
                          trailing: result.confidence.rawValue.capitalized)
            NoopCard(tint: StrandPalette.chargeColor) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("HELPING").strandOverline().foregroundStyle(StrandPalette.statusPositive)
                        Spacer()
                        Text("HOLDING BACK").strandOverline().foregroundStyle(HealthspanOrbPalette.worsening)
                    }
                    ForEach(visible, id: \.key) { item in
                        ContributorImpactRow(item: item)
                    }
                    if sorted.isEmpty {
                        Text(contributorEmptyText(availability))
                            .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    }
                    if sorted.count > 5 {
                        Button(showsAllContributors ? "Show less" : "Show all") {
                            withAnimation(StrandMotion.interactive) { showsAllContributors.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accent)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func contributorEmptyText(_ availability: HealthspanContributorAvailability) -> String {
        switch availability {
        case .buildingPaceBaseline:
            return "Building your recent-vs-long-term contributor baseline."
        case .insufficientComparableData:
            return "Not enough comparable data to identify trajectory contributors yet."
        case .valid:
            return "No strong contributor stood out for this period."
        }
    }

    private var modelNote: some View {
        Text("Noop Age is a deterministic, WHOOP-inspired functional fitness comparison built from your available data. It is not WHOOP’s formula, a biological age, diagnosis, lifespan estimate, or disease-risk score.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
    }

    private func load(identity: HealthspanSnapshotIdentity? = nil) async {
        let requestedIdentity = identity ?? snapshotIdentity
        let snapshot = await repo.noopAgeSnapshot(profile: profile)
        guard !Task.isCancelled, requestedIdentity == snapshotIdentity else { return }
        healthspanDays = snapshot.observations
        history = snapshot.results
        selectedIndex = HealthspanSelection.newestIndex(count: history.count)
    }
    private func chronologicalAge(for day: String) -> Double? {
        HealthspanResultSummary.chronologicalAge(for: day, profile: profile)
    }
    private func weekLabel(_ day: String) -> String {
        guard let end = Self.parser.date(from: day), let start = Calendar.current.date(byAdding: .day, value: -6, to: end) else { return day }
        return "\(Self.label.string(from: start).uppercased()) – \(Self.label.string(from: end).uppercased())"
    }
    private func paceColor(_ pace: Double?) -> Color {
        guard let pace else { return StrandPalette.textTertiary }
        if pace < 0.95 { return StrandPalette.statusPositive }
        if pace > 1.05 { return StrandPalette.statusWarning }
        return StrandPalette.chargeColor
    }
    private static let parser: DateFormatter = { let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let label: DateFormatter = { let f = DateFormatter(); f.locale = .current; f.setLocalizedDateFormatFromTemplate("MMM d"); return f }()
}

enum HealthspanAttribution {
    struct Item: Identifiable, Equatable {
        let id: String
        let label: String
        let domain: NoopAgeDomain
        let impact: Double
        let paceChange: Double?
        let isCombined: Bool
    }

    static let domainOrder: [NoopAgeDomain] = [.sleep, .fitness, .activity, .body]

    static func ranked(result: NoopAgeWeekResult, chronologicalAge: Double?) -> [Item] {
        let domainCount = max(1, domainOrder.filter { domain in result.ageContributors.contains { $0.domain == domain } }.count)
        let paceByKey = Dictionary(uniqueKeysWithValues: result.contributors.map { ($0.key, $0.recentAdjustmentYears) })
        var items = result.ageContributors.map {
            Item(id: $0.key, label: $0.label, domain: $0.domain,
                 impact: $0.adjustmentYears / Double(domainCount), paceChange: paceByKey[$0.key] ?? nil,
                 isCombined: false)
        }
        // Opportunity first, strongest helping signal second, then remaining absolute impacts.
        items.sort {
            if ($0.impact > 0) != ($1.impact > 0) { return $0.impact > 0 }
            return abs($0.impact) > abs($1.impact)
        }
        if let age = result.noopAge, let chronologicalAge {
            let target = age - chronologicalAge
            let remainder = target - items.reduce(0) { $0 + $1.impact }
            items.append(Item(id: "combined", label: "Combined model effects", domain: .body,
                              impact: remainder, paceChange: nil, isCombined: true))
        }
        return items
    }

    static func headline(result: NoopAgeWeekResult) -> String {
        guard result.noopAge != nil else { return "Building your baseline" }
        if result.confidence != .established { return "Your estimate is taking shape" }
        guard let pace = result.paceOfAging else { return "A stable overall picture" }
        if pace < 0.95 { return "Strong overall trend" }
        if pace > 1.05 { return "A clear opportunity to improve" }
        return "A stable overall picture"
    }

    static func interpretation(ranked: [Item], confidence: NoopAgeConfidence) -> String {
        let metrics = ranked.filter { !$0.isCombined }
        let helping = metrics.filter { $0.impact < -0.05 }.min { $0.impact < $1.impact }
        let holding = metrics.filter { $0.impact > 0.05 }.max { $0.impact < $1.impact }
        var parts = ["Your available habits and health signals are currently influencing your estimated Noop Age."]
        if let helping { parts.append("\(helping.label) is the strongest younger-associated contribution.") }
        if let holding { parts.append("\(holding.label) is the clearest opportunity for improvement.") }
        if helping == nil && holding == nil { parts.append("No single measured contributor is having a large effect right now.") }
        return parts.joined(separator: " ")
    }

    static func years(_ value: Double) -> String { String(format: "%+.1f years", value) }
    static func color(_ value: Double) -> Color {
        if value < -0.05 { return StrandPalette.statusPositive }
        if value > 0.05 { return StrandPalette.statusWarning }
        return StrandPalette.textTertiary
    }
    static func domainName(_ domain: NoopAgeDomain) -> String {
        switch domain { case .sleep: return "Sleep"; case .fitness: return "Fitness & Recovery"; case .activity: return "Daily Activity"; case .body: return "Body Composition" }
    }
}

private struct HealthspanContributorCard: View {
    let item: HealthspanAttribution.Item
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        SolidHealthMonitorCard(padding: 16) {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.label.uppercased()).strandOverline()
                        Spacer()
                        Text(HealthspanAttribution.years(item.impact)).font(StrandFont.number(16)).foregroundStyle(HealthspanAttribution.color(item.impact))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down").foregroundStyle(StrandPalette.textTertiary)
                    }
                    impactBar
                    HStack {
                        Text(item.impact < -0.05 ? "Helping" : item.impact > 0.05 ? "Needs attention" : "Near neutral")
                            .font(StrandFont.footnote.weight(.semibold)).foregroundStyle(HealthspanAttribution.color(item.impact))
                        Spacer()
                        if let pace = item.paceChange, abs(pace) >= 0.03 {
                            Text(pace < 0 ? "Recent trend improving" : "Recent trend declining")
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    if isExpanded { expandedContent }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label), estimated impact \(HealthspanAttribution.years(item.impact))")
        .accessibilityHint(isExpanded ? "Collapses details" : "Expands explanation and recommendation")
    }

    private var impactBar: some View {
        GeometryReader { geo in
            let cap = 2.0
            let fraction = CGFloat(max(0, min(1, (cap - item.impact) / (cap * 2))))
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    Rectangle().fill(StrandPalette.statusWarning.opacity(0.85))
                    Rectangle().fill(StrandPalette.statusWarning.opacity(0.40))
                    Rectangle().fill(StrandPalette.textTertiary.opacity(0.35))
                    Rectangle().fill(StrandPalette.statusPositive.opacity(0.35))
                    Rectangle().fill(StrandPalette.statusPositive.opacity(0.8))
                }.clipShape(Capsule())
                Rectangle().fill(StrandPalette.textPrimary).frame(width: 2, height: 17)
                    .offset(x: max(0, min(geo.size.width - 2, geo.size.width * fraction)))
            }
        }.frame(height: 10)
        .overlay(alignment: .top) { HStack { Text("Older"); Spacer(); Text("Neutral"); Spacer(); Text("Younger") }.font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).offset(y: 13) }
        .padding(.bottom, 14)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(StrandPalette.hairline)
            Text(overview).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Text("RECOMMENDATION").strandOverline()
            Text(recommendation).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var overview: String {
        if abs(item.impact) < 0.05 { return "This metric is close to the model's neutral reference and currently has a limited estimated age impact." }
        return item.impact < 0
            ? "Your longer-term \(item.label.lowercased()) signal is currently associated with a younger Noop Age estimate."
            : "Your longer-term \(item.label.lowercased()) signal is currently associated with an older Noop Age estimate."
    }

    private var recommendation: String {
        switch item.id {
        case "sleep_duration": return "Increase sleep gradually and protect a consistent wake time; avoid reacting aggressively to a single short night."
        case "sleep_consistency": return "Keep sleep and wake timing reasonably consistent across the week."
        case "steps": return "Build daily movement progressively with a level that is sustainable for you."
        case "zone_1_3": return "Maintain regular moderate cardiovascular activity and increase volume gradually."
        case "zone_4_5": return "Use higher-intensity work selectively and allow adequate recovery between demanding sessions."
        case "strength": return "Maintain consistent resistance training with recoverable volume and sound technique."
        case "rhr": return "Prioritize recovery fundamentals and review the longer trend rather than one isolated reading."
        case "vo2max": return "Consistent aerobic training can support this fitness signal; progress conservatively."
        case "lean_mass": return "Support strength with adequate recovery and nutrition; this is a broad wellness estimate, not a diagnosis."
        default: return "Keep collecting valid data and focus on sustainable habits rather than short-term fluctuations."
        }
    }
}

private struct ContributorImpactRow: View {
    let item: NoopAgeContributor

    private var color: Color {
        if abs(displayAdjustment) < 0.1 { return StrandPalette.textTertiary }
        return displayAdjustment < 0 ? StrandPalette.statusPositive : HealthspanOrbPalette.worsening
    }

    private var displayAdjustment: Double { item.recentAdjustmentYears ?? item.adjustmentYears }

    private var effectText: String {
        let direction: String
        if abs(displayAdjustment) < 0.1 { direction = "near neutral" }
        else { direction = displayAdjustment < 0 ? "reducing the trajectory" : "raising the trajectory" }
        return "\(HealthspanContributorScale.effect(for: displayAdjustment)) · \(direction)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Text(effectText).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.72)
            }
            GeometryReader { proxy in
                let center = proxy.size.width / 2
                let position = HealthspanContributorScale.position(for: displayAdjustment)
                let length = abs(position) * center
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset).frame(height: 4)
                    Rectangle().fill(StrandPalette.hairlineStrong).frame(width: 1, height: 14).offset(x: center)
                    Capsule().fill(color.opacity(0.76)).frame(width: length, height: 5)
                        .offset(x: position < 0 ? center - length : center)
                    Circle().fill(color).frame(width: 9, height: 9)
                        .shadow(color: color.opacity(0.45), radius: 4)
                        .offset(x: max(0, min(proxy.size.width - 9, center + position * center - 4.5)))
                }
                .animation(StrandMotion.interactive, value: displayAdjustment)
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label), \(effectText)")
    }
}

enum HealthspanOrbPalette {
    static let improving = Color(red: 0.02, green: 0.84, blue: 0.50)
    static let neutral = Color(red: 0.95, green: 0.65, blue: 0.18)
    static let worsening = Color(red: 1.00, green: 0.38, blue: 0.10)
    static let calibrating = Color(red: 0.55, green: 0.59, blue: 0.64)
}

struct NoopAgeOrb: View {
    enum LabelMode {
        case full
        case ageOnly
        case hidden
    }

    let age: Double
    let chronologicalAge: Double
    let confidence: NoopAgeConfidence
    var neutralPreview = false
    var labelMode: LabelMode = .full
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var appearedAt = Date()
    @State private var isVisible = false

    private var tint: Color {
        if neutralPreview { return HealthspanOrbPalette.calibrating }
        let delta = age - chronologicalAge
        switch HealthspanDirection.classify(delta: delta) {
        case .improving: return HealthspanOrbPalette.improving
        case .worsening: return HealthspanOrbPalette.worsening
        case .neutral: return HealthspanOrbPalette.neutral
        }
    }

    var body: some View {
        let animates = isVisible && HealthspanAnimationPolicy.animates(
            reduceMotion: reduceMotion, sceneIsActive: scenePhase == .active
        )
        TimelineView(.animation(minimumInterval: animates ? 1.0 / 24 : 1,
                                paused: !animates)) { timeline in
            let t = animates ? max(0, timeline.date.timeIntervalSince(appearedAt)) : 0
            ZStack {
                Canvas { context, size in
                    let geometry = HealthspanOrbGeometry(size: size)
                    let scale = HealthspanOrbMotion.shellScale(at: t)
                    let center = geometry.center
                    let shellRadius = geometry.shellRadius(scale: scale)
                    let coreRadius = geometry.coreRadius(scale: scale)
                    let glowRadius = geometry.glowRadius(scale: scale)
                    let shellPhase = HealthspanOrbMotion.shellPhase(at: t)
                    let shellCircle = geometry.circle(radius: shellRadius)

                    // Ambient glow is centered, shell-bound, and filter-scoped so it cannot affect the
                    // particles or rim. It supports the sphere instead of becoming a second flat disk.
                    context.drawLayer { glow in
                        glow.addFilter(.shadow(
                            color: tint.opacity(0.14),
                            radius: geometry.baseRadius * 0.045,
                            x: 0,
                            y: 0
                        ))

                        glow.fill(
                            Path(ellipseIn: geometry.circle(radius: glowRadius)),
                            with: .color(tint.opacity(0.025))
                        )
                    }

                    context.fill(
                        Path(ellipseIn: shellCircle),
                        with: .color(.black)
                    )

                    // Centered luminous shell. The light source is expressed by the later rim highlight,
                    // never by moving this gradient's geometric center away from the canonical center.
                    context.fill(
                        Path(ellipseIn: shellCircle),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: tint.opacity(0.0), location: 0.00),
                                .init(color: tint.opacity(0.01), location: 0.66),
                                .init(color: tint.opacity(0.08), location: 0.76),
                                .init(color: tint.opacity(0.28), location: 0.88),
                                .init(color: tint.opacity(0.50), location: 0.94),
                                .init(color: tint.opacity(0.8), location: 1.00)

                            ]),
                            center: center,
                            startRadius: 0,
                            endRadius: shellRadius
                        )
                    )

                    // A distinct centered core keeps the text field dark without redefining shell geometry.
                    context.fill(
                        Path(ellipseIn: geometry.circle(radius: coreRadius)),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.995), location: 0.82),
                                .init(color: .black.opacity(0.94), location: 1)
                            ]),
                            center: center,
                            startRadius: 0,
                            endRadius: coreRadius
                        )
                    )

                    context.clip(to: Path(ellipseIn: shellCircle))
                    for index in 0..<320 {
                        let seed = Double(index) + 1
                        let baseDepth = HealthspanOrbMotion.unit(seed * 12.9898) * 2 - 1
                        let theta = HealthspanOrbMotion.unit(seed * 78.233) * .pi * 2
                        // Cube root produces a volume-uniform radial distribution, including the core,
                        // instead of concentrating every point in a thin outer ring.
                        let radial =
                            0.55
                            + pow(
                                HealthspanOrbMotion.unit(seed * 39.425),
                                0.80
                            ) * 0.40

                        let motion = HealthspanOrbMotion.particle(index: index, elapsed: t)
                        let depth = max(-1, min(1, baseDepth + motion.depth))

                        let p = geometry.project(
                            normalizedX: cos(theta) * radial + motion.xDrift * 0.35,
                            normalizedY: sin(theta) * radial + motion.yDrift * 0.35,
                            scale: scale
                        )
                        let random = HealthspanOrbMotion.unit(seed * 91.7)

                        let dot =
                            0.45
                            + pow(random, 2.4) * 2.0
                            + max(0, depth) * 0.35

                        var opacity =
                            0.22
                            + random * 0.28
                            + max(0, depth) * 0.16

                        let twinkle =
                            0.90
                            + 0.10 * sin(t * 1.65 + seed * 1.73)

                        opacity *= twinkle

                        context.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot,
                                                            width: dot * 2, height: dot * 2)),
                                     with: .color(tint.opacity(opacity)))
                    }

                    context.stroke(Path(ellipseIn: shellCircle.insetBy(dx: 1.5, dy: 1.5)),
                                   with: .color(tint.opacity(0.28)),
                                   lineWidth: 0.8)
                    var highlight = Path()
                    highlight.addArc(center: center, radius: shellRadius - 3,
                                     startAngle: .degrees(205 + shellPhase * 4),
                                     endAngle: .degrees(315 + shellPhase * 4), clockwise: false)
                    context.stroke(
                        highlight,
                        with: .color(tint.opacity(0.10)),
                        style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                    )
                }
                if labelMode == .full {
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", age)).font(StrandFont.display(50)).foregroundStyle(.white)
                        Text("NOOP AGE").strandOverline().foregroundStyle(.white.opacity(0.72))
                        Text(deltaText).font(StrandFont.headline).foregroundStyle(tint)
                        Text(confidence.rawValue.capitalized).font(StrandFont.footnote).foregroundStyle(.white.opacity(0.55))
                    }
                } else if labelMode == .ageOnly {
                    Text(String(format: "%.1f", age))
                        .font(StrandFont.display(38))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            appearedAt = Date()
            isVisible = true
        }
        .onDisappear { isVisible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(neutralPreview ? "Noop Age is calibrating" : "Noop Age \(String(format: "%.1f", age)), \(deltaText), confidence \(confidence.rawValue)")
    }

    private var deltaText: String {
        let delta = chronologicalAge - age
        if abs(delta) < 0.05 { return "Matches your age" }
        return String(format: "%.1f years %@", abs(delta), delta > 0 ? "younger" : "older")
    }
}

#Preview("Healthspan Orb") {
    ZStack {
        liquidScaffoldSky()
            .ignoresSafeArea()

        NoopAgeOrb(
            age: 23.2,
            chronologicalAge: 27.0,
            confidence: .established
        )
        .frame(width: 360, height: 360)
    }
    .preferredColorScheme(.dark)
}
