#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Writes menstruation flow category samples.
final class MenstruationFlowWriter {
    /// Shared write dependencies and registries.
    private let context: HealthWriteContext

    /// Creates a menstruation flow writer backed by `context`.
    init(context: HealthWriteContext) {
        self.context = context
    }

    /// Writes the menstruation flow event described by `request`.
    func write(_ request: MenstruationFlowWriteRequest, result: @escaping FlutterResult) throws {
        guard let menstrualFlowType = HKCategoryValueMenstrualFlow(rawValue: request.value) else {
            throw PluginError(message: "Invalid Menstrual Flow Type")
        }
        guard let categoryType = HKSampleType.categoryType(forIdentifier: .menstrualFlow) else {
            throw PluginError(message: "Invalid Menstrual Flow Type")
        }

        var metadata = context.userEnteredMetadata(recordingMethod: request.recordingMethod)
        metadata[HKMetadataKeyMenstrualCycleStart] = request.isStartOfCycle

        let sample = HKCategorySample(
            type: categoryType,
            value: menstrualFlowType.rawValue,
            start: request.endDate,
            end: request.endDate,
            metadata: metadata
        )

        HealthWriteResultHandler.save(
            sample,
            in: context.healthStore,
            failureCode: "WRITE_MENSTRUATION_FLOW_FAILED",
            errorMessage: { "Error saving menstruation flow sample: \($0.localizedDescription)" },
            failureMessage: "HealthKit save returned false for menstruation flow sample.",
            successPayload: .uuidList,
            result: result
        )
    }
}
