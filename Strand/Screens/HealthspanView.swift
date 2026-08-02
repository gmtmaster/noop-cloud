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

struct HealthspanView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var history: [NoopAgeWeekResult] = []
    @State private var selectedIndex = 0

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
                    .frame(maxWidth: .infinity)
                paceSection(result)
                contributorCard(result)
                modelNote
            } else {
                ComingSoon(what: "Noop Age needs at least four nights of resting heart rate in a week. Keep wearing your device and check back after more history lands.", symbol: "heart.circle")
            }
        }
        .task(id: repo.refreshSeq) { await load() }
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
        let helping = result.contributors.filter { $0.impact == .helping && abs($0.adjustmentYears) >= 0.1 }
        let holding = result.contributors.filter { $0.impact == .holdingBack && abs($0.adjustmentYears) >= 0.1 }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("What moved it", overline: "Weekly contributors",
                          trailing: result.confidence.rawValue.capitalized)
            NoopCard(tint: StrandPalette.chargeColor) {
                VStack(alignment: .leading, spacing: 14) {
                    contributorGroup("Helping", items: helping.prefix(3), color: StrandPalette.statusPositive)
                    if !helping.isEmpty && !holding.isEmpty { Divider().overlay(StrandPalette.hairline) }
                    contributorGroup("Holding you back", items: holding.prefix(3), color: StrandPalette.statusWarning)
                    if helping.isEmpty && holding.isEmpty {
                        Text("No strong contributor stood out this week.")
                            .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
    }

    private func contributorGroup<S: Sequence>(_ title: LocalizedStringKey, items: S, color: Color) -> some View where S.Element == NoopAgeContributor {
        VStack(alignment: .leading, spacing: 8) {
            if items.contains(where: { _ in true }) {
                Text(title).strandOverline().foregroundStyle(color)
                ForEach(Array(items), id: \.key) { item in
                    Label(item.label, systemImage: item.impact == .helping ? "arrow.down.right" : "arrow.up.right")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
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

private struct NoopAgeOrb: View {
    let age: Double
    let chronologicalAge: Double
    let confidence: NoopAgeConfidence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var tint: Color {
        let delta = age - chronologicalAge
        if delta <= -1 { return StrandPalette.statusPositive }
        if delta >= 1 { return StrandPalette.statusWarning }
        return StrandPalette.chargeColor
    }

    var body: some View {
        let animates = HealthspanAnimationPolicy.animates(reduceMotion: reduceMotion, sceneIsActive: scenePhase == .active)
        TimelineView(.animation(minimumInterval: animates ? 1.0 / 24 : 1,
                                paused: !animates)) { timeline in
            let t = animates ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) * (0.42 + 0.008 * sin(t * 0.7))
                    context.addFilter(.shadow(color: tint.opacity(0.55), radius: 26))
                    context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                        width: radius * 2, height: radius * 2)),
                                 with: .radialGradient(Gradient(colors: [tint.opacity(0.7), tint.opacity(0.24), .clear]),
                                                       center: center, startRadius: 2, endRadius: radius))
                    for index in 0..<72 {
                        let seed = Double(index) * 12.9898
                        let angle = seed + t * (0.025 + Double(index % 5) * 0.004)
                        let radial = radius * (0.15 + 0.78 * abs(sin(seed * 0.37)))
                        let p = CGPoint(x: center.x + cos(angle) * radial, y: center.y + sin(angle) * radial)
                        let dot = 1.0 + Double(index % 3) * 0.55
                        context.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                                     with: .color(.white.opacity(0.28 + Double(index % 4) * 0.1)))
                    }
                }
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", age)).font(StrandFont.display(50)).foregroundStyle(.white)
                    Text("NOOP AGE").strandOverline().foregroundStyle(.white.opacity(0.72))
                    Text(deltaText).font(StrandFont.subhead).foregroundStyle(tint)
                    Text(confidence.rawValue.capitalized).font(StrandFont.footnote).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .frame(width: 330, height: 330)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Noop Age \(String(format: "%.1f", age)), \(deltaText), confidence \(confidence.rawValue)")
    }

    private var deltaText: String {
        let delta = chronologicalAge - age
        if abs(delta) < 0.05 { return "Matches your age" }
        return String(format: "%.1f years %@", abs(delta), delta > 0 ? "younger" : "older")
    }
}
