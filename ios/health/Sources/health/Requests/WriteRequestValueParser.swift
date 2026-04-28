import CoreLocation
import Foundation

/// Error emitted when Flutter write arguments cannot be decoded into a typed request.
enum WriteRequestParsingError: LocalizedError {
    case invalidArguments(String)

    /// The localized description for the parsing failure.
    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            message
        }
    }
}

/// Shared argument reader for the write request decoders.
struct WriteRequestValueParser {
    /// The raw Flutter arguments keyed by field name.
    let arguments: [String: Any]

    /// Creates a parser from the raw Flutter arguments dictionary.
    init(arguments: Any?) throws {
        guard let dictionary = arguments as? NSDictionary else {
            throw WriteRequestParsingError.invalidArguments("Invalid Arguments")
        }
        self.arguments = dictionary as? [String: Any] ?? [:]
    }

    /// Reads a required string value.
    func requiredString(_ key: String, message: String? = nil) throws -> String {
        guard let value = arguments[key] as? String else {
            throw WriteRequestParsingError.invalidArguments(message ?? "Missing or invalid \(key)")
        }
        return value
    }

    /// Reads an optional string value.
    func optionalString(_ key: String) -> String? {
        arguments[key] as? String
    }

    /// Reads a required numeric value and coerces it to `Double`.
    func requiredDouble(_ key: String, message: String? = nil) throws -> Double {
        guard let value = Self.doubleValue(arguments[key]) else {
            throw WriteRequestParsingError.invalidArguments(message ?? "Missing or invalid \(key)")
        }
        return value
    }

    /// Reads an optional numeric value and coerces it to `Double`.
    func optionalDouble(_ key: String) -> Double? {
        Self.doubleValue(arguments[key])
    }

    /// Reads a required numeric value and coerces it to `Int`.
    func requiredInt(_ key: String, message: String? = nil) throws -> Int {
        guard let value = Self.intValue(arguments[key]) else {
            throw WriteRequestParsingError.invalidArguments(message ?? "Missing or invalid \(key)")
        }
        return value
    }

    /// Reads a required numeric or boolean value as `NSNumber`.
    func requiredNSNumber(_ key: String, message: String? = nil) throws -> NSNumber {
        if let value = arguments[key] as? NSNumber {
            return value
        }
        if let value = arguments[key] as? Bool {
            return NSNumber(value: value)
        }
        throw WriteRequestParsingError.invalidArguments(message ?? "Missing or invalid \(key)")
    }

    /// Reads a required millisecond timestamp and converts it to `Date`.
    func requiredDate(_ key: String, message: String? = nil) throws -> Date {
        guard let milliseconds = Self.doubleValue(arguments[key]) else {
            throw WriteRequestParsingError.invalidArguments(message ?? "Missing or invalid \(key)")
        }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    /// Reads an optional metadata dictionary.
    func metadata(_ key: String) -> [String: Any]? {
        arguments[key] as? [String: Any]
    }

    /// Reads an array of route point dictionaries.
    func locationArray(_ key: String, message: String) throws -> [NSDictionary] {
        guard let values = arguments[key] as? [NSDictionary] else {
            throw WriteRequestParsingError.invalidArguments(message)
        }
        return values
    }

    /// Coerces Flutter argument values into `Double`.
    static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let doubleValue as Double:
            doubleValue
        case let intValue as Int:
            Double(intValue)
        case let stringValue as String:
            Double(stringValue)
        default:
            nil
        }
    }

    /// Coerces Flutter argument values into `Int`.
    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            number.intValue
        case let intValue as Int:
            intValue
        case let stringValue as String:
            Int(stringValue)
        default:
            nil
        }
    }

    /// Converts a millisecond timestamp into `Date`.
    static func dateValue(from value: Any?) -> Date? {
        guard let milliseconds = doubleValue(value) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
