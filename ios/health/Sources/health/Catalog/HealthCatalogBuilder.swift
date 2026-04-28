import HealthKit

/// Mutable builder that assembles the shared `HealthCatalog` in staged passes.
///
/// The concrete registrations live in builder extensions so OS-specific additions
/// stay isolated while the final catalog remains a single immutable value.
struct HealthCatalogBuilder {
    /// Sample types keyed by plugin data type.
    var dataTypesDict: [String: HKSampleType] = [:]

    /// Quantity types keyed by plugin data type.
    var dataQuantityTypesDict: [String: HKQuantityType] = [:]

    /// Units keyed by plugin unit key.
    var unitDict: [String: HKUnit] = [:]

    /// Workout activity types keyed by plugin activity key.
    var workoutActivityTypeMap: [String: HKWorkoutActivityType] = [:]

    /// Characteristic types keyed by plugin data type.
    var characteristicsTypesDict: [String: HKCharacteristicType] = [:]

    /// Nutrition keys expanded from the umbrella nutrition permission.
    var nutritionList: [String] = []

    /// Populates every registry segment and seals the result into a catalog.
    mutating func build() -> HealthCatalog {
        initializeUnits()
        initializeWorkoutTypes()
        initializeNutritionList()
        initializeIOS11Types()
        initializeIOS12And13Types()
        initializeIOS14And16Types()

        return HealthCatalog(
            dataTypesDict: dataTypesDict,
            dataQuantityTypesDict: dataQuantityTypesDict,
            unitDict: unitDict,
            workoutActivityTypeMap: workoutActivityTypeMap,
            characteristicsTypesDict: characteristicsTypesDict,
            nutritionList: nutritionList
        )
    }
}
