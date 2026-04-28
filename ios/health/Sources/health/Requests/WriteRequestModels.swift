import Foundation

/// Typed payload for simple quantity and category writes.
struct GenericWriteRequest {
    /// The numeric value written to HealthKit.
    let value: Double

    /// The plugin data type key to write.
    let dataTypeKey: String

    /// The plugin unit key used to build the quantity.
    let dataUnitKey: String

    /// The sample start date.
    let startDate: Date

    /// The sample end date.
    let endDate: Date

    /// The plugin recording method value.
    let recordingMethod: Int
}

/// Typed payload for audiogram writes with left and right ear sensitivities.
struct AudiogramWriteRequest {
    /// The test frequencies in hertz.
    let frequencies: [Double]

    /// The left ear sensitivities aligned with `frequencies`.
    let leftEarSensitivities: [Double]

    /// The right ear sensitivities aligned with `frequencies`.
    let rightEarSensitivities: [Double]

    /// The sample start date.
    let startDate: Date

    /// The sample end date.
    let endDate: Date

    /// Optional metadata forwarded to HealthKit.
    let metadata: [String: Any]?
}

/// Typed payload for blood pressure writes, represented as paired quantity samples.
struct BloodPressureWriteRequest {
    /// The systolic reading in millimeters of mercury.
    let systolic: Double

    /// The diastolic reading in millimeters of mercury.
    let diastolic: Double

    /// The sample start date.
    let startDate: Date

    /// The sample end date.
    let endDate: Date

    /// The plugin recording method value.
    let recordingMethod: Int
}

/// Typed payload for nutrition writes.
struct MealWriteRequest {
    /// The meal display name.
    let name: String?

    /// The meal start date.
    let startDate: Date

    /// The meal end date.
    let endDate: Date

    /// The meal type metadata value.
    let mealType: String?

    /// The plugin recording method value.
    let recordingMethod: Int

    /// Nutrient values keyed by Flutter nutrient name.
    let nutrients: [String: Double]
}

/// Typed payload for insulin delivery writes.
struct InsulinDeliveryWriteRequest {
    /// The delivered insulin units.
    let units: Double

    /// The HealthKit insulin delivery reason value.
    let reason: NSNumber

    /// The sample start date.
    let startDate: Date

    /// The sample end date.
    let endDate: Date
}

/// Typed payload for menstruation flow writes.
struct MenstruationFlowWriteRequest {
    /// The menstrual flow category value.
    let value: Int

    /// The event date.
    let endDate: Date

    /// Whether the event starts a cycle.
    let isStartOfCycle: NSNumber

    /// The plugin recording method value.
    let recordingMethod: Int
}

/// Typed payload for mindfulness session writes.
struct MindfulnessWriteRequest {
    /// The session start date.
    let startDate: Date

    /// The session end date.
    let endDate: Date

    /// The plugin recording method value.
    let recordingMethod: Int
}

/// Typed payload for workout writes, including optional totals.
struct WorkoutWriteRequest {
    /// The plugin workout activity key.
    let activityType: String

    /// The workout start date.
    let startDate: Date

    /// The workout end date.
    let endDate: Date

    /// The optional total energy burned value.
    let totalEnergyBurned: Double?

    /// The plugin unit key for `totalEnergyBurned`.
    let totalEnergyBurnedUnitKey: String?

    /// The optional total distance value.
    let totalDistance: Double?

    /// The plugin unit key for `totalDistance`.
    let totalDistanceUnitKey: String?
}
