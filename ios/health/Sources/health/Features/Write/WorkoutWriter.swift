#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Writes workout samples with optional totals.
final class WorkoutWriter {
    /// Shared write dependencies and registries.
    private let context: HealthWriteContext

    /// Creates a workout writer backed by `context`.
    init(context: HealthWriteContext) {
        self.context = context
    }

    /// Writes the workout described by `request`.
    func write(_ request: WorkoutWriteRequest, result: @escaping FlutterResult) {
        guard let activityType = context.workoutActivityCoder.activityType(for: request.activityType) else {
            result(
                HealthWriteResultHandler.flutterError(
                    code: "ARGUMENT_ERROR",
                    message: "Missing or invalid activityType, startTime, or endTime"
                )
            )
            return
        }

        guard
            let totalEnergyBurned = quantity(
                for: request.totalEnergyBurned,
                unitKey: request.totalEnergyBurnedUnitKey,
                result: result
            ),
            let totalDistance = quantity(
                for: request.totalDistance,
                unitKey: request.totalDistanceUnitKey,
                result: result
            )
        else {
            return
        }

        let sample = HKWorkout(
            activityType: activityType,
            start: request.startDate,
            end: request.endDate,
            duration: request.endDate.timeIntervalSince(request.startDate),
            totalEnergyBurned: totalEnergyBurned,
            totalDistance: totalDistance,
            metadata: nil
        )

        HealthWriteResultHandler.save(
            sample,
            in: context.healthStore,
            failureCode: "WRITE_WORKOUT_FAILED",
            errorMessage: { "Error saving workout: \($0.localizedDescription)" },
            failureMessage: "HealthKit save returned false for workout.",
            successPayload: .uuidList,
            result: result
        )
    }

    /// Returns an `HKQuantity` converted from `value` and `unitKey`.
    private func quantity(
        for value: Double?,
        unitKey: String?,
        result: @escaping FlutterResult
    ) -> HKQuantity?? {
        guard let value else { return .some(nil) }
        guard let unitKey, let unit = context.unitDict[unitKey] else {
            if let unitKey {
                HealthWriteResultHandler.unsupportedUnit(unitKey, result: result)
            } else {
                result(
                    HealthWriteResultHandler.flutterError(
                        code: "ARGUMENT_ERROR",
                        message: "Missing or invalid workout unit."
                    )
                )
            }
            return nil
        }
        return HKQuantity(unit: unit, doubleValue: value)
    }
}
