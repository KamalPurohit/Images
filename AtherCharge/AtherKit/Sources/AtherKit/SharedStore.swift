import Foundation

/// Finds the App Group the app and widget share.
///
/// Sideloading tools (AltStore, Sideloadly, …) re-sign the app and may rename its App Group,
/// e.g. by appending the signing team ID. The group actually granted is read from the
/// provisioning profile embedded in the bundle, so the app and widget still find each other.
public enum AppGroup {
    /// The App Group declared in the project's entitlements.
    public static let defaultIdentifier = "group.com.kamalpurohit.athercharge"

    public static func candidates(bundle: Bundle = .main) -> [String] {
        var list: [String] = []
        list += provisionedGroups(bundle: bundle)
        if let alt = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { list += alt }
        if let configured = bundle.object(forInfoDictionaryKey: "AtherAppGroup") as? String { list.append(configured) }
        list.append(defaultIdentifier)

        var seen = Set<String>()
        let unique = list.filter { seen.insert($0).inserted }
        // Prefer groups that belong to this app over any others the profile happens to grant.
        return unique.filter(isOurs) + unique.filter { !isOurs($0) }
    }

    static func isOurs(_ id: String) -> Bool {
        id.lowercased().contains("athercharge")
    }

    /// The first candidate this process is entitled to, with its container directory.
    public static func resolve(bundle: Bundle = .main) -> (identifier: String, url: URL)? {
        #if os(iOS)
        for id in candidates(bundle: bundle) {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return (id, url)
            }
        }
        #endif
        return nil
    }

    static func provisionedGroups(bundle: Bundle) -> [String] {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return [] }
        return appGroups(inProvisioningProfile: data)
    }

    /// Extracts `com.apple.security.application-groups` from a `.mobileprovision` file, which is
    /// a signed container around a plain XML property list.
    public static func appGroups(inProvisioningProfile data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return [] }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else { return [] }
        return groups
    }
}

/// JSON files in the shared App Group container, read and written by both the app and the widget.
public final class SharedStore: @unchecked Sendable {
    public static let shared = SharedStore()

    /// The App Group in use, or nil when the widget can't see the app's data.
    public let groupIdentifier: String?
    public let directory: URL

    public var isShared: Bool { groupIdentifier != nil }

    private init() {
        if let group = AppGroup.resolve() {
            groupIdentifier = group.identifier
            directory = group.url.appendingPathComponent("AtherCharge", isDirectory: true)
        } else {
            groupIdentifier = nil
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            directory = support.appendingPathComponent("AtherCharge", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A store in an arbitrary directory, for tests.
    public init(directory: URL) {
        groupIdentifier = nil
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    private var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
    private var telemetryURL: URL { directory.appendingPathComponent("telemetry.json") }

    public func loadSettings() -> AppSettings { read(AppSettings.self, from: settingsURL) ?? AppSettings() }
    public func saveSettings(_ settings: AppSettings) { write(settings, to: settingsURL) }

    public func loadSnapshot() -> StatusSnapshot { read(StatusSnapshot.self, from: snapshotURL) ?? StatusSnapshot() }
    public func saveSnapshot(_ snapshot: StatusSnapshot) { write(snapshot, to: snapshotURL) }

    /// The last raw telemetry response, for the field-mapping screen.
    public func loadRawTelemetry() -> Data? { try? Data(contentsOf: telemetryURL) }
    public func saveRawTelemetry(_ data: Data) { writeData(data, to: telemetryURL) }

    public func reset() {
        for url in [settingsURL, snapshotURL, telemetryURL] { try? FileManager.default.removeItem(at: url) }
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        writeData(data, to: url)
    }

    private func writeData(_ data: Data, to url: URL) {
        #if os(iOS)
        // The widget refreshes while the phone is locked, so the files must stay readable after
        // the first unlock.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: .atomic)
        #endif
    }
}
