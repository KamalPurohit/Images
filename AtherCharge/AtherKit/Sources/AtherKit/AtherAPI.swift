import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AtherError: LocalizedError, Equatable {
    case invalidPhone
    case invalidOTP
    case invalidToken
    case tokenExpired
    case notSignedIn
    case unauthorized(Int)
    case noScooter
    case http(Int, String?)
    case invalidResponse(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPhone: return "Enter the 10-digit mobile number registered with Ather."
        case .invalidOTP: return "Enter the OTP Ather sent you."
        case .invalidToken: return "That doesn't look like an Ather login token."
        case .tokenExpired: return "Your Ather login has expired. Sign in again."
        case .notSignedIn: return "Sign in to your Ather account."
        case .unauthorized(let code): return "Ather rejected the login (HTTP \(code)). Sign in again."
        case .noScooter: return "No scooter was found on this Ather account."
        case .http(let code, let message):
            if let message, !message.isEmpty { return "Ather returned HTTP \(code): \(message)" }
            return "Ather returned HTTP \(code)."
        case .invalidResponse(let detail): return "Unexpected response from Ather: \(detail)"
        case .network(let detail): return "Couldn't reach Ather: \(detail)"
        }
    }

    /// Whether the fix is to log in again.
    public var needsSignIn: Bool {
        switch self {
        case .tokenExpired, .notSignedIn, .unauthorized, .invalidToken: return true
        default: return false
        }
    }
}

public struct Scooter: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String?

    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return "Scooter …\(id.suffix(6))"
    }
}

/// Client for the private API used by Ather's own mobile app (host `cerberus.ather.io`).
///
/// This API is undocumented. The endpoints, headers and fields below follow the MIT-licensed
/// community project https://github.com/paritosh-08/ather-bot and can change without notice.
public struct AtherAPI {
    public static let defaultBaseURL = URL(string: "https://cerberus.ather.io")!
    static let appHeaders = [
        "Source": "ATHER_APP/11.3.0",
        "User-Agent": "Ktor client",
        "Accept": "application/json",
    ]

    public var baseURL: URL
    public var session: URLSession
    public var timeout: TimeInterval

    public init(baseURL: URL = AtherAPI.defaultBaseURL, session: URLSession = .shared, timeout: TimeInterval = 20) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    /// Returns the bare 10-digit Indian mobile number Ather expects.
    public static func normalizePhone(_ raw: String) throws -> String {
        var digits = raw.filter { $0.isASCII && $0.isNumber }
        if digits.count == 12, digits.hasPrefix("91") { digits.removeFirst(2) }
        if digits.count == 11, digits.hasPrefix("0") { digits.removeFirst() }
        guard digits.count == 10 else { throw AtherError.invalidPhone }
        return digits
    }

    // MARK: Login

    public func requestOTP(phone: String) async throws {
        let contact = try Self.normalizePhone(phone)
        _ = try await send(
            "POST", "/auth/v2/generate-login-otp",
            body: ["email": "", "contact_no": contact, "country_code": "IN"]
        )
    }

    /// Verifies the OTP and returns the login token (a JWT).
    public func verifyOTP(phone: String, otp: String) async throws -> String {
        let contact = try Self.normalizePhone(phone)
        let code = otp.filter { $0.isASCII && $0.isNumber }
        guard (4...8).contains(code.count) else { throw AtherError.invalidOTP }
        let json = try await send(
            "POST", "/auth/v2/verify-login-otp",
            body: [
                "email": "",
                "contact_no": contact,
                "userOtp": code,
                "is_mobile_login": "true",
                "country_code": "IN",
            ]
        )
        let candidates = ["token", "data.token", "access_token", "accessToken", "data.access_token", "data.accessToken"]
        for path in candidates {
            if let raw = json.value(at: path)?.stringValue {
                let token = JWT.normalize(raw)
                if !token.isEmpty { return token }
            }
        }
        throw AtherError.invalidResponse("the login response had no token")
    }

    // MARK: Vehicle

    public func scooters(token: String) async throws -> [Scooter] {
        let json = try await send("GET", "/api/v1/auth/user/scooters/firebase-dbs", token: token)
        guard case .array(let items)? = json["scooterDatabases"] else {
            throw AtherError.invalidResponse("no scooter list")
        }
        let nameKeys = ["nickname", "nick_name", "name", "scooter_name", "vehicle_name", "model", "model_name", "variant"]
        let scooters = items.compactMap { item -> Scooter? in
            guard let id = item["scooter"]?.stringValue, !id.isEmpty else { return nil }
            let name = nameKeys.lazy.compactMap { item[$0]?.stringValue }.first { !$0.isEmpty }
            return Scooter(id: id, name: name)
        }
        guard !scooters.isEmpty else { throw AtherError.noScooter }
        return scooters
    }

    /// Raw telemetry JSON for one scooter. Parse it with `TelemetryParser`.
    public func telemetry(token: String, scooterId: String) async throws -> Data {
        let (data, _) = try await sendRaw(
            "GET", "/api/v1/devices/shadows/telemetry",
            query: [URLQueryItem(name: "uuid", value: scooterId)],
            token: token
        )
        return data
    }

    // MARK: Transport

    private func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: String]? = nil,
        token: String? = nil
    ) async throws -> JSONValue {
        let (data, _) = try await sendRaw(method, path, query: query, body: body, token: token)
        if data.isEmpty { return .null }
        guard let json = try? JSONValue.decode(data) else {
            throw AtherError.invalidResponse("not JSON")
        }
        return json
    }

    private func sendRaw(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: String]? = nil,
        token: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = method
        for (name, value) in Self.appHeaders { request.setValue(value, forHTTPHeaderField: name) }
        if let token {
            request.setValue("Bearer \(JWT.normalize(token))", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AtherError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AtherError.invalidResponse("not HTTP")
        }
        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case let code where (code == 401 || code == 403) && token != nil:
            throw AtherError.unauthorized(code)
        default:
            throw AtherError.http(http.statusCode, Self.serverMessage(in: data))
        }
    }

    static func serverMessage(in data: Data) -> String? {
        guard let json = try? JSONValue.decode(data) else { return nil }
        for key in ["message", "error", "msg", "detail", "error_description", "data.message"] {
            if let text = json.value(at: key)?.stringValue, !text.isEmpty { return String(text.prefix(200)) }
        }
        return nil
    }
}
