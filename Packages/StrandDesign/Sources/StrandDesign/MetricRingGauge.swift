import SwiftUI

public struct MetricRingGauge: View {
    public var valueText: String
    public var unitText: String?
    public var label: String?
    public var progress: Double?
    public var tint: Color
    public var diameter: CGFloat
    public var lineWidth: CGFloat
    public var centerScale: CGFloat

    public init(
        valueText: String,
        unitText: String? = nil,
        label: String? = nil,
        progress: Double?,
        tint: Color,
        diameter: CGFloat = 92,
        lineWidth: CGFloat = 8,
        centerScale: CGFloat = 1
    ) {
        self.valueText = valueText
        self.unitText = unitText
        self.label = label
        self.progress = progress
        self.tint = tint
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.centerScale = centerScale
    }

    private var clamped: CGFloat {
        CGFloat(min(max(progress ?? 0, 0), 1))
    }

    public var body: some View {
        VStack(spacing: label == nil ? 0 : 8) {
            ZStack {
                Circle()
                    .stroke(StrandPalette.textPrimary.opacity(0.10),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Circle()
                    .trim(from: 0, to: max(0.0001, clamped))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.28), radius: 7, y: 0)
                    .opacity(progress == nil ? 0.28 : 1)

                VStack(spacing: -1) {
                    if !valueText.isEmpty {
                        Text(valueText)
                            .font(StrandFont.rounded(max(11, diameter * 0.30 * centerScale), weight: .bold))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    if let unitText, !unitText.isEmpty {
                        Text(unitText)
                            .font(StrandFont.overlineScaled(max(7, diameter * 0.08)))
                            .tracking(0.8)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, lineWidth + 2)
            }
            .frame(width: diameter, height: diameter)
            .animation(StrandMotion.gentle, value: clamped)

            if let label, !label.isEmpty {
                Text(label.uppercased())
                    .font(StrandFont.overlineScaled(10))
                    .tracking(1.3)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
