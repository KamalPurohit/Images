import Foundation

/// Values pulled out of one telemetry response.
public struct TelemetryReading: Equatable, Sendable {
    public var soc: Double?
    public var charging: ChargingState?
    public var rangeKm: Double?
    public var minutesToFull: Double?
    public var frontTyrePsi: Double?
    public var rearTyrePsi: Double?
    public var reportedAt: Date?
    public var detected: DetectedFields

    public init(
        soc: Double? = nil,
        charging: ChargingState? = nil,
        rangeKm: Double? = nil,
        minutesToFull: Double? = nil,
        frontTyrePsi: Double? = nil,
        rearTyrePsi: Double? = nil,
        reportedAt: Date? = nil,
        detected: DetectedFields = DetectedFields()
    ) {
        self.soc = soc
        self.charging = charging
        self.rangeKm = rangeKm
        self.minutesToFull = minutesToFull
        self.frontTyrePsi = frontTyrePsi
        self.rearTyrePsi = rearTyrePsi
        self.reportedAt = reportedAt
        self.detected = detected
    }
}

/// Turns Ather's device-shadow telemetry into a `TelemetryReading`.
///
/// Only `bike.battery_soc` and the `tpms` pressures are confirmed field names. Charging, range and
/// time-to-full are found by key name, and each can be pinned with `FieldOverrides`.
public struct TelemetryParser {
    public var overrides: FieldOverrides

    public init(overrides: FieldOverrides = FieldOverrides()) {
        self.overrides = overrides
    }

    static let socKeys = ["battery_soc", "soc", "state_of_charge", "battery_percentage", "battery_percent", "battery_level", "batterysoc", "batterypercentage"]
    static let chargingKeys = [
        "is_charging", "ischarging", "charging", "charging_status", "chargingstatus", "charging_state", "chargingstate",
        "charge_state", "chargestate", "charge_status", "chargestatus", "charger_connected", "is_charger_connected",
        "chargerconnected", "charger_plugged_in", "plugged_in", "is_plugged_in", "charger_status", "chargerstatus",
    ]
    /// Charging-looking booleans that describe settings or capabilities, not the current state.
    static let chargingNoise = ["enable", "allow", "support", "avail", "capab", "schedul", "limit", "fast", "mode", "notif", "alert", "remind", "count", "cycle", "last", "session"]
    static let rangeKeys = ["range", "estimated_range", "range_km", "predicted_range", "remaining_range", "range_left", "dte", "distance_to_empty", "estimatedrange", "rangekm", "rangeleft"]
    static let timeToFullFragments = ["time_to_full", "timetofull", "time_to_charge", "timetocharge", "ttf", "ttc", "charge_time_remaining", "charging_time_remaining", "remaining_charge_time", "remaining_charging_time", "time_remaining", "charge_eta", "charging_eta", "full_charge_time"]
    static let timestampKeys = ["timestamp", "ts", "updated_at", "updatedat", "last_updated", "lastupdated", "last_seen", "lastseen", "time", "reported_at", "reportedat"]

    public func parse(_ data: Data, now: Date = Date()) throws -> TelemetryReading {
        let json: JSONValue
        do {
            json = try JSONValue.decode(data)
        } catch {
            throw AtherError.invalidResponse("telemetry is not JSON")
        }
        return try parse(json, now: now)
    }

    public func parse(_ json: JSONValue, now: Date = Date()) throws -> TelemetryReading {
        let root = Self.reportedRoot(of: json)
        let leaves = root.leaves()
        var reading = TelemetryReading()

        // Battery percentage (required).
        if let (path, value) = findSOC(in: root, leaves: leaves) {
            reading.soc = min(max(value, 0), 100)
            reading.detected.soc = path
        } else {
            throw AtherError.invalidResponse("no battery percentage found. Set the path in Settings → Field mapping.")
        }

        // Charging state.
        if let (path, state) = findCharging(in: root, leaves: leaves) {
            reading.charging = state
            reading.detected.charging = path
        }

        // Range.
        if let path = nonEmpty(overrides.rangePath) {
            reading.rangeKm = root.value(at: path)?.number
            reading.detected.range = path
        } else if let hit = leaves.first(where: { Self.rangeKeys.contains(Self.lastKey($0.path)) && ($0.value.number.map { (0...500).contains($0) } ?? false) })
            ?? leaves.first(where: { Self.lastKey($0.path).contains("range") && !Self.lastKey($0.path).contains("mode") && ($0.value.number.map { (0...500).contains($0) } ?? false) }) {
            reading.rangeKm = hit.value.number
            reading.detected.range = hit.path
        }

        // Time to full.
        if let path = nonEmpty(overrides.timeToFullPath) {
            if let value = root.value(at: path)?.number {
                reading.minutesToFull = Self.minutes(from: value, key: Self.lastKey(path), unit: overrides.timeToFullUnit)
            }
            reading.detected.timeToFull = path
        } else if let hit = leaves.first(where: { leaf in
            let key = Self.lastKey(leaf.path)
            return Self.timeToFullFragments.contains(where: { key.contains($0) }) && (leaf.value.number.map { $0 >= 0 } ?? false)
        }) {
            reading.minutesToFull = Self.minutes(from: hit.value.number!, key: Self.lastKey(hit.path), unit: .auto)
            reading.detected.timeToFull = hit.path
        }

        // Tyres.
        reading.frontTyrePsi = root.value(at: "tpms.front_tyre_pressure")?.number
        reading.rearTyrePsi = root.value(at: "tpms.rear_tyre_pressure")?.number

        reading.reportedAt = Self.findTimestamp(in: json, root: root, socPath: reading.detected.soc, now: now)
        return reading
    }

    private func findSOC(in root: JSONValue, leaves: [(path: String, value: JSONValue)]) -> (String, Double)? {
        if let path = nonEmpty(overrides.socPath) {
            guard let value = root.value(at: path)?.number else { return nil }
            return (path, value)
        }
        if let value = root.value(at: "bike.battery_soc")?.number {
            return ("bike.battery_soc", value)
        }
        let percent: (JSONValue) -> Double? = { v in v.number.flatMap { (0...100).contains($0) ? $0 : nil } }
        for key in Self.socKeys {
            if let hit = leaves.first(where: { Self.lastKey($0.path) == key && percent($0.value) != nil }) {
                return (hit.path, percent(hit.value)!)
            }
        }
        if let hit = leaves.first(where: { Self.lastKey($0.path).contains("soc") && percent($0.value) != nil }) {
            return (hit.path, percent(hit.value)!)
        }
        return nil
    }

    private func findCharging(in root: JSONValue, leaves: [(path: String, value: JSONValue)]) -> (String, ChargingState)? {
        if let path = nonEmpty(overrides.chargingPath) {
            guard let value = root.value(at: path), let state = Self.chargingState(from: value) else { return nil }
            return (path, state)
        }
        for key in Self.chargingKeys {
            for leaf in leaves where Self.lastKey(leaf.path) == key {
                if let state = Self.chargingState(from: leaf.value) { return (leaf.path, state) }
            }
        }
        // A nested object such as `charging: { status: "CHARGING" }`.
        let nestedKeys = ["status", "state", "active", "is_active", "in_progress", "connected"]
        for leaf in leaves {
            let parts = leaf.path.lowercased().split(separator: ".")
            guard parts.count >= 2, nestedKeys.contains(String(parts[parts.count - 1])) else { continue }
            let parent = String(parts[parts.count - 2])
            guard parent.contains("charg"), !Self.chargingNoise.contains(where: { parent.contains($0) }) else { continue }
            if let state = Self.chargingState(from: leaf.value) { return (leaf.path, state) }
        }
        for leaf in leaves {
            let key = Self.lastKey(leaf.path)
            guard key.contains("charg"), !Self.chargingNoise.contains(where: { key.contains($0) }) else { continue }
            if case .bool(let b) = leaf.value { return (leaf.path, b ? .charging : .notCharging) }
        }
        return nil
    }

    // MARK: Helpers

    /// Ather wraps the reading as `data.state.reported`, like an AWS IoT device shadow.
    public static func reportedRoot(of json: JSONValue) -> JSONValue {
        for path in ["data.state.reported", "state.reported", "data.reported", "reported", "data.state", "data"] {
            if let v = json.value(at: path), case .object = v { return v }
        }
        return json
    }

    static func lastKey(_ path: String) -> String {
        (path.split(separator: ".").last.map(String.init) ?? path).lowercased()
    }

    private func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// Reads a charging flag or status text. Returns nil when the value can't be interpreted.
    public static func chargingState(from value: JSONValue) -> ChargingState? {
        switch value {
        case .bool(let b):
            return b ? .charging : .notCharging
        case .number(let n):
            if n == 0 { return .notCharging }
            if n == 1 { return .charging }
            return nil
        case .string(let raw):
            let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
            if s.isEmpty { return nil }
            if ["0", "false", "no", "off", "none", "na", "n/a"].contains(s) { return .notCharging }
            if ["1", "true", "yes", "on"].contains(s) { return .charging }
            let negative = ["not", "disconnect", "unplug", "plugged_out", "removed", "idle", "stop", "discharg", "fault", "error", "abort", "inactive"]
            if negative.contains(where: { s.contains($0) }) { return .notCharging }
            let done = ["complete", "full", "done", "finish"]
            if done.contains(where: { s.contains($0) }) { return .full }
            let active = ["charg", "progress", "start", "active", "connected", "plugged"]
            if active.contains(where: { s.contains($0) }) { return .charging }
            return nil
        default:
            return nil
        }
    }

    static func minutes(from value: Double, key: String, unit: TimeUnit) -> Double {
        switch unit {
        case .seconds: return value / 60
        case .minutes: return value
        case .hours: return value * 60
        case .auto:
            if key.hasSuffix("_ms") || key.contains("millis") { return value / 60_000 }
            if key.contains("sec") || key.hasSuffix("_s") { return value / 60 }
            if key.contains("min") { return value }
            if key.contains("hour") || key.hasSuffix("_h") || key.hasSuffix("_hr") || key.hasSuffix("_hrs") { return value * 60 }
            // A home charge never takes more than ~15 hours, so a larger number must be seconds.
            return value > 900 ? value / 60 : value
        }
    }

    static func date(from value: JSONValue, now: Date) -> Date? {
        var candidate: Date?
        if let n = value.number {
            if n > 1e12 { candidate = Date(timeIntervalSince1970: n / 1000) }
            else if n > 1e9 { candidate = Date(timeIntervalSince1970: n) }
        } else if case .string(let s) = value {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            candidate = iso.date(from: s)
            if candidate == nil {
                iso.formatOptions = [.withInternetDateTime]
                candidate = iso.date(from: s)
            }
        }
        guard let date = candidate else { return nil }
        // Ignore anything implausible: before Ather's connected scooters or in the future.
        let earliest = Date(timeIntervalSince1970: 1_514_764_800) // 2018-01-01
        guard date >= earliest, date <= now.addingTimeInterval(24 * 3600) else { return nil }
        return min(date, now)
    }

    static func findTimestamp(in json: JSONValue, root: JSONValue, socPath: String?, now: Date) -> Date? {
        var paths: [String] = []
        if let socPath {
            paths += ["data.metadata.reported.\(socPath).timestamp", "metadata.reported.\(socPath).timestamp"]
        }
        paths += ["data.timestamp", "timestamp", "data.state.reported.timestamp", "data.ts", "ts"]
        for path in paths {
            if let v = json.value(at: path), let d = date(from: v, now: now) { return d }
        }
        let dates = root.leaves().compactMap { leaf -> Date? in
            timestampKeys.contains(lastKey(leaf.path)) ? date(from: leaf.value, now: now) : nil
        }
        return dates.max()
    }
}
