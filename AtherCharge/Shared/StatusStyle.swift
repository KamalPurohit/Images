import SwiftUI
import AtherKit

enum Theme {
    static let accent = Color(red: 0.13, green: 0.80, blue: 0.62)
    static let charging = Color(red: 0.30, green: 0.87, blue: 0.40)
    static let medium = Color(red: 1.00, green: 0.72, blue: 0.22)
    static let low = Color(red: 0.96, green: 0.32, blue: 0.27)
    static let backgroundTop = Color(red: 0.08, green: 0.13, blue: 0.12)
    static let backgroundBottom = Color(red: 0.02, green: 0.05, blue: 0.05)
}

extension ChargeStatus {
    var socText: String { "\(Int(soc.rounded()))%" }

    var stateTitle: String {
        switch state {
        case .charging: return "Charging"
        case .full: return "Fully charged"
        case .notCharging: return "Not charging"
        case .unknown: return "Battery"
        }
    }

    var shortStateTitle: String {
        switch state {
        case .charging: return "Charging"
        case .full: return "Full"
        case .notCharging: return "Unplugged"
        case .unknown: return "Battery"
        }
    }

    var stateSymbol: String {
        switch state {
        case .charging: return "bolt.fill"
        case .full: return "checkmark.circle.fill"
        case .notCharging: return "bolt.slash.fill"
        case .unknown: return batterySymbol
        }
    }

    var batterySymbol: String {
        switch soc {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var levelColor: Color {
        if state == .charging || state == .full { return Theme.charging }
        if soc < 20 { return Theme.low }
        if soc < 40 { return Theme.medium }
        return Theme.accent
    }

    var sourceNote: String {
        switch stateSource {
        case .reported: return isDemo ? "Simulated" : "Reported by the scooter"
        case .inferred: return "Estimated from battery changes"
        case .none: return "Charging state not reported yet"
        }
    }

    /// When the timer should count down to, if the scooter is charging and the time is still ahead.
    func countdownTarget(from now: Date) -> Date? {
        guard state == .charging, let fullAt, fullAt > now else { return nil }
        return fullAt
    }

    var displayName: String { scooterName ?? "Ather" }

    /// One line for Siri and Shortcuts.
    var summary: String {
        var text = "\(displayName): \(socText), \(stateTitle.lowercased())"
        if let fullAt, state == .charging, fullAt > Date() {
            text += ", full \(fullAtIsEstimate ? "around" : "at") \(fullAt.formatted(date: .omitted, time: .shortened))"
        }
        if let rangeKm { text += ", \(Int(rangeKm.rounded())) km range" }
        return text + "."
    }
}

/// Circular battery gauge used by the app and the widget.
struct BatteryRing<Content: View>: View {
    var soc: Double
    var color: Color
    var lineWidth: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(soc, 100) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .padding(lineWidth / 2)
    }
}
