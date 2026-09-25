import SwiftUI
import WidgetKit
import AtherKit

@MainActor
final class AppModel: ObservableObject {
    let store = SharedStore.shared
    let api = AtherAPI()

    @Published private(set) var settings: AppSettings
    @Published private(set) var snapshot: StatusSnapshot
    @Published private(set) var isRefreshing = false

    init() {
        settings = store.loadSettings()
        snapshot = store.loadSnapshot()
    }

    var isConfigured: Bool { settings.source != nil }

    func refresh() async {
        guard isConfigured, !isRefreshing else { return }
        isRefreshing = true
        snapshot = await StatusService(store: store, api: api).refresh(force: true)
        isRefreshing = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Sign-in

    func requestOTP(phone: String) async throws {
        try await api.requestOTP(phone: phone)
    }

    /// Returns the login token and the scooters on the account.
    func verifyOTP(phone: String, otp: String) async throws -> (token: String, scooters: [Scooter]) {
        let token = try await api.verifyOTP(phone: phone, otp: otp)
        let scooters = try await api.scooters(token: token)
        return (token, scooters)
    }

    /// Accepts a token copied from elsewhere, checking it against Ather first.
    func scooters(forPastedToken raw: String) async throws -> (token: String, scooters: [Scooter]) {
        let token = JWT.normalize(raw)
        guard JWT.isWellFormed(token) else { throw AtherError.invalidToken }
        if let expiry = JWT.expiry(token), expiry <= Date() { throw AtherError.tokenExpired }
        let scooters = try await api.scooters(token: token)
        return (token, scooters)
    }

    func scootersForCurrentLogin() async throws -> [Scooter] {
        guard let token = settings.token else { throw AtherError.notSignedIn }
        return try await api.scooters(token: token)
    }

    func finishSignIn(token: String, phone: String?, scooter: Scooter) async {
        let sameScooter = settings.source == .ather && settings.scooterId == scooter.id
        settings.source = .ather
        settings.token = token
        if let phone { settings.phone = try? AtherAPI.normalizePhone(phone) }
        settings.scooterId = scooter.id
        settings.scooterName = scooter.name
        store.saveSettings(settings)
        if !sameScooter {
            snapshot = StatusSnapshot()
            store.saveSnapshot(snapshot)
        }
        await refresh()
    }

    func startDemo() async {
        settings.source = .demo
        store.saveSettings(settings)
        snapshot = StatusSnapshot()
        store.saveSnapshot(snapshot)
        await refresh()
    }

    func signOut() {
        store.reset()
        settings = AppSettings()
        snapshot = StatusSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Field mapping

    func updateOverrides(_ overrides: FieldOverrides) async {
        settings.overrides = overrides
        store.saveSettings(settings)
        await refresh()
    }

    func rawTelemetry() -> Data? {
        store.loadRawTelemetry()
    }
}
