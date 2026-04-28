import HealthKit

/// Serializes `HKCategorySample` values.
struct CategorySampleSerializer: SampleSerializer {
    /// Returns whether `sample` is a category sample.
    func canSerialize(_ sample: HKSample) -> Bool {
        sample is HKCategorySample
    }

    /// Returns the Flutter payload for `sample`.
    func serialize(_ sample: HKSample, context: SampleSerializationContext) -> [String: Any]? {
        guard let sample = sample as? HKCategorySample,
              CategorySampleFilter.includes(sample.value, for: context.dataTypeKey)
        else {
            return nil
        }

        var payload = SamplePayloadBuilder.basePayload(for: sample)
        payload["value"] = sample.value
        payload["metadata"] = HealthUtilities.sanitizeMetadata(sample.metadata)
        return payload
    }
}
