import Foundation

/// Reads the claims of the JWT Ather issues at login. The signature isn't checked; this is only
/// used to show when the login expires.
public enum JWT {
    /// Strips whitespace, quotes and a leading "Bearer ".
    public static func normalize(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        return token
    }

    public static func isWellFormed(_ token: String) -> Bool {
        claims(token) != nil
    }

    public static func claims(_ token: String) -> [String: JSONValue]? {
        let parts = normalize(token).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              case .object(let o)? = try? JSONValue.decode(data) else { return nil }
        return o
    }

    public static func expiry(_ token: String) -> Date? {
        guard let exp = claims(token)?["exp"]?.number else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
