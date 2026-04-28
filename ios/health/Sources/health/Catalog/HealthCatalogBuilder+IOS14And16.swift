import HealthKit

/// iOS 14 through iOS 16 catalog registrations.
extension HealthCatalogBuilder {
    /// Registers sample types and units introduced after iOS 13.
    mutating func initializeIOS14And16Types() {
        dataTypesDict[HealthConstants.ELECTROCARDIOGRAM] = HKSampleType.electrocardiogramType()
        dataTypesDict[HealthConstants.WALKING_SPEED] =
            HKSampleType.quantityType(forIdentifier: .walkingSpeed)
        unitDict[HealthConstants.VOLT] = HKUnit.volt()
        unitDict[HealthConstants.INCHES_OF_MERCURY] = HKUnit.inchesOfMercury()

        if #available(iOS 14.5, *) {
            dataTypesDict[HealthConstants.APPLE_MOVE_TIME] =
                HKSampleType.quantityType(forIdentifier: .appleMoveTime)!
        }

        if #available(iOS 16.0, *) {
            dataTypesDict[HealthConstants.ATRIAL_FIBRILLATION_BURDEN] =
                HKQuantityType.quantityType(forIdentifier: .atrialFibrillationBurden)!
            dataTypesDict[HealthConstants.WATER_TEMPERATURE] =
                HKQuantityType.quantityType(forIdentifier: .waterTemperature)!
            dataTypesDict[HealthConstants.UNDERWATER_DEPTH] =
                HKQuantityType.quantityType(forIdentifier: .underwaterDepth)!
            dataTypesDict[HealthConstants.UV_INDEX] =
                HKQuantityType.quantityType(forIdentifier: .uvExposure)!
            dataTypesDict[HealthConstants.SLEEP_WRIST_TEMPERATURE] =
                HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!

            dataQuantityTypesDict[HealthConstants.UV_INDEX] =
                HKQuantityType.quantityType(forIdentifier: .uvExposure)!
            dataQuantityTypesDict[HealthConstants.SLEEP_WRIST_TEMPERATURE] =
                HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!
        }
    }
}
