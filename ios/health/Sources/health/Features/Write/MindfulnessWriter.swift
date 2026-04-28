#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Writes mindfulness session samples.
final class MindfulnessWriter {
    /// Shared write dependencies and registries.
    private let context: HealthWriteContext

    /// Creates a mindfulness writer backed by `context`.
    init(context: HealthWriteContext) {
        self.context = context
    }

    /// Writes the mindfulness session described by `request`.
    func write(_ request: MindfulnessWriteRequest, result: @escaping FlutterResult) throws {
        guard let categoryType = HKSampleType.categoryType(forIdentifier: .mindfulSession) else {
            throw PluginError(message: "Invalid Mindfulness Session Type")
        }

        let sample = HKCategorySample(
            type: categoryType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: request.startDate,
            end: request.endDate,
            metadata: context.userEnteredMetadata(recordingMethod: request.recordingMethod)
        )

        HealthWriteResultHandler.save(
            sample,
            in: context.healthStore,
            failureCode: "WRITE_MINDFULNESS_FAILED",
            errorMessage: { "Error saving mindfulness session: \($0.localizedDescription)" },
            failureMessage: "HealthKit save returned false for mindfulness session.",
            successPayload: .uuidList,
            result: result
        )
    }
}
