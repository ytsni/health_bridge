#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Writes food correlations and nutrient samples.
final class MealWriter {
    /// Shared write dependencies and registries.
    private let context: HealthWriteContext

    /// Creates a meal writer backed by `context`.
    init(context: HealthWriteContext) {
        self.context = context
    }

    /// Writes the meal described by `request`.
    func write(_ request: MealWriteRequest, result: @escaping FlutterResult) {
        guard #available(iOS 15.0, *) else {
            result(
                HealthWriteResultHandler.flutterError(
                    code: "UNSUPPORTED_FEATURE",
                    message: "Meal correlation samples are only supported on iOS 15.0 and above."
                )
            )
            return
        }

        var metadata = context.userEnteredMetadata(recordingMethod: request.recordingMethod)
        metadata["HKFoodMeal"] = request.mealType ?? "UNKNOWN"
        if let name = request.name {
            metadata[HKMetadataKeyFoodType] = name
        }

        let nutritionSamples = Set<HKSample>(request.nutrients.compactMap { key, value in
            guard let identifier = HealthConstants.NUTRITION_KEYS[key] else { return nil }
            return HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: identifier)!,
                quantity: HKQuantity(unit: nutritionUnit(for: key), doubleValue: value),
                start: request.startDate,
                end: request.endDate,
                metadata: metadata
            )
        })

        let sample = HKCorrelation(
            type: HKCorrelationType.correlationType(forIdentifier: .food)!,
            start: request.startDate,
            end: request.endDate,
            objects: nutritionSamples,
            metadata: metadata
        )

        HealthWriteResultHandler.save(
            sample,
            in: context.healthStore,
            failureCode: "WRITE_MEAL_FAILED",
            errorMessage: { "Error saving meal sample: \($0.localizedDescription)" },
            failureMessage: "HealthKit save returned false for meal sample.",
            successPayload: .uuidList,
            result: result
        )
    }

    /// Returns the unit used to save nutrient `key`.
    private func nutritionUnit(for key: String) -> HKUnit {
        switch key {
        case "calories":
            .kilocalorie()
        case "water":
            .literUnit(with: .milli)
        default:
            .gram()
        }
    }
}
