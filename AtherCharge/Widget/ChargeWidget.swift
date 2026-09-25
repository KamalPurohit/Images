import WidgetKit
import SwiftUI
import AtherKit

@main
struct AtherChargeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChargeWidget()
    }
}

struct ChargeWidget: Widget {
    let kind = "AtherChargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChargeProvider()) { entry in
            ChargeWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Ather Charge")
        .description("Battery and charging status of your Ather scooter.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ChargeEntry: TimelineEntry {
    var date: Date
    var snapshot: StatusSnapshot
    var configured: Bool
    /// False when the widget can't reach the app's App Group, so it can never see the login.
    var sharedStorage: Bool

    var status: ChargeStatus? { snapshot.status }

    static func sample(at date: Date = Date()) -> ChargeEntry {
        ChargeEntry(date: date, snapshot: StatusSnapshot(status: DemoData.status(at: date)), configured: true, sharedStorage: true)
    }
}

struct ChargeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChargeEntry {
        .sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (ChargeEntry) -> Void) {
        if context.isPreview {
            completion(.sample())
        } else {
            completion(Self.currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChargeEntry>) -> Void) {
        Task {
            await StatusService().refresh()
            let entry = Self.currentEntry()
            completion(Timeline(entries: [entry], policy: .after(Self.nextRefresh(for: entry))))
        }
    }

    static func currentEntry(now: Date = Date()) -> ChargeEntry {
        let store = SharedStore.shared
        return ChargeEntry(
            date: now,
            snapshot: store.loadSnapshot(),
            configured: store.loadSettings().source != nil,
            sharedStorage: store.isShared
        )
    }

    /// iOS rations widget refreshes, so ask often only while charging.
    static func nextRefresh(for entry: ChargeEntry) -> Date {
        let now = entry.date
        guard entry.configured, !entry.snapshot.needsSignIn else { return now.addingTimeInterval(60 * 60) }
        guard let status = entry.status else { return now.addingTimeInterval(15 * 60) }
        if status.state == .charging {
            var next = now.addingTimeInterval(15 * 60)
            if let fullAt = status.fullAt, fullAt > now, fullAt < next { next = fullAt.addingTimeInterval(60) }
            return next
        }
        return now.addingTimeInterval(30 * 60)
    }
}

struct WidgetBackground: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            Color.clear
        default:
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .top, endPoint: .bottom)
        }
    }
}
