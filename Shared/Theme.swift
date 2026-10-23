import SwiftUI
import UpslopeCore

/// Trail Map in Spruce & Signal (PLAN.md §4).
enum Theme {
    static let bg = Color(hex: 0x0E2620)
    static let surface = Color(hex: 0x173A30)
    static let line = Color(hex: 0x2B5446)
    static let text = Color(hex: 0xF1F6F2)
    static let soft = Color(hex: 0xD3E3DA)
    static let muted = Color(hex: 0xA2BFB2)
    static let accent = Color(hex: 0xF2C230)
    static let onAccent = Color(hex: 0x0E2620)
    static let bar = Color(hex: 0xE4EFE8)
    static let nav = Color(hex: 0x0A1D18)
    static let snow = Color(hex: 0xCFE8FF)
    static let rain = Color(hex: 0x8CC3FF)
    static let mix = Color(hex: 0xD8C9FF)
    static let trailGreen = Color(hex: 0x2FA84F)
    static let trailBlue = Color(hex: 0x3D7BFF)

    static func color(for type: PrecipType) -> Color {
        switch type {
        case .snow: return snow
        case .rain: return rain
        case .mix: return mix
        case .none: return muted
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Barlow Condensed for headings and numbers, Barlow for body (bundled, SIL OFL).
enum UFont {
    static func display(_ size: CGFloat, bold: Bool = true, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(bold ? "BarlowCondensed-Bold" : "BarlowCondensed-SemiBold", size: size, relativeTo: style)
    }

    static func body(_ size: CGFloat, weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.name, size: size, relativeTo: style)
    }

    enum Weight {
        case regular, medium, semibold
        var name: String {
            switch self {
            case .regular: return "Barlow-Regular"
            case .medium: return "Barlow-Medium"
            case .semibold: return "Barlow-SemiBold"
            }
        }
    }
}

/// Trail-sign shapes for precipitation intensity: circle, square, diamond.
struct IntensityMark: View {
    var intensity: Intensity
    var size: CGFloat = 10
    /// Lock screen widgets render in one tint, so they get outline-free shapes.
    var monochrome = false

    var body: some View {
        switch intensity {
        case .none:
            EmptyView()
        case .light:
            Circle().fill(monochrome ? Color.primary : Theme.trailGreen).frame(width: size, height: size)
        case .moderate:
            Rectangle().fill(monochrome ? Color.primary : Theme.trailBlue).frame(width: size * 0.9, height: size * 0.9)
        case .heavy:
            Rectangle()
                .fill(monochrome ? Color.primary : Color.black)
                .overlay(Rectangle().stroke(monochrome ? Color.clear : Color.white, lineWidth: 1.2))
                .frame(width: size * 0.72, height: size * 0.72)
                .rotationEffect(.degrees(45))
                .frame(width: size, height: size)
        }
    }
}

struct PrecipIcon: View {
    var type: PrecipType
    var body: some View {
        Image(systemName: Self.symbol(type))
    }

    static func symbol(_ type: PrecipType) -> String {
        switch type {
        case .snow: return "snowflake"
        case .rain: return "cloud.rain"
        case .mix: return "cloud.sleet"
        case .none: return "sun.max"
        }
    }

    static func symbol(_ s: DaySymbol) -> String {
        switch s {
        case .sun: return "sun.max"
        case .partly: return "cloud.sun"
        case .cloud: return "cloud"
        case .rain: return "cloud.rain"
        case .snow: return "cloud.snow"
        case .mix: return "cloud.sleet"
        case .fog: return "cloud.fog"
        case .storm: return "cloud.bolt.rain"
        }
    }
}
