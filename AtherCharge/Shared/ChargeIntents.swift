import AppIntents
import WidgetKit
import AtherKit

struct ChargeIntentError: Error, CustomLocalizedStringResourceConvertible {
    var message: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }
}

/// Used by the widget's refresh button.
struct RefreshChargeStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Ather Charge"
    static var description = IntentDescription("Fetches the latest battery and charging status of your Ather scooter.")

    func perform() async throws -> some IntentResult {
        await StatusService().refresh(force: true)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// For Siri and Shortcuts automations; returns the battery percentage.
struct GetChargeStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Ather Charge Status"
    static var description = IntentDescription("Returns your Ather scooter's battery percentage and says whether it is charging.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let snapshot = await StatusService().refresh(force: true)
        WidgetCenter.shared.reloadAllTimelines()
        guard let status = snapshot.status else {
            throw ChargeIntentError(message: snapshot.lastError ?? "Open Ather Charge and sign in first.")
        }
        return .result(value: Int(status.soc.rounded()), dialog: IntentDialog(stringLiteral: status.summary))
    }
}
