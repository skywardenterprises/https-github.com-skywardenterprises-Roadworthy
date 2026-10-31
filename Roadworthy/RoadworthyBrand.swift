import SwiftUI

// MARK: - Colors

/// Semantic colors for the vehicle list. Each adapts to light and dark
/// appearance, so nothing here forces a color scheme.
enum RWColor {
    /// Same surfaces as every other screen in the app.
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    /// The Roadworthy teal (the AccentColor asset, matched to the app icon).
    static let brand = Color.accentColor
    /// The exact teal of the app icon, for the splash screen in both
    /// appearances. White text on it has 4.7:1 contrast.
    static let splash = Color(red: 4 / 255, green: 128 / 255, blue: 139 / 255)
    /// Muted blue-gray, the second color in charts.
    static let slate = dynamic(light: 0x4F667C, dark: 0x829BB3)
    /// Warm amber for warning text. Standard orange is too light to read as
    /// text on a light background (2.2:1); this is 4.6:1 on white.
    static let amber = dynamic(light: 0xB45F06, dark: 0xE6A04A)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light)
        })
    }

    nonisolated private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension VehicleType {
    /// Accent for the small type icon. Deliberately avoids red, green and
    /// yellow so the color never reads as a maintenance or health status.
    var rowTint: Color {
        switch self {
        case .car: return .blue
        case .truck: return .orange
        case .motorcycle: return .purple
        case .rv: return .teal
        case .other: return .gray
        }
    }
}

extension View {
    /// Draws a list row as a rounded card: 16 pt side margins, 8 pt between
    /// cards and 12 pt of padding inside. The row background is inset
    /// because a plain List row background always spans the full width.
    func rwCardRow() -> some View {
        self
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RWColor.card)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 16, leading: 28, bottom: 16, trailing: 28))
    }
}

// MARK: - Footer

/// "ROADWORTHY / VEHICLE CARE" with a tire-tread band on each side. It is the
/// last row of the vehicle list, so it scrolls with the vehicles.
struct RoadworthyBrandFooter: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let showsTread = !typeSize.isAccessibilitySize
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                if showsTread {
                    RoadworthyTireTread().frame(height: 28)
                }
                Text(verbatim: "ROADWORTHY")
                    .font(.title3.weight(.bold))
                    .tracking(2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .layoutPriority(1)
                if showsTread {
                    RoadworthyTireTread(mirrored: true).frame(height: 28)
                }
            }
            HStack(spacing: 10) {
                Rectangle().frame(width: 28, height: 1)
                Text(verbatim: "VEHICLE CARE")
                    .font(.caption2.weight(.medium))
                    .tracking(3)
                Rectangle().frame(width: 28, height: 1)
            }
        }
        .foregroundStyle(RWColor.brand)
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Roadworthy: Vehicle Care"))
    }
}

/// Two rows of repeating chevrons, like a tread pattern. Drawn as vector
/// paths, so it stays sharp at any width.
struct RoadworthyTireTread: View {
    var mirrored = false

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let step: CGFloat = 10
                let slant: CGFloat = 6
                let rowHeight = proxy.size.height / 2
                for row in 0..<2 {
                    let top = CGFloat(row) * rowHeight + 1
                    let bottom = top + rowHeight - 2
                    var x: CGFloat = 0
                    while x < proxy.size.width + slant {
                        path.move(to: CGPoint(x: x, y: top))
                        path.addLine(to: CGPoint(x: x + slant, y: (top + bottom) / 2))
                        path.addLine(to: CGPoint(x: x, y: bottom))
                        x += step
                    }
                }
            }
            .stroke(
                RWColor.brand.opacity(0.55),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
        .scaleEffect(x: mirrored ? -1 : 1)
        .clipped()
        .accessibilityHidden(true)
    }
}
