import XCTest
@testable import AtherKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private func json(_ s: String) -> Data { Data(s.utf8) }

private func makeJWT(exp: TimeInterval) -> String {
    func b64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    return b64(#"{"alg":"HS256","typ":"JWT"}"#) + "." + b64(#"{"sub":"user","exp":\#(Int(exp))}"#) + ".c2lnbmF0dXJl"
}

final class JWTTests: XCTestCase {
    func testExpiryAndBearerPrefix() {
        let token = makeJWT(exp: 1_900_000_000)
        XCTAssertEqual(JWT.expiry("Bearer \(token)"), Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(JWT.normalize("  \"Bearer \(token)\"\n"), token)
        XCTAssertTrue(JWT.isWellFormed(token))
        XCTAssertFalse(JWT.isWellFormed("not-a-token"))
    }
}

final class PhoneTests: XCTestCase {
    func testNormalizesIndianNumbers() throws {
        XCTAssertEqual(try AtherAPI.normalizePhone("+91 98765 43210"), "9876543210")
        XCTAssertEqual(try AtherAPI.normalizePhone("09876543210"), "9876543210")
        XCTAssertEqual(try AtherAPI.normalizePhone("9876543210"), "9876543210")
        XCTAssertThrowsError(try AtherAPI.normalizePhone("12345"))
    }
}

final class TelemetryParserTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// The shape confirmed by the ather-bot project.
    func testKnownShape() throws {
        let data = json(#"""
        {"data":{"state":{"reported":{"bike":{"battery_soc":"42.5"},
          "tpms":{"front_tyre_pressure":29.5,"rear_tyre_pressure":"32"}}}}}
        """#)
        let r = try TelemetryParser().parse(data, now: now)
        XCTAssertEqual(r.soc, 42.5)
        XCTAssertEqual(r.detected.soc, "bike.battery_soc")
        XCTAssertEqual(r.frontTyrePsi, 29.5)
        XCTAssertEqual(r.rearTyrePsi, 32)
        XCTAssertNil(r.charging)
        XCTAssertNil(r.reportedAt)
    }

    func testDetectsChargingRangeTimeToFullAndTimestamp() throws {
        let data = json(#"""
        {"data":{"timestamp":1789999700,
          "state":{"reported":{
            "bike":{"battery_soc":61,"is_charging":true,"fast_charging_enabled":false,"estimated_range":64},
            "charger":{"time_to_full_sec":5400}}}}}
        """#)
        let r = try TelemetryParser().parse(data, now: now)
        XCTAssertEqual(r.soc, 61)
        XCTAssertEqual(r.charging, .charging)
        XCTAssertEqual(r.detected.charging, "bike.is_charging")
        XCTAssertEqual(r.rangeKm, 64)
        XCTAssertEqual(r.minutesToFull, 90)
        XCTAssertEqual(r.reportedAt, Date(timeIntervalSince1970: 1_789_999_700))
    }

    func testShadowMetadataTimestampWins() throws {
        let data = json(#"""
        {"data":{"timestamp":1789999999,
          "state":{"reported":{"bike":{"battery_soc":50}}},
          "metadata":{"reported":{"bike":{"battery_soc":{"timestamp":1789990000}}}}}}
        """#)
        XCTAssertEqual(try TelemetryParser().parse(data, now: now).reportedAt, Date(timeIntervalSince1970: 1_789_990_000))
    }

    func testChargingStatusStrings() {
        XCTAssertEqual(TelemetryParser.chargingState(from: .string("CHARGING")), .charging)
        XCTAssertEqual(TelemetryParser.chargingState(from: .string("NOT_CHARGING")), .notCharging)
        XCTAssertEqual(TelemetryParser.chargingState(from: .string("Discharging")), .notCharging)
        XCTAssertEqual(TelemetryParser.chargingState(from: .string("charger_disconnected")), .notCharging)
        XCTAssertEqual(TelemetryParser.chargingState(from: .string("CHARGING_COMPLETE")), .full)
        XCTAssertEqual(TelemetryParser.chargingState(from: .number(1)), .charging)
        XCTAssertEqual(TelemetryParser.chargingState(from: .bool(false)), .notCharging)
        XCTAssertNil(TelemetryParser.chargingState(from: .number(3)))
    }

    func testNestedChargingObject() throws {
        let data = json(#"{"data":{"state":{"reported":{"bike":{"battery_soc":70},"charging":{"status":"IN_PROGRESS"}}}}}"#)
        let r = try TelemetryParser().parse(data, now: now)
        XCTAssertEqual(r.charging, .charging)
        XCTAssertEqual(r.detected.charging, "charging.status")
    }

    func testOverridesTakePriority() throws {
        let data = json(#"""
        {"data":{"state":{"reported":{"bike":{"battery_soc":10,"custom_pct":77,"chg":"1","eta":2}}}}}
        """#)
        let overrides = FieldOverrides(socPath: "bike.custom_pct", chargingPath: "bike.chg", timeToFullPath: "bike.eta", timeToFullUnit: .hours)
        let r = try TelemetryParser(overrides: overrides).parse(data, now: now)
        XCTAssertEqual(r.soc, 77)
        XCTAssertEqual(r.charging, .charging)
        XCTAssertEqual(r.minutesToFull, 120)
    }

    func testMissingBatteryThrows() {
        XCTAssertThrowsError(try TelemetryParser().parse(json(#"{"data":{"state":{"reported":{"tpms":{}}}}}"#), now: now))
        XCTAssertThrowsError(try TelemetryParser().parse(json("<html>"), now: now))
    }

    func testTimeUnits() {
        XCTAssertEqual(TelemetryParser.minutes(from: 45, key: "ttf", unit: .auto), 45)
        XCTAssertEqual(TelemetryParser.minutes(from: 3600, key: "ttf", unit: .auto), 60)
        XCTAssertEqual(TelemetryParser.minutes(from: 120, key: "time_to_full_sec", unit: .auto), 2)
        XCTAssertEqual(TelemetryParser.minutes(from: 2, key: "time_to_full_hours", unit: .auto), 120)
    }
}

final class ChargeEstimatorTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testInfersChargingFromRisingBattery() {
        var history: [SocSample] = []
        history = ChargeEstimator.append(SocSample(time: t0, soc: 40), to: history)
        history = ChargeEstimator.append(SocSample(time: t0.addingTimeInterval(1800), soc: 50), to: history)
        let now = t0.addingTimeInterval(1800)
        let status = ChargeEstimator.status(from: TelemetryReading(soc: 50), history: history, scooterName: nil, now: now)
        XCTAssertEqual(status.state, .charging)
        XCTAssertEqual(status.stateSource, .inferred)
        XCTAssertEqual(status.chargeRatePerHour, 20)
        // 50 points left at 20 per hour.
        XCTAssertEqual(status.fullAt, now.addingTimeInterval(2.5 * 3600))
        XCTAssertTrue(status.fullAtIsEstimate)
    }

    func testInfersNotChargingFromFlatBattery() {
        let history = [SocSample(time: t0, soc: 60), SocSample(time: t0.addingTimeInterval(1200), soc: 60)]
        let status = ChargeEstimator.status(from: TelemetryReading(soc: 60), history: history, scooterName: nil, now: t0.addingTimeInterval(1200))
        XCTAssertEqual(status.state, .notCharging)
        XCTAssertEqual(status.stateSource, .inferred)
        XCTAssertNil(status.fullAt)
    }

    func testReportedTimeToFullIsUsed() {
        let reading = TelemetryReading(soc: 80, charging: .charging, minutesToFull: 30, reportedAt: t0)
        let status = ChargeEstimator.status(from: reading, history: [], scooterName: "Mine", now: t0.addingTimeInterval(60))
        XCTAssertEqual(status.state, .charging)
        XCTAssertEqual(status.stateSource, .reported)
        XCTAssertEqual(status.fullAt, t0.addingTimeInterval(1800))
        XCTAssertFalse(status.fullAtIsEstimate)
    }

    func testChargingAtHundredIsFull() {
        let status = ChargeEstimator.status(from: TelemetryReading(soc: 100, charging: .charging), history: [], scooterName: nil, now: t0)
        XCTAssertEqual(status.state, .full)
    }

    func testRateResetsAfterDischarge() {
        let history = [
            SocSample(time: t0, soc: 30),
            SocSample(time: t0.addingTimeInterval(1800), soc: 50),
            SocSample(time: t0.addingTimeInterval(3600), soc: 45),
            SocSample(time: t0.addingTimeInterval(5400), soc: 45),
        ]
        XCTAssertNil(ChargeEstimator.risingRate(history))
    }

    func testHistoryDropsOldAndDuplicateSamples() {
        var history = [SocSample(time: t0, soc: 10)]
        history = ChargeEstimator.append(SocSample(time: t0.addingTimeInterval(13 * 3600), soc: 20), to: history)
        XCTAssertEqual(history.count, 1)
        history = ChargeEstimator.append(SocSample(time: t0.addingTimeInterval(13 * 3600 + 60), soc: 20), to: history)
        XCTAssertEqual(history.count, 1)
        history = ChargeEstimator.append(SocSample(time: t0.addingTimeInterval(13 * 3600), soc: 20), to: history)
        XCTAssertEqual(history.count, 1)
    }
}

final class AppGroupTests: XCTestCase {
    func testReadsGroupsFromProvisioningProfile() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Entitlements</key><dict>
            <key>com.apple.security.application-groups</key>
            <array><string>group.com.kamalpurohit.athercharge.ABCDE12345</string></array>
          </dict>
        </dict></plist>
        """
        var data = Data([0x30, 0x82, 0x0B, 0xFF, 0x06, 0x09])
        data.append(Data(plist.utf8))
        data.append(Data([0xA0, 0x82, 0x00]))
        XCTAssertEqual(AppGroup.appGroups(inProvisioningProfile: data), ["group.com.kamalpurohit.athercharge.ABCDE12345"])
        XCTAssertEqual(AppGroup.appGroups(inProvisioningProfile: Data([1, 2, 3])), [])
    }
}

final class StoreTests: XCTestCase {
    func testRoundTripAndMissingKeys() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SharedStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertNil(store.loadSettings().source)
        var settings = AppSettings(source: .ather, token: "t", scooterId: "s1")
        settings.overrides.socPath = "bike.x"
        store.saveSettings(settings)
        XCTAssertEqual(store.loadSettings(), settings)

        let snapshot = StatusSnapshot(status: DemoData.status(at: Date(timeIntervalSince1970: 1_790_000_000)))
        store.saveSnapshot(snapshot)
        XCTAssertEqual(store.loadSnapshot(), snapshot)

        let older = try JSONDecoder().decode(AppSettings.self, from: json(#"{"source":"demo"}"#))
        XCTAssertEqual(older.source, .demo)
        XCTAssertEqual(older.overrides, FieldOverrides())
    }
}

final class DemoDataTests: XCTestCase {
    func testCycle() {
        let start = Date(timeIntervalSince1970: 3 * 3600 * 1000)
        let begin = DemoData.status(at: start)
        XCTAssertEqual(begin.soc, 20)
        XCTAssertEqual(begin.state, .charging)
        XCTAssertEqual(begin.fullAt, start.addingTimeInterval(2.5 * 3600))
        let end = DemoData.status(at: start.addingTimeInterval(2.75 * 3600))
        XCTAssertEqual(end.soc, 100)
        XCTAssertEqual(end.state, .full)
    }
}

// MARK: - Networking

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class StatusServiceTests: XCTestCase {
    var dir: URL!
    var store: SharedStore!
    var api: AtherAPI!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = SharedStore(directory: dir)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        api = AtherAPI(session: URLSession(configuration: config))
        StubURLProtocol.requests = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        StubURLProtocol.handler = nil
    }

    func testFetchesTelemetryWithAppHeaders() async {
        let token = makeJWT(exp: Date().timeIntervalSince1970 + 3600)
        store.saveSettings(AppSettings(source: .ather, token: token, scooterId: "abc-123", scooterName: "Rizta"))
        StubURLProtocol.handler = { _ in
            (200, json(#"{"data":{"state":{"reported":{"bike":{"battery_soc":"55","charging_status":"CHARGING"}}}}}"#))
        }

        let snapshot = await StatusService(store: store, api: api).refresh(force: true)

        XCTAssertNil(snapshot.lastError)
        XCTAssertEqual(snapshot.status?.soc, 55)
        XCTAssertEqual(snapshot.status?.state, .charging)
        XCTAssertEqual(snapshot.status?.scooterName, "Rizta")
        XCTAssertEqual(snapshot.detected?.charging, "bike.charging_status")
        XCTAssertNotNil(store.loadRawTelemetry())

        let request = StubURLProtocol.requests.first
        XCTAssertEqual(request?.url?.path, "/api/v1/devices/shadows/telemetry")
        XCTAssertEqual(request?.url?.query, "uuid=abc-123")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Source"), "ATHER_APP/11.3.0")
    }

    func testUnauthorizedKeepsLastStatusAndAsksForSignIn() async {
        let token = makeJWT(exp: Date().timeIntervalSince1970 + 3600)
        store.saveSettings(AppSettings(source: .ather, token: token, scooterId: "abc"))
        let previous = ChargeStatus(soc: 33, state: .notCharging, stateSource: .reported, fetchedAt: Date(timeIntervalSince1970: 1_790_000_000))
        store.saveSnapshot(StatusSnapshot(status: previous))
        StubURLProtocol.handler = { _ in (401, Data()) }

        let snapshot = await StatusService(store: store, api: api).refresh(force: true)

        XCTAssertEqual(snapshot.status, previous)
        XCTAssertTrue(snapshot.needsSignIn)
        XCTAssertNotNil(snapshot.lastError)
    }

    func testExpiredTokenSkipsNetwork() async {
        store.saveSettings(AppSettings(source: .ather, token: makeJWT(exp: 1_000_000_000), scooterId: "abc"))
        let snapshot = await StatusService(store: store, api: api).refresh(force: true)
        XCTAssertTrue(snapshot.needsSignIn)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testThrottlesRepeatedRefreshes() async {
        store.saveSettings(AppSettings(source: .demo))
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let first = await StatusService(store: store, api: api).refresh(now: now)
        XCTAssertNotNil(first.status)
        let second = await StatusService(store: store, api: api).refresh(now: now.addingTimeInterval(30))
        XCTAssertEqual(second.lastAttemptAt, first.lastAttemptAt)
    }

    func testLoginFlow() async throws {
        let token = makeJWT(exp: Date().timeIntervalSince1970 + 3600)
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/auth/v2/generate-login-otp": return (200, json(#"{"message":"OTP sent"}"#))
            case "/auth/v2/verify-login-otp": return (200, json(#"{"token":"Bearer \#(token)"}"#))
            case "/api/v1/auth/user/scooters/firebase-dbs":
                return (200, json(#"{"scooterDatabases":[{"scooter":"uuid-1","nickname":"Zippy"},{"scooter":"uuid-2"}]}"#))
            default: return (404, Data())
            }
        }
        try await api.requestOTP(phone: "+91 98765 43210")
        let received = try await api.verifyOTP(phone: "9876543210", otp: "1234")
        XCTAssertEqual(received, token)
        let scooters = try await api.scooters(token: received)
        XCTAssertEqual(scooters, [Scooter(id: "uuid-1", name: "Zippy"), Scooter(id: "uuid-2")])
    }

    func testOTPErrorsAreNotTreatedAsExpiredLogin() async {
        StubURLProtocol.handler = { _ in (403, json(#"{"message":"Too many attempts"}"#)) }
        do {
            try await api.requestOTP(phone: "9876543210")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AtherError, .http(403, "Too many attempts"))
        }
    }
}
