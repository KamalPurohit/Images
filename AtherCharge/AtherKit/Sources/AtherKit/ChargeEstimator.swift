import Foundation

/// Works out charging state, charge rate and time-to-full from successive battery readings,
/// for when the telemetry doesn't say so directly.
public enum ChargeEstimator {
    static let historyWindow: TimeInterval = 12 * 3600
    static let maxSamples = 72
    /// A rising streak with a gap longer than this is treated as two separate charges.
    static let maxGap: TimeInterval = 90 * 60
    /// A reading older than this is too stale to call the scooter "charging" from the trend alone.
    static let freshness: TimeInterval = 45 * 60

    /// Adds a reading, dropping duplicates and anything older than the history window.
    public static func append(_ sample: SocSample, to history: [SocSample]) -> [SocSample] {
        var result = history.filter { sample.time.timeIntervalSince($0.time) < historyWindow && $0.time < sample.time }
        if let last = result.last, last.soc == sample.soc, sample.time.timeIntervalSince(last.time) < 10 * 60 {
            // Same percentage a few minutes later: keep the history compact.
            return result
        }
        result.append(sample)
        if result.count > maxSamples { result.removeFirst(result.count - maxSamples) }
        return result
    }

    /// Charge rate in percentage points per hour over the latest rising stretch, or nil if the
    /// battery isn't rising.
    public static func risingRate(_ history: [SocSample]) -> Double? {
        guard history.count >= 2 else { return nil }
        var startIndex = history.count - 1
        while startIndex > 0 {
            let prev = history[startIndex - 1]
            let cur = history[startIndex]
            if prev.soc > cur.soc || cur.time.timeIntervalSince(prev.time) > maxGap { break }
            startIndex -= 1
        }
        let first = history[startIndex]
        let last = history[history.count - 1]
        let deltaSoc = last.soc - first.soc
        let deltaT = last.time.timeIntervalSince(first.time)
        guard deltaSoc >= 1, deltaT >= 5 * 60 else { return nil }
        let rate = deltaSoc / (deltaT / 3600)
        return (1...200).contains(rate) ? rate : nil
    }

    /// Combines a telemetry reading with the reading history into what the widget shows.
    public static func status(
        from reading: TelemetryReading,
        history: [SocSample],
        scooterName: String?,
        now: Date
    ) -> ChargeStatus {
        let soc = reading.soc ?? 0
        let sampleTime = reading.reportedAt ?? now
        let rate = risingRate(history)
        let latest = history.last

        var state: ChargingState
        var source: StateSource
        if let reported = reading.charging {
            state = reported
            source = .reported
        } else if let latest, rate != nil, now.timeIntervalSince(latest.time) < freshness {
            state = .charging
            source = .inferred
        } else if history.count >= 2, let latest, now.timeIntervalSince(latest.time) < freshness,
                  let previous = history.dropLast().last, previous.soc >= latest.soc,
                  latest.time.timeIntervalSince(previous.time) >= 15 * 60 {
            state = .notCharging
            source = .inferred
        } else {
            state = .unknown
            source = .none
        }
        if state == .charging && soc >= 99.5 { state = .full }

        var fullAt: Date?
        var estimate = false
        if state == .charging {
            if let minutes = reading.minutesToFull, minutes > 0 {
                fullAt = sampleTime.addingTimeInterval(minutes * 60)
            } else if let rate {
                fullAt = sampleTime.addingTimeInterval((100 - soc) / rate * 3600)
                estimate = true
            }
        }

        return ChargeStatus(
            scooterName: scooterName,
            soc: soc,
            state: state,
            stateSource: source,
            rangeKm: reading.rangeKm,
            fullAt: fullAt,
            fullAtIsEstimate: estimate,
            chargeRatePerHour: state == .charging ? rate : nil,
            frontTyrePsi: reading.frontTyrePsi,
            rearTyrePsi: reading.rearTyrePsi,
            reportedAt: reading.reportedAt,
            fetchedAt: now
        )
    }
}
