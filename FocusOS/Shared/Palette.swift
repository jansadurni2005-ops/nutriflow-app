import SwiftUI

/// Paleta de FOCUS OS. Compartida por la app y los widgets.
enum Palette {
    /// Fondo negro profundo #090909
    static let background = Color(hex: "090909")
    /// Tarjetas #171717
    static let card = Color(hex: "171717")
    /// Tarjeta elevada / controles
    static let cardElevated = Color(hex: "202020")
    /// Separadores y bordes sutiles
    static let stroke = Color.white.opacity(0.07)
    /// Naranja eléctrico #FF6500
    static let accent = Color(hex: "FF6500")
    static let accentSoft = Color(hex: "FF6500").opacity(0.16)

    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "A1A1A1")
    static let textTertiary = Color(hex: "5E5E5E")

    static let success = Color(hex: "35D07F")
    static let warning = Color(hex: "FFB020")
    static let danger = Color(hex: "FF3B30")
    static let info = Color(hex: "4C8DFF")

    /// Colores seleccionables para bloques.
    static let blockColors: [String] = [
        "FF6500", "FF9F0A", "FFD60A", "35D07F", "30D5C8",
        "4C8DFF", "7D5CFF", "BF5AF2", "FF375F", "8E8E93"
    ]

    /// Color de una puntuación 0...1
    static func scoreColor(_ value: Double?) -> Color {
        guard let value else { return textTertiary }
        switch value {
        case ..<0.5: return danger
        case ..<0.7: return warning
        case ..<0.85: return Color(hex: "FF8A3D")
        default: return accent
        }
    }
}

extension Color {
    /// Crea un color a partir de un hex "RRGGBB" o "#RRGGBB".
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: Double
        switch cleaned.count {
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// Formateo de tiempo compartido (app + widgets).
enum TimeFormat {
    /// 01:24:35
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// 24:35 o 1:24:35 según la duración.
    static func compactClock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "5h 15m", "45m", "0m"
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// "5,3 h"
    static func hours(_ seconds: TimeInterval) -> String {
        let h = seconds / 3600
        return h.formatted(.number.precision(.fractionLength(h < 10 ? 1 : 0))) + " h"
    }

    static func hhmm(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
}
