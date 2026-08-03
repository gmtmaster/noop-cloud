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
        1 + 0.012 * sin(elapsed * 0.72)
    }

    static func shellPhase(at elapsed: TimeInterval) -> Double {
        sin(elapsed * 0.18)
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
        return 0.24 + unit(seed * 3.1) * 0.10
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

    private var selected: NoopAgeWeekResult? { history.indices.contains(selectedIndex) ? history[selectedIndex] : nil }

    var body: some View {
        ScreenScaffold(title: "Healthspan", subtitle: "Your long-term fitness and health trajectory.",
                       onRefresh: { await load() }, lazy: true) {
            if !profile.ageIsExplicit && profile.birthDate == nil {
                missingAge
            } else if let result = selected, let age = result.noopAge {
                weekNavigation(result.weekEndDay)
                NoopAgeOrb(age: result.confidence == .calibrating ? age.rounded() : age,
                           chronologicalAge: chronologicalAge(for: result.weekEndDay) ?? age,
                           confidence: result.confidence)
                    .frame(maxWidth: 380)
                    .frame(maxWidth: .infinity)
                paceSection(result)
                contributorCard(result)
                modelNote
            } else {
                ComingSoon(what: "Noop Age is calibrating. Keep wearing your device through sleep and daily activity so enough reliable coverage can build.", symbol: "heart.circle")
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

    private func load() async {
        let snapshot = await repo.noopAgeSnapshot(profile: profile)
        healthspanDays = snapshot.observations
        history = snapshot.results
        selectedIndex = HealthspanSelection.newestIndex(count: history.count)
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
    @State private var appearedAt = Date()
    @State private var isVisible = false

    private var tint: Color {
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
                            + 0.10 * sin(t * 0.9 + seed * 1.73)

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
                VStack(spacing: 4) {
                    Text(String(format: "%.1f", age)).font(StrandFont.display(50)).foregroundStyle(.white)
                    Text("NOOP AGE").strandOverline().foregroundStyle(.white.opacity(0.72))
                    Text(deltaText).font(StrandFont.headline).foregroundStyle(tint)
                    Text(confidence.rawValue.capitalized).font(StrandFont.footnote).foregroundStyle(.white.opacity(0.55))
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
        .accessibilityLabel("Noop Age \(String(format: "%.1f", age)), \(deltaText), confidence \(confidence.rawValue)")
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
