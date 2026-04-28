import HealthKit

/// Ordered registry of sample serializers used by the read pipeline.
final class SampleSerializerRegistry: SampleSerializing {
    /// Serializers consulted in precedence order.
    private let serializers: [SampleSerializer]

    /// Creates a registry where earlier serializers take precedence over later ones.
    init(serializers: [SampleSerializer] = [
        QuantitySampleSerializer(),
        CategorySampleSerializer(),
        WorkoutSampleSerializer(),
        AudiogramSampleSerializer(),
        NutritionSampleSerializer(),
    ]) {
        self.serializers = serializers
    }

    /// Serializes each sample with the first serializer that claims it.
    func serialize(samples: [HKSample], context: SampleSerializationContext) -> [[String: Any]] {
        samples.compactMap { sample in
            serializers.first(where: { $0.canSerialize(sample) })?.serialize(sample, context: context)
        }
    }
}
