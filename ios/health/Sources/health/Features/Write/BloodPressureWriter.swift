#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Writes blood pressure correlations.
final class BloodPressureWriter {
    /// Shared write dependencies and registries.
    private let context: HealthWriteContext

    /// Creates a blood pressure writer backed by `context`.
    init(context: HealthWriteContext) {
        self.context = context
    }

    /// Writes the blood pressure reading described by `request`.
    func write(_ request: BloodPressureWriteRequest, result: @escaping FlutterResult) {
        let metadata = context.userEnteredMetadata(recordingMethod: request.recordingMethod)
        let systolicSample = HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!,
            quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: request.systolic),
            start: request.startDate,
            end: request.endDate,
            metadata: metadata
        )
        let diastolicSample = HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
            quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: request.diastolic),
            start: request.startDate,
            end: request.endDate,
            metadata: metadata
        )
        let sample = HKCorrelation(
            type: HKCorrelationType.correlationType(forIdentifier: .bloodPressure)!,
            start: request.startDate,
            end: request.endDate,
            objects: [systolicSample, diastolicSample]
        )

        HealthWriteResultHandler.save(
            sample,
            in: context.healthStore,
            failureCode: "WRITE_BLOOD_PRESSURE_FAILED",
            errorMessage: { "Error saving blood pressure sample: \($0.localizedDescription)" },
            failureMessage: "HealthKit save returned false for blood pressure sample.",
            successPayload: .uuidList,
            result: result
        )
    }
}
