import HealthKit

/// Serializes `HKWorkout` values.
struct WorkoutSampleSerializer: SampleSerializer {
    /// Returns whether `sample` is a workout.
    func canSerialize(_ sample: HKSample) -> Bool {
        sample is HKWorkout
    }

    /// Returns the Flutter payload for `sample`.
    func serialize(_ sample: HKSample, context: SampleSerializationContext) -> [String: Any]? {
        guard let sample = sample as? HKWorkout else { return nil }

        var payload = SamplePayloadBuilder.basePayload(for: sample)
        payload["workoutActivityType"] = context.workoutActivityCoder.pluginKey(for: sample.workoutActivityType)
        payload["totalEnergyBurned"] = sample.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie())
        payload["totalEnergyBurnedUnit"] = HealthConstants.KILOCALORIE
        payload["totalDistance"] = sample.totalDistance?.doubleValue(for: HKUnit.meter())
        payload["totalDistanceUnit"] = HealthConstants.METER
        payload["workout_type"] = context.workoutActivityCoder.legacyName(for: sample.workoutActivityType)
        payload["total_distance"] = sample.totalDistance.map { Int($0.doubleValue(for: HKUnit.meter())) } ?? 0
        payload["total_energy_burned"] = sample.totalEnergyBurned.map {
            Int($0.doubleValue(for: HKUnit.kilocalorie()))
        } ?? 0
        return payload
    }
}
