import HealthKit

/// Serializes `HKQuantitySample` values.
struct QuantitySampleSerializer: SampleSerializer {
    /// Returns whether `sample` is a quantity sample.
    func canSerialize(_ sample: HKSample) -> Bool {
        sample is HKQuantitySample
    }

    /// Returns the Flutter payload for `sample`.
    func serialize(_ sample: HKSample, context: SampleSerializationContext) -> [String: Any]? {
        guard let sample = sample as? HKQuantitySample else { return nil }

        var payload = SamplePayloadBuilder.basePayload(for: sample)
        payload["value"] = sample.quantity.doubleValue(for: context.unit ?? HKUnit.internationalUnit())
        payload["dataUnitKey"] = context.unit?.unitString
        payload["metadata"] = HealthUtilities.sanitizeMetadata(sample.metadata)
        return payload
    }
}
