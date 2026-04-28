import HealthKit

/// Shared context passed to serializers after request decoding and catalog lookup.
struct SampleSerializationContext {
    /// Plugin data type key that selected the read path.
    let dataTypeKey: String
    /// Optional unit resolved from the request for quantity conversion.
    let unit: HKUnit?
    /// Workout activity translator used to map HealthKit workouts back to plugin payloads.
    let workoutActivityCoder: any WorkoutActivityTypeCoding
}

/// Strategy for converting an `HKSample` into the dictionary payload returned to Flutter.
///
/// The serializer registry picks the first serializer whose `canSerialize(_:)` returns
/// `true`, then calls `serialize(_:context:)` to build the payload.
protocol SampleSerializer {
    /// Returns `true` when the serializer owns the sample subtype.
    func canSerialize(_ sample: HKSample) -> Bool

    /// Builds the Flutter-facing payload for a supported sample.
    ///
    /// Returning `nil` drops the sample from the serialized result.
    func serialize(_ sample: HKSample, context: SampleSerializationContext) -> [String: Any]?
}
