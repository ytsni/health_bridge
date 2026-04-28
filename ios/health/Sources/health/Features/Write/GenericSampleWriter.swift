#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Writes generic quantity and category samples.
final class GenericSampleWriter {
    /// Shared write dependencies and registries.
    private let context: HealthWriteContext

    /// Creates a generic writer backed by `context`.
    init(context: HealthWriteContext) {
        self.context = context
    }

    /// Writes the generic sample described by `request`.
    func write(_ request: GenericWriteRequest, result: @escaping FlutterResult) {
        guard let sampleType = context.dataTypesDict[request.dataTypeKey] else {
            HealthWriteResultHandler.unsupportedDataType(request.dataTypeKey, result: result)
            return
        }

        let metadata = context.userEnteredMetadata(recordingMethod: request.recordingMethod)
        let sample: HKObject

        if let categoryType = sampleType as? HKCategoryType {
            sample = HKCategorySample(
                type: categoryType,
                value: resolvedCategoryValue(for: request.dataTypeKey, rawValue: Int(request.value)),
                start: request.startDate,
                end: request.endDate,
                metadata: metadata
            )
        } else if let quantityType = sampleType as? HKQuantityType {
            guard let hkUnit = context.unitDict[request.dataUnitKey] else {
                HealthWriteResultHandler.unsupportedUnit(request.dataUnitKey, result: result)
                return
            }

            sample = HKQuantitySample(
                type: quantityType,
                quantity: HKQuantity(unit: hkUnit, doubleValue: request.value),
                start: request.startDate,
                end: request.endDate,
                metadata: metadata
            )
        } else {
            HealthWriteResultHandler.unsupportedSampleType(request.dataTypeKey, result: result)
            return
        }

        HealthWriteResultHandler.save(
            sample,
            in: context.healthStore,
            failureCode: "WRITE_DATA_FAILED",
            errorMessage: { "Error saving \(request.dataTypeKey) sample: \($0.localizedDescription)" },
            failureMessage: "HealthKit save returned false for '\(request.dataTypeKey)'.",
            successPayload: .uuidList,
            result: result
        )
    }

    /// Returns the HealthKit category value used for `type`.
    private func resolvedCategoryValue(for type: String, rawValue: Int) -> Int {
        switch type {
        case HealthConstants.SLEEP_IN_BED:
            HKCategoryValueSleepAnalysis.inBed.rawValue
        case HealthConstants.SLEEP_ASLEEP:
            if #available(iOS 16.0, macOS 13.0, *) {
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            } else {
                HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        case HealthConstants.SLEEP_AWAKE:
            HKCategoryValueSleepAnalysis.awake.rawValue
        case HealthConstants.SLEEP_LIGHT:
            if #available(iOS 16.0, *) {
                HKCategoryValueSleepAnalysis.asleepCore.rawValue
            } else {
                HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        case HealthConstants.SLEEP_DEEP:
            if #available(iOS 16.0, *) {
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            } else {
                HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        case HealthConstants.SLEEP_REM:
            if #available(iOS 16.0, *) {
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            } else {
                HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        default:
            rawValue
        }
    }
}
