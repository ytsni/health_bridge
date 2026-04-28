import HealthKit

/// Immutable registry of HealthKit types and plugin-facing keys.
///
/// Services read from this catalog instead of reconstructing unit or type mappings
/// on demand. That keeps availability rules and key translation centralized.
final class HealthCatalog: HealthCatalogProviding {
    /// Maps plugin data type keys to sample types used by read, write, and delete flows.
    let dataTypesDict: [String: HKSampleType]
    /// Maps plugin data type keys to quantity types that support statistics queries.
    let dataQuantityTypesDict: [String: HKQuantityType]
    /// Maps plugin unit keys to the matching `HKUnit`.
    let unitDict: [String: HKUnit]
    /// Maps plugin workout activity keys to `HKWorkoutActivityType`.
    let workoutActivityTypeMap: [String: HKWorkoutActivityType]
    /// Maps plugin data type keys to characteristic types.
    let characteristicsTypesDict: [String: HKCharacteristicType]
    /// Lists nutrition keys expanded from umbrella nutrition operations.
    let nutritionList: [String]

    /// Shared workout activity translator derived from the catalog map.
    private let workoutActivityCoder: WorkoutActivityTypeCoder

    /// Creates a catalog snapshot from the builder output.
    init(
        dataTypesDict: [String: HKSampleType],
        dataQuantityTypesDict: [String: HKQuantityType],
        unitDict: [String: HKUnit],
        workoutActivityTypeMap: [String: HKWorkoutActivityType],
        characteristicsTypesDict: [String: HKCharacteristicType],
        nutritionList: [String]
    ) {
        self.dataTypesDict = dataTypesDict
        self.dataQuantityTypesDict = dataQuantityTypesDict
        self.unitDict = unitDict
        self.workoutActivityTypeMap = workoutActivityTypeMap
        self.characteristicsTypesDict = characteristicsTypesDict
        self.nutritionList = nutritionList
        workoutActivityCoder = WorkoutActivityTypeCoder(activityTypesByPluginKey: workoutActivityTypeMap)
    }

    /// Builds the default catalog for the current plugin runtime.
    static func current() -> HealthCatalog {
        var builder = HealthCatalogBuilder()
        return builder.build()
    }

    /// Resolves the HealthKit workout type used for `pluginKey`.
    func activityType(for pluginKey: String) -> HKWorkoutActivityType? {
        workoutActivityCoder.activityType(for: pluginKey)
    }

    /// Resolves the canonical plugin workout key for `activityType`.
    func pluginKey(for activityType: HKWorkoutActivityType) -> String? {
        workoutActivityCoder.pluginKey(for: activityType)
    }

    /// Resolves the legacy lower-camel workout string for `activityType`.
    func legacyName(for activityType: HKWorkoutActivityType) -> String {
        workoutActivityCoder.legacyName(for: activityType)
    }
}
