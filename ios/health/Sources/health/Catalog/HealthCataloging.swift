import HealthKit

/// Shared read-only HealthKit catalog lookups used across the plugin.
protocol HealthCataloging {
    var dataTypesDict: [String: HKSampleType] { get }
    var dataQuantityTypesDict: [String: HKQuantityType] { get }
    var unitDict: [String: HKUnit] { get }
    var workoutActivityTypeMap: [String: HKWorkoutActivityType] { get }
    var characteristicsTypesDict: [String: HKCharacteristicType] { get }
    var nutritionList: [String] { get }
}

/// Translates workout activity types between plugin keys and HealthKit values.
protocol WorkoutActivityTypeCoding {
    func activityType(for pluginKey: String) -> HKWorkoutActivityType?
    func pluginKey(for activityType: HKWorkoutActivityType) -> String?
    func legacyName(for activityType: HKWorkoutActivityType) -> String
}

/// Composite catalog surface shared by plugin services.
typealias HealthCatalogProviding = HealthCataloging & WorkoutActivityTypeCoding
