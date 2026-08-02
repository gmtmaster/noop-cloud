import SwiftUI
import StrandAnalytics
import StrandDesign

enum HealthNavigationContract {
    static let primaryTabs = ["Today", "Health", "Sleep", "Friends", "More"]
    static let healthTabIndex = 1
    static let trendsRemainsSecondary = true
}

enum HealthspanAnimationPolicy {
    static func animates(reduceMotion: Bool, sceneIsActive: Bool) -> Bool {
        !reduceMotion && sceneIsActive
    }
}

/// Presentation-only mapping for the contributor scale. The engine's signed year adjustment remains the
/// sole source of truth; the cap only prevents one large value from making every other marker unreadable.
enum HealthspanContributorScale {
    static let visualCapYears = 2.0

    static func sorted(_ contributors: [NoopAgeContributor]) -> [NoopAgeContributor] {
        contributors.sorted {
            sortsBefore(lhsLabel: $0.label, lhsAdjustment: $0.adjustmentYears,
                        rhsLabel: $1.label, rhsAdjustment: $1.adjustmentYears)
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
    @State private var selectedIndex = 0
    @State private var showsAllContributors = false

    private var selected: NoopAgeWeekResult? { history.indices.contains(selectedIndex) ? history[selectedIndex] : nil }

    var body: some View {
        ScreenScaffold(title: "Healthspan", subtitle: "Your long-term fitness and health trajectory.",
                       onRefresh: { await load() }, lazy: true, topBackground: liquidScaffoldSky()) {
            if !profile.ageIsExplicit && profile.birthDate == nil {
                missingAge
            } else if let result = selected, let age = result.noopAge {
                weekNavigation(result.weekEndDay)
                NoopAgeOrb(age: age, chronologicalAge: chronologicalAge(for: result.weekEndDay) ?? age,
                           confidence: result.confidence)
                    .frame(maxWidth: 380)
                    .frame(maxWidth: .infinity)
                paceSection(result)
                contributorCard(result)
                modelNote
            } else {
                ComingSoon(what: "Noop Age needs at least four nights of resting heart rate in a week. Keep wearing your device and check back after more history lands.", symbol: "heart.circle")
            }
        }
        .task(id: repo.refreshSeq) { await load() }
        .onChange(of: selectedIndex) { _, _ in showsAllContributors = false }
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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Pace of Aging", overline: "Recent modeled trajectory")
            NoopCard(tint: paceColor(result.paceOfAging)) {
                VStack(spacing: 12) {
                    Text(result.paceOfAging.map { String(format: "%.1fx", $0) } ?? "—")
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
                    Text(result.paceOfAging == nil
                         ? "At least four weekly Noop Age points are needed."
                         : "A bounded trend in your modeled fitness and health estimate—not literal biological aging speed.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private func contributorCard(_ result: NoopAgeWeekResult) -> some View {
        let sorted = HealthspanContributorScale.sorted(result.contributors.filter { abs($0.adjustmentYears) >= 0.05 })
        let visible = showsAllContributors ? sorted : Array(sorted.prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("What Is Moving Your Noop Age", overline: "Weekly contributors",
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
                        Text("No strong contributor stood out this week.")
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

    private var modelNote: some View {
        Text("Noop Age is a deterministic, WHOOP-inspired functional fitness comparison built from your available data. It is not WHOOP’s formula, a biological age, diagnosis, lifespan estimate, or disease-risk score.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
    }

    private func load() async {
        history = await repo.noopAgeHistory(profile: profile)
        selectedIndex = max(0, history.count - 1)
    }
    private func chronologicalAge(for day: String) -> Double? {
        guard let date = Self.parser.date(from: day) else { return profile.ageIsExplicit ? Double(profile.age) : nil }
        return profile.chronologicalAge(on: date)
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

private struct ContributorImpactRow: View {
    let item: NoopAgeContributor

    private var color: Color {
        if abs(item.adjustmentYears) < 0.1 { return StrandPalette.textTertiary }
        return item.adjustmentYears < 0 ? StrandPalette.statusPositive : HealthspanOrbPalette.worsening
    }

    private var effectText: String {
        let direction: String
        if abs(item.adjustmentYears) < 0.1 { direction = "near neutral" }
        else { direction = item.adjustmentYears < 0 ? "reducing the estimate" : "raising the estimate" }
        return "\(HealthspanContributorScale.effect(for: item.adjustmentYears)) · \(direction)"
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
                let position = HealthspanContributorScale.position(for: item.adjustmentYears)
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
                .animation(StrandMotion.interactive, value: item.adjustmentYears)
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label), \(effectText)")
    }
}

private enum HealthspanOrbPalette {
    static let improving = Color(red: 0.02, green: 0.84, blue: 0.50)
    static let neutral = Color(red: 0.95, green: 0.65, blue: 0.18)
    static let worsening = Color(red: 1.00, green: 0.38, blue: 0.10)
}

private struct NoopAgeOrb: View {
    let age: Double
    let chronologicalAge: Double
    let confidence: NoopAgeConfidence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var tint: Color {
        let delta = age - chronologicalAge
        if delta <= -1 { return HealthspanOrbPalette.improving }
        if delta >= 1 { return HealthspanOrbPalette.worsening }
        return HealthspanOrbPalette.neutral
    }

    var body: some View {
        let animates = HealthspanAnimationPolicy.animates(reduceMotion: reduceMotion, sceneIsActive: scenePhase == .active)
        TimelineView(.animation(minimumInterval: animates ? 1.0 / 24 : 1,
                                paused: !animates)) { timeline in
            let t = animates ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) * (0.435 + 0.004 * sin(t * 0.42))
                    let sphere = CGRect(x: center.x - radius, y: center.y - radius,
                                      width: radius * 2, height: radius * 2)

                    context.addFilter(.shadow(color: tint.opacity(0.42), radius: 22, x: 0, y: 8))
                    context.fill(Path(ellipseIn: sphere), with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.98), location: 0.48),
                            .init(color: tint.opacity(0.13), location: 0.68),
                            .init(color: tint.opacity(0.72), location: 0.94),
                            .init(color: tint.opacity(0.24), location: 1)
                        ]), center: CGPoint(x: center.x - radius * 0.15, y: center.y - radius * 0.18),
                        startRadius: 0, endRadius: radius))

                    context.clip(to: Path(ellipseIn: sphere))
                    for index in 0..<128 {
                        let seed = Double(index) + 1
                        let u = Self.unit(seed * 12.9898) * 2 - 1
                        let theta = Self.unit(seed * 78.233) * .pi * 2
                        let shell = 0.58 + Self.unit(seed * 39.425) * 0.40
                        let planar = sqrt(max(0, 1 - u * u))
                        let driftX = 0.045 * sin(t * (0.035 + Self.unit(seed * 3.1) * 0.025) + seed)
                        let driftY = 0.04 * sin(t * (0.027 + Self.unit(seed * 5.7) * 0.022) + seed * 0.71)
                        let x = (cos(theta) * planar * shell + driftX) * radius
                        let y = (sin(theta) * planar * shell + driftY) * radius
                        let depth = u
                        let p = CGPoint(x: center.x + x, y: center.y + y * 0.96)
                        let dot = 0.7 + Self.unit(seed * 91.7) * 1.65 + max(0, depth) * 0.7
                        let opacity = 0.18 + (depth + 1) * 0.19 + Self.unit(seed * 17.3) * 0.22
                        context.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot,
                                                            width: dot * 2, height: dot * 2)),
                                     with: .color(tint.opacity(opacity)))
                    }
                    context.stroke(Path(ellipseIn: sphere.insetBy(dx: 1.5, dy: 1.5)),
                                   with: .color(tint.opacity(0.55)), lineWidth: 1.2)
                }
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", age)).font(StrandFont.display(50)).foregroundStyle(.white)
                    Text("NOOP AGE").strandOverline().foregroundStyle(.white.opacity(0.72))
                    Text(deltaText).font(StrandFont.subhead).foregroundStyle(tint)
                    Text(confidence.rawValue.capitalized).font(StrandFont.footnote).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Noop Age \(String(format: "%.1f", age)), \(deltaText), confidence \(confidence.rawValue)")
    }

    private static func unit(_ value: Double) -> Double {
        let raw = sin(value) * 43_758.5453
        return raw - floor(raw)
    }

    private var deltaText: String {
        let delta = chronologicalAge - age
        if abs(delta) < 0.05 { return "Matches your age" }
        return String(format: "%.1f years %@", abs(delta), delta > 0 ? "younger" : "older")
    }
}
