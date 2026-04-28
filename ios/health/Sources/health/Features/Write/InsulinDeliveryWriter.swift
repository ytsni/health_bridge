#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Writes insulin delivery samples.
final class InsulinDeliveryWriter {
    /// Shared write dependencies and registries.
    private let context: HealthWriteContext

    /// Creates an insulin delivery writer backed by `context`.
    init(context: HealthWriteContext) {
        self.context = context
    }

    /// Writes the insulin delivery described by `request`.
    func write(_ request: InsulinDeliveryWriteRequest, result: @escaping FlutterResult) {
        let sample = HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .insulinDelivery)!,
            quantity: HKQuantity(unit: .internationalUnit(), doubleValue: request.units),
            start: request.startDate,
            end: request.endDate,
            metadata: [HKMetadataKeyInsulinDeliveryReason: request.reason]
        )

        HealthWriteResultHandler.save(
            sample,
            in: context.healthStore,
            failureCode: "WRITE_INSULIN_DELIVERY_FAILED",
            errorMessage: { "Error saving insulin delivery sample: \($0.localizedDescription)" },
            failureMessage: "HealthKit save returned false for insulin delivery sample.",
            successPayload: .uuidList,
            result: result
        )
    }
}
