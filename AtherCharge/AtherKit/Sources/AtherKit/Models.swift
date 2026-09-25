import Foundation

/// What the scooter is doing with its battery right now.
public enum ChargingState: String, Codable, Sendable {
    case charging
    case full
    case notCharging
    case unknown
}

/// Where a charging state came from.
public enum StateSource: String, Codable, Sendable {
    /// A charging field in Ather's telemetry.
    case reported
    /// Worked out from how the battery percentage changed between readings.
    case inferred
    case none
}

/// Everything the app and the widget display.
public struct ChargeStatus: Codable, Equatable, Sendable {
    public var scooterName: String?
    /// State of charge, 0–100.
    public var soc: Double
    public var state: ChargingState
    public var stateSource: StateSource
    public var rangeKm: Double?
    /// When the battery is expected to reach 100%.
    public var fullAt: Date?
    /// True when `fullAt` was projected from the charge rate rather than reported by Ather.
    public var fullAtIsEstimate: Bool
    /// Observed charge rate in percentage points per hour.
    public var chargeRatePerHour: Double?
    public var frontTyrePsi: Double?
    public var rearTyrePsi: Double?
    /// Time of the scooter's own reading, when the telemetry includes one.
    public var reportedAt: Date?
    /// When this app fetched the reading.
    public var fetchedAt: Date
    public var isDemo: Bool

    public init(
        scooterName: String? = nil,
        soc: Double,
        state: ChargingState,
        stateSource: StateSource,
        rangeKm: Double? = nil,
        fullAt: Date? = nil,
        fullAtIsEstimate: Bool = false,
        chargeRatePerHour: Double? = nil,
        frontTyrePsi: Double? = nil,
        rearTyrePsi: Double? = nil,
        reportedAt: Date? = nil,
        fetchedAt: Date,
        isDemo: Bool = false
    ) {
        self.scooterName = scooterName
        self.soc = soc
        self.state = state
        self.stateSource = stateSource
        self.rangeKm = rangeKm
        self.fullAt = fullAt
        self.fullAtIsEstimate = fullAtIsEstimate
        self.chargeRatePerHour = chargeRatePerHour
        self.frontTyrePsi = frontTyrePsi
        self.rearTyrePsi = rearTyrePsi
        self.reportedAt = reportedAt
        self.fetchedAt = fetchedAt
        self.isDemo = isDemo
    }

    /// The best available time for "data as of".
    public var asOf: Date { reportedAt ?? fetchedAt }
}

/// One battery reading, kept to work out the charge rate.
public struct SocSample: Codable, Equatable, Sendable {
    public var time: Date
    public var soc: Double

    public init(time: Date, soc: Double) {
        self.time = time
        self.soc = soc
    }
}

/// Telemetry paths the parser used, shown in Settings so field mapping can be checked.
public struct DetectedFields: Codable, Equatable, Sendable {
    public var soc: String?
    public var charging: String?
    public var range: String?
    public var timeToFull: String?

    public init(soc: String? = nil, charging: String? = nil, range: String? = nil, timeToFull: String? = nil) {
        self.soc = soc
        self.charging = charging
        self.range = range
        self.timeToFull = timeToFull
    }
}

/// The last known status plus refresh bookkeeping. Written by whichever process refreshed last.
public struct StatusSnapshot: Codable, Equatable, Sendable {
    public var status: ChargeStatus?
    public var history: [SocSample]
    public var detected: DetectedFields?
    public var lastError: String?
    public var lastErrorAt: Date?
    /// True when the last failure means the Ather login has to be redone.
    public var needsSignIn: Bool
    public var lastAttemptAt: Date?

    public init(
        status: ChargeStatus? = nil,
        history: [SocSample] = [],
        detected: DetectedFields? = nil,
        lastError: String? = nil,
        lastErrorAt: Date? = nil,
        needsSignIn: Bool = false,
        lastAttemptAt: Date? = nil
    ) {
        self.status = status
        self.history = history
        self.detected = detected
        self.lastError = lastError
        self.lastErrorAt = lastErrorAt
        self.needsSignIn = needsSignIn
        self.lastAttemptAt = lastAttemptAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(ChargeStatus.self, forKey: .status)
        history = try c.decodeIfPresent([SocSample].self, forKey: .history) ?? []
        detected = try c.decodeIfPresent(DetectedFields.self, forKey: .detected)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        lastErrorAt = try c.decodeIfPresent(Date.self, forKey: .lastErrorAt)
        needsSignIn = try c.decodeIfPresent(Bool.self, forKey: .needsSignIn) ?? false
        lastAttemptAt = try c.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
    }
}

public enum DataSource: String, Codable, Sendable, CaseIterable {
    case ather
    case demo
}

public enum TimeUnit: String, Codable, Sendable, CaseIterable {
    case auto
    case seconds
    case minutes
    case hours
}

/// Manual telemetry paths, for when auto-detection picks the wrong field.
/// Paths are dot-separated and relative to `data.state.reported`, e.g. `bike.battery_soc`.
public struct FieldOverrides: Codable, Equatable, Sendable {
    public var socPath: String
    public var chargingPath: String
    public var rangePath: String
    public var timeToFullPath: String
    public var timeToFullUnit: TimeUnit

    public init(
        socPath: String = "",
        chargingPath: String = "",
        rangePath: String = "",
        timeToFullPath: String = "",
        timeToFullUnit: TimeUnit = .auto
    ) {
        self.socPath = socPath
        self.chargingPath = chargingPath
        self.rangePath = rangePath
        self.timeToFullPath = timeToFullPath
        self.timeToFullUnit = timeToFullUnit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        socPath = try c.decodeIfPresent(String.self, forKey: .socPath) ?? ""
        chargingPath = try c.decodeIfPresent(String.self, forKey: .chargingPath) ?? ""
        rangePath = try c.decodeIfPresent(String.self, forKey: .rangePath) ?? ""
        timeToFullPath = try c.decodeIfPresent(String.self, forKey: .timeToFullPath) ?? ""
        timeToFullUnit = try c.decodeIfPresent(TimeUnit.self, forKey: .timeToFullUnit) ?? .auto
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    /// nil until the user signs in or picks demo mode.
    public var source: DataSource?
    public var token: String?
    public var phone: String?
    public var scooterId: String?
    public var scooterName: String?
    public var overrides: FieldOverrides

    public init(
        source: DataSource? = nil,
        token: String? = nil,
        phone: String? = nil,
        scooterId: String? = nil,
        scooterName: String? = nil,
        overrides: FieldOverrides = FieldOverrides()
    ) {
        self.source = source
        self.token = token
        self.phone = phone
        self.scooterId = scooterId
        self.scooterName = scooterName
        self.overrides = overrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(DataSource.self, forKey: .source)
        token = try c.decodeIfPresent(String.self, forKey: .token)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        scooterId = try c.decodeIfPresent(String.self, forKey: .scooterId)
        scooterName = try c.decodeIfPresent(String.self, forKey: .scooterName)
        overrides = try c.decodeIfPresent(FieldOverrides.self, forKey: .overrides) ?? FieldOverrides()
    }
}
