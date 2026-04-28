import HealthKit

/// Serializes food correlations and nutrient quantities.
struct NutritionSampleSerializer: SampleSerializer {
    /// Returns whether `sample` is a food correlation.
    func canSerialize(_ sample: HKSample) -> Bool {
        sample is HKCorrelation
    }

    /// Returns the Flutter payload for `sample`.
    func serialize(_ sample: HKSample, context _: SampleSerializationContext) -> [String: Any]? {
        guard let sample = sample as? HKCorrelation,
              let firstQuantity = sample.objects.first(where: { $0 is HKQuantitySample }) as? HKQuantitySample
        else {
            return nil
        }

        var payload = SamplePayloadBuilder.basePayload(for: firstQuantity)
        payload["name"] = sample.metadata?[HKMetadataKeyFoodType] as? String
        payload["meal_type"] = sample.metadata?["HKFoodMeal"]

        for object in sample.objects {
            guard let quantitySample = object as? HKQuantitySample else { continue }

            for (key, identifier) in HealthConstants.NUTRITION_KEYS where
                quantitySample.quantityType == HKObjectType.quantityType(forIdentifier: identifier)
            {
                let unit: HKUnit = switch key {
                case "calories": .kilocalorie()
                case "water": .literUnit(with: .milli)
                default: .gram()
                }
                payload[key] = quantitySample.quantity.doubleValue(for: unit)
            }
        }

        return payload
    }
}
