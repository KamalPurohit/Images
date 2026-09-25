import Foundation

/// Fetches the latest status for whichever source is configured and saves it for the app and widget.
public struct StatusService {
    public var store: SharedStore
    public var api: AtherAPI

    /// Several widgets reload at once; within this window they share one fetch.
    public static let minimumInterval: TimeInterval = 90

    public init(store: SharedStore = .shared, api: AtherAPI = AtherAPI()) {
        self.store = store
        self.api = api
    }

    /// Refreshes and returns the saved snapshot. Never throws: failures are recorded in
    /// `lastError` and the last good status is kept.
    @discardableResult
    public func refresh(force: Bool = false, now: Date = Date()) async -> StatusSnapshot {
        let settings = store.loadSettings()
        var snapshot = store.loadSnapshot()

        if !force, let last = snapshot.lastAttemptAt, now.timeIntervalSince(last) < Self.minimumInterval, now >= last {
            return snapshot
        }
        snapshot.lastAttemptAt = now

        switch settings.source {
        case nil:
            return snapshot

        case .demo?:
            snapshot.status = DemoData.status(at: now)
            snapshot.lastError = nil
            snapshot.needsSignIn = false

        case .ather?:
            do {
                guard let token = settings.token, !token.isEmpty, let scooterId = settings.scooterId else {
                    throw AtherError.notSignedIn
                }
                if let expiry = JWT.expiry(token), expiry <= now { throw AtherError.tokenExpired }

                let data = try await api.telemetry(token: token, scooterId: scooterId)
                store.saveRawTelemetry(data)
                let reading = try TelemetryParser(overrides: settings.overrides).parse(data, now: now)

                // A new login or a switch away from demo mode starts a fresh history.
                if snapshot.status?.isDemo == true { snapshot.history = [] }
                if let soc = reading.soc {
                    snapshot.history = ChargeEstimator.append(SocSample(time: reading.reportedAt ?? now, soc: soc), to: snapshot.history)
                }
                snapshot.status = ChargeEstimator.status(
                    from: reading, history: snapshot.history, scooterName: settings.scooterName, now: now
                )
                snapshot.detected = reading.detected
                snapshot.lastError = nil
                snapshot.lastErrorAt = nil
                snapshot.needsSignIn = false
            } catch {
                let atherError = error as? AtherError
                snapshot.lastError = atherError?.errorDescription ?? error.localizedDescription
                snapshot.lastErrorAt = now
                snapshot.needsSignIn = atherError?.needsSignIn ?? false
            }
        }

        store.saveSnapshot(snapshot)
        return snapshot
    }
}
