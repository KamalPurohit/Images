import Foundation

/// A simulated scooter that charges from 20% to 100% over 2½ hours, then sits full for 30 minutes,
/// on repeat. Lets the widget be tried out without an Ather login.
public enum DemoData {
    static let cycle: TimeInterval = 3 * 3600
    static let chargeDuration: TimeInterval = 2.5 * 3600

    public static func status(at now: Date) -> ChargeStatus {
        let t = now.timeIntervalSince1970.truncatingRemainder(dividingBy: cycle)
        let soc: Double
        let state: ChargingState
        var fullAt: Date?
        var rate: Double?
        if t < chargeDuration {
            soc = (20 + 80 * t / chargeDuration).rounded(.down)
            state = .charging
            fullAt = now.addingTimeInterval(chargeDuration - t)
            rate = 80 / (chargeDuration / 3600)
        } else {
            soc = 100
            state = .full
        }
        return ChargeStatus(
            scooterName: "Demo 450X",
            soc: soc,
            state: state,
            stateSource: .reported,
            rangeKm: (soc * 1.05).rounded(),
            fullAt: fullAt,
            fullAtIsEstimate: false,
            chargeRatePerHour: rate,
            frontTyrePsi: 30,
            rearTyrePsi: 33,
            reportedAt: now.addingTimeInterval(-60),
            fetchedAt: now,
            isDemo: true
        )
    }
}
