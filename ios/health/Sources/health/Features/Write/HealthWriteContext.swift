import HealthKit

/// Shared dependencies used by HealthKit write services.
struct HealthWriteContext {
    /// The HealthKit store that persists samples.
    let healthStore: HKHealthStore

    /// Sample types keyed by plugin data type.
    let dataTypesDict: [String: HKSampleType]

    /// Units keyed by plugin unit key.
    let unitDict: [String: HKUnit]

    /// Workout activity translator used for workout samples.
    let workoutActivityCoder: any WorkoutActivityTypeCoding

    /// Returns user-entered metadata for `recordingMethod`.
    func userEnteredMetadata(recordingMethod: Int) -> [String: Any] {
        let isManualEntry = recordingMethod == HealthConstants.RecordingMethod.manual.rawValue
        return [HKMetadataKeyWasUserEntered: NSNumber(value: isManualEntry)]
    }
}
