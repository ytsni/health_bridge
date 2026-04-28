#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Success payload shapes returned by write operations.
enum HealthWriteSuccessPayload {
    /// Returns a Boolean success value.
    case bool

    /// Returns the saved object's UUID in a single-item list.
    case uuidList
}

/// Helpers that bridge HealthKit write results back to Flutter.
enum HealthWriteResultHandler {
    /// Returns a Flutter error carrying `code` and `message`.
    static func flutterError(code: String, message: String) -> FlutterError {
        FlutterError(code: code, message: message, details: nil)
    }

    /// Returns an unsupported-data-type error for `type`.
    static func unsupportedDataType(_ type: String, result: @escaping FlutterResult) {
        result(
            flutterError(
                code: "UNSUPPORTED_DATA_TYPE",
                message: "Health data type '\(type)' not available on this iOS version."
            )
        )
    }

    /// Returns an unsupported-unit error for `unit`.
    static func unsupportedUnit(_ unit: String, result: @escaping FlutterResult) {
        result(
            flutterError(
                code: "UNSUPPORTED_UNIT",
                message: "Health data unit '\(unit)' not available on this iOS version."
            )
        )
    }

    /// Returns an unsupported-sample-type error for `type`.
    static func unsupportedSampleType(_ type: String, result: @escaping FlutterResult) {
        result(
            flutterError(
                code: "UNSUPPORTED_SAMPLE_TYPE",
                message: "Unsupported HealthKit sample type for '\(type)'."
            )
        )
    }

    /// Saves `object` and maps the completion into a Flutter result.
    static func save(
        _ object: HKObject,
        in healthStore: HKHealthStore,
        failureCode: String,
        errorMessage: @escaping (Error) -> String,
        failureMessage: String,
        successPayload: HealthWriteSuccessPayload,
        result: @escaping FlutterResult
    ) {
        healthStore.save(object) { success, error in
            DispatchQueue.main.async {
                if let error {
                    result(flutterError(code: failureCode, message: errorMessage(error)))
                    return
                }

                guard success else {
                    result(flutterError(code: failureCode, message: failureMessage))
                    return
                }

                switch successPayload {
                case .bool:
                    result(true)
                case .uuidList:
                    result([object.uuid.uuidString])
                }
            }
        }
    }
}
