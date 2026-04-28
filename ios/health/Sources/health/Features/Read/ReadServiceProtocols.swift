import HealthKit

/// Specialized reader for characteristic values exposed outside sample queries.
protocol CharacteristicReading {
    func read(for request: SampleReadRequest) -> Result<[[String: Any]]?, Error>
}

/// Specialized reader for workout route samples.
protocol WorkoutRouteReading {
    func read(
        samples: [HKSample],
        includeManualEntries: Bool,
        singleResult: Bool,
        completion: @escaping (Result<Any?, Error>) -> Void
    )
}

/// Specialized reader for electrocardiogram samples.
protocol ECGReading {
    func read(
        samples: [HKSample],
        singleResult: Bool,
        completion: @escaping (Result<Any?, Error>) -> Void
    )
}

/// Shared registry interface used to serialize generic HealthKit samples.
protocol SampleSerializing {
    func serialize(samples: [HKSample], context: SampleSerializationContext) -> [[String: Any]]
}
