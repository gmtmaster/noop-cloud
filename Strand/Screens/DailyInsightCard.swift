import SwiftUI
import StrandDesign

struct InsightDriver: Identifiable {
    let id: String
    let title: String
    let value: String
    let caption: String?
    let tint: Color
    let systemImage: String?

    init(_ label: String, tint: Color, systemImage: String? = nil) {
        self.id = label
        self.title = label
        self.value = ""
        self.caption = nil
        self.tint = tint
        self.systemImage = systemImage
    }

    init(title: String, value: String, caption: String? = nil, tint: Color, systemImage: String? = nil) {
        self.id = "\(title)-\(value)-\(caption ?? "")"
        self.title = title
        self.value = value
        self.caption = caption
        self.tint = tint
        self.systemImage = systemImage
    }

    var accessibilityText: String {
        [title, value, caption].compactMap { text in
            guard let text, !text.isEmpty else { return nil }
            return text
        }.joined(separator: " ")
    }
}

struct DailyInsightCard: View {
    let title: LocalizedStringKey
    let overline: LocalizedStringKey
    let status: LocalizedStringKey
    let detail: LocalizedStringKey
    let tint: Color
    let drivers: [InsightDriver]

    var body: some View {
        NoopCard(padding: 18, tint: tint) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(overline).strandOverline()
                        Text(title)
                            .font(StrandFont.title2)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    Spacer(minLength: NoopMetrics.space2)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text(status)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !drivers.isEmpty {
                    Divider().overlay(StrandPalette.hairline)
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text("Why today?").strandOverline()
                        FlowLayout(spacing: 7, lineSpacing: 7) {
                            ForEach(drivers) { driver in
                                InsightDriverChip(driver: driver)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct InsightDriverChip: View {
    let driver: InsightDriver

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage = driver.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(driver.tint)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(driver.tint.opacity(0.14)))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(driver.title)
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                    if !driver.value.isEmpty {
                        Text(driver.value)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(driver.tint)
                            .lineLimit(1)
                    }
                }
                if let caption = driver.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, driver.systemImage == nil ? 10 : 6)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(StrandPalette.surfaceRaised.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(driver.tint.opacity(0.26), lineWidth: 1))
        .accessibilityLabel(driver.accessibilityText)
    }
}

struct MetricMiniStat: View {
    let title: LocalizedStringKey
    let value: String
    let caption: LocalizedStringKey
    let tint: Color
    let systemImage: String

    var body: some View {
        NoopCard(padding: 14, tint: tint) {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint.opacity(0.12)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).strandOverline()
                    Text(caption)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: NoopMetrics.space2)
                Text(value)
                    .font(StrandFont.number(26))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecoveryVitalCell: View {
    let title: String
    let value: String
    let unit: String
    let caption: String
    let tint: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(tint.opacity(0.13)))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            Text(title)
                .font(StrandFont.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(StrandFont.number(25))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(unit)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(1)
            }
            Text(caption)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(StrandPalette.surfaceRaised.opacity(0.72)))
        .accessibilityElement(children: .combine)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return layout(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, items: [(index: Int, origin: CGPoint, size: CGSize)]) {
        var items: [(index: Int, origin: CGPoint, size: CGSize)] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        let available = max(width, 1)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > available {
                cursor.x = 0
                cursor.y += lineHeight + lineSpacing
                lineHeight = 0
            }
            items.append((index, cursor, size))
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, cursor.x - spacing)
        }

        return (CGSize(width: min(available, maxWidth), height: cursor.y + lineHeight), items)
    }
}
