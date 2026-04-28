import HealthKit

/// Utilities for sanitizing HealthKit payloads and timestamps.
enum HealthUtilities {
    /// Returns Flutter-safe values from `metadata`.
    static func sanitizeMetadata(_ metadata: [String: Any]?) -> [String: Any] {
        guard let metadata else { return [:] }

        var sanitized = [String: Any]()

        for (key, value) in metadata {
            switch value {
            case let stringValue as String:
                sanitized[key] = stringValue
            case let numberValue as NSNumber:
                sanitized[key] = numberValue
            case let boolValue as Bool:
                sanitized[key] = boolValue
            case let arrayValue as [Any]:
                sanitized[key] = sanitizeArray(arrayValue)
            case let mapValue as [String: Any]:
                sanitized[key] = sanitizeMetadata(mapValue)
            default:
                continue
            }
        }

        return sanitized
    }

    /// Returns Flutter-safe values from `array`.
    static func sanitizeArray(_ array: [Any]) -> [Any] {
        var sanitizedArray: [Any] = []

        for value in array {
            switch value {
            case let stringValue as String:
                sanitizedArray.append(stringValue)
            case let numberValue as NSNumber:
                sanitizedArray.append(numberValue)
            case let boolValue as Bool:
                sanitizedArray.append(boolValue)
            case let arrayValue as [Any]:
                sanitizedArray.append(sanitizeArray(arrayValue))
            case let mapValue as [String: Any]:
                sanitizedArray.append(sanitizeMetadata(mapValue))
            default:
                continue
            }
        }

        return sanitizedArray
    }

    /// Returns a `Date` converted from epoch `milliseconds`.
    static func dateFromMilliseconds(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
