import Foundation

/// A decoded JSON document whose shape isn't known ahead of time.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    public static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    /// Follows a dot-separated path; numeric components index into arrays.
    public func value(at path: String) -> JSONValue? {
        let parts = path.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var current: JSONValue = self
        for part in parts {
            switch current {
            case .object(let o):
                guard let next = o[part] else { return nil }
                current = next
            case .array(let a):
                guard let i = Int(part), a.indices.contains(i) else { return nil }
                current = a[i]
            default:
                return nil
            }
        }
        return current
    }

    /// Every leaf value with its dot-separated path, sorted by path.
    public func leaves(maxDepth: Int = 12) -> [(path: String, value: JSONValue)] {
        var result: [(String, JSONValue)] = []
        func walk(_ v: JSONValue, _ prefix: String, _ depth: Int) {
            guard depth <= maxDepth else { return }
            switch v {
            case .object(let o):
                for key in o.keys.sorted() {
                    walk(o[key]!, prefix.isEmpty ? key : "\(prefix).\(key)", depth + 1)
                }
            case .array(let a):
                for (i, item) in a.enumerated() {
                    walk(item, prefix.isEmpty ? "\(i)" : "\(prefix).\(i)", depth + 1)
                }
            default:
                result.append((prefix, v))
            }
        }
        walk(self, "", 0)
        return result
    }

    /// A number, or a string that holds one. Booleans are not numbers.
    public var number: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n):
            return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// Short text for showing a leaf in the raw telemetry list.
    public var displayText: String {
        switch self {
        case .null: return "null"
        case .object: return "{…}"
        case .array: return "[…]"
        default: return stringValue ?? ""
        }
    }
}
