import WidgetKit
import SwiftUI
import AppIntents
import AtherKit

struct ChargeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ChargeEntry

    var body: some View {
        if let status = entry.status {
            switch family {
            case .accessoryCircular: CircularView(status: status)
            case .accessoryRectangular: RectangularView(entry: entry, status: status)
            case .accessoryInline: InlineView(entry: entry, status: status)
            case .systemMedium: MediumView(entry: entry, status: status)
            default: SmallView(entry: entry, status: status)
            }
        } else {
            MessageView(entry: entry)
        }
    }
}

// MARK: - Home Screen

private struct SmallView: View {
    var entry: ChargeEntry
    var status: ChargeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeaderRow(entry: entry, status: status)
            BatteryRing(soc: status.soc, color: status.levelColor, lineWidth: 7) {
                VStack(spacing: 0) {
                    if status.state == .charging {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(status.levelColor)
                    }
                    Text(status.socText)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let target = status.countdownTarget(from: entry.date) {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                    Text(timerInterval: entry.date...target, countsDown: true)
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.levelColor)
                .frame(maxWidth: .infinity)
            } else {
                Label(status.stateTitle, systemImage: status.stateSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.levelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct MediumView: View {
    var entry: ChargeEntry
    var status: ChargeStatus

    var body: some View {
        HStack(spacing: 16) {
            BatteryRing(soc: status.soc, color: status.levelColor, lineWidth: 10) {
                VStack(spacing: 0) {
                    Image(systemName: status.state == .charging ? "bolt.fill" : "scooter")
                        .font(.subheadline)
                        .foregroundStyle(status.levelColor)
                    Text(status.socText)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 4) {
                HeaderRow(entry: entry, status: status, showsRefresh: true)
                Label(status.stateTitle, systemImage: status.stateSymbol)
                    .font(.headline)
                    .foregroundStyle(status.levelColor)
                if let target = status.countdownTarget(from: entry.date) {
                    HStack(spacing: 4) {
                        Text("Full in")
                        Text(timerInterval: entry.date...target, countsDown: true)
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    Text("\(status.fullAtIsEstimate ? "≈ " : "at ")\(target.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let range = status.rangeKm {
                    Label("\(Int(range.rounded())) km range", systemImage: "road.lanes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                FooterRow(entry: entry, status: status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
}

private struct HeaderRow: View {
    var entry: ChargeEntry
    var status: ChargeStatus
    var showsRefresh = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "scooter")
            Text(status.displayName)
                .lineLimit(1)
            if status.isDemo {
                Text("DEMO")
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
            Spacer(minLength: 0)
            if showsRefresh {
                Button(intent: RefreshChargeStatusIntent()) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            } else if entry.snapshot.lastError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.medium)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct FooterRow: View {
    var entry: ChargeEntry
    var status: ChargeStatus

    var body: some View {
        Group {
            if entry.snapshot.needsSignIn {
                Label("Sign in again in the app", systemImage: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(Theme.medium)
            } else if entry.snapshot.lastError != nil {
                Label("Update failed · \(status.asOf.formatted(date: .omitted, time: .shortened))", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.medium)
            } else {
                HStack(spacing: 3) {
                    Text("Updated")
                    Text(status.asOf, style: .relative)
                    Text("ago")
                }
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Lock Screen

private struct CircularView: View {
    var status: ChargeStatus

    var body: some View {
        Gauge(value: min(status.soc, 100), in: 0...100) {
            Image(systemName: status.state == .charging ? "bolt.fill" : "scooter")
        } currentValueLabel: {
            Text("\(Int(status.soc.rounded()))")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

private struct RectangularView: View {
    var entry: ChargeEntry
    var status: ChargeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: status.stateSymbol)
                Text(status.socText)
                    .font(.headline)
                Text(status.shortStateTitle)
                    .font(.caption)
            }
            .widgetAccentable()
            if let target = status.countdownTarget(from: entry.date) {
                HStack(spacing: 3) {
                    Text("Full in")
                    Text(timerInterval: entry.date...target, countsDown: true)
                        .monospacedDigit()
                }
                .font(.caption)
            } else if let range = status.rangeKm {
                Text("\(Int(range.rounded())) km range")
                    .font(.caption)
            } else {
                Text(status.displayName)
                    .font(.caption)
            }
            Gauge(value: min(status.soc, 100), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
        }
    }
}

private struct InlineView: View {
    var entry: ChargeEntry
    var status: ChargeStatus

    var body: some View {
        if let target = status.countdownTarget(from: entry.date) {
            Label {
                Text("\(status.socText) · full \(target.formatted(date: .omitted, time: .shortened))")
            } icon: {
                Image(systemName: "bolt.fill")
            }
        } else {
            Label("\(status.socText) · \(status.shortStateTitle)", systemImage: status.stateSymbol)
        }
    }
}

// MARK: - No data

private struct MessageView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ChargeEntry

    private var message: (symbol: String, text: String) {
        if !entry.sharedStorage {
            return ("exclamationmark.triangle", "Widget can't read the app's data. Open Ather Charge for help.")
        }
        if !entry.configured {
            return ("person.crop.circle", "Open Ather Charge to sign in.")
        }
        if entry.snapshot.needsSignIn {
            return ("person.crop.circle.badge.exclamationmark", "Sign in again in Ather Charge.")
        }
        if let error = entry.snapshot.lastError {
            return ("exclamationmark.triangle", error)
        }
        return ("arrow.clockwise", "Loading…")
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Ather Charge", systemImage: message.symbol)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: message.symbol)
            }
        case .accessoryRectangular:
            Label(message.text, systemImage: message.symbol)
                .font(.caption)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label("Ather Charge", systemImage: "scooter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: message.symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                Text(message.text)
                    .font(.caption)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
        }
    }
}
