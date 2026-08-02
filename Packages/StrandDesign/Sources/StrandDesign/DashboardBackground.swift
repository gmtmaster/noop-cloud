import SwiftUI

/// Canonical dashboard canvas: restrained graphite at the top, settling into near-black.
public struct DashboardBackground: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [Color(hex: "#20262C"), Color(hex: "#15191D"), Color(hex: "#090B0D")],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
