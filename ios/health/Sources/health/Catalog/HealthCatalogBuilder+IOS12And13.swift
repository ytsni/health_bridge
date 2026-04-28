import HealthKit

/// iOS 12 and iOS 13 catalog registrations.
extension HealthCatalogBuilder {
    /// Registers sample and characteristic types introduced through iOS 13.
    mutating func initializeIOS12And13Types() {
        dataTypesDict[HealthConstants.HIGH_HEART_RATE_EVENT] =
            HKSampleType.categoryType(forIdentifier: .highHeartRateEvent)!
        dataTypesDict[HealthConstants.LOW_HEART_RATE_EVENT] =
            HKSampleType.categoryType(forIdentifier: .lowHeartRateEvent)!
        dataTypesDict[HealthConstants.IRREGULAR_HEART_RATE_EVENT] =
            HKSampleType.categoryType(forIdentifier: .irregularHeartRhythmEvent)!

        initializeIOS13Types()

        dataTypesDict[HealthConstants.HEADACHE_UNSPECIFIED] =
            HKSampleType.categoryType(forIdentifier: .headache)!
        dataTypesDict[HealthConstants.HEADACHE_NOT_PRESENT] =
            HKSampleType.categoryType(forIdentifier: .headache)!
        dataTypesDict[HealthConstants.HEADACHE_MILD] =
            HKSampleType.categoryType(forIdentifier: .headache)!
        dataTypesDict[HealthConstants.HEADACHE_MODERATE] =
            HKSampleType.categoryType(forIdentifier: .headache)!
        dataTypesDict[HealthConstants.HEADACHE_SEVERE] =
            HKSampleType.categoryType(forIdentifier: .headache)!
    }

    /// Registers concrete sample types that back the plugin's iOS 13 keys.
    private mutating func initializeIOS13Types() {
        dataTypesDict[HealthConstants.ACTIVE_ENERGY_BURNED] =
            HKSampleType.quantityType(forIdentifier: .activeEnergyBurned)!
        dataTypesDict[HealthConstants.APPLE_STAND_TIME] =
            HKSampleType.quantityType(forIdentifier: .appleStandTime)!
        dataTypesDict[HealthConstants.AUDIOGRAM] = HKSampleType.audiogramSampleType()
        dataTypesDict[HealthConstants.BASAL_ENERGY_BURNED] =
            HKSampleType.quantityType(forIdentifier: .basalEnergyBurned)!
        dataTypesDict[HealthConstants.BLOOD_GLUCOSE] =
            HKSampleType.quantityType(forIdentifier: .bloodGlucose)!
        dataTypesDict[HealthConstants.BLOOD_OXYGEN] =
            HKSampleType.quantityType(forIdentifier: .oxygenSaturation)!
        dataTypesDict[HealthConstants.RESPIRATORY_RATE] =
            HKSampleType.quantityType(forIdentifier: .respiratoryRate)!
        dataTypesDict[HealthConstants.PERIPHERAL_PERFUSION_INDEX] =
            HKSampleType.quantityType(forIdentifier: .peripheralPerfusionIndex)!
        dataTypesDict[HealthConstants.BLOOD_PRESSURE_DIASTOLIC] =
            HKSampleType.quantityType(forIdentifier: .bloodPressureDiastolic)!
        dataTypesDict[HealthConstants.BLOOD_PRESSURE_SYSTOLIC] =
            HKSampleType.quantityType(forIdentifier: .bloodPressureSystolic)!
        dataTypesDict[HealthConstants.BODY_FAT_PERCENTAGE] =
            HKSampleType.quantityType(forIdentifier: .bodyFatPercentage)!
        dataTypesDict[HealthConstants.LEAN_BODY_MASS] =
            HKSampleType.quantityType(forIdentifier: .leanBodyMass)!
        dataTypesDict[HealthConstants.BODY_MASS_INDEX] =
            HKSampleType.quantityType(forIdentifier: .bodyMassIndex)!
        dataTypesDict[HealthConstants.BODY_TEMPERATURE] =
            HKSampleType.quantityType(forIdentifier: .bodyTemperature)!
        initializeNutritionTypes()
        dataTypesDict[HealthConstants.ELECTRODERMAL_ACTIVITY] =
            HKSampleType.quantityType(forIdentifier: .electrodermalActivity)!
        dataTypesDict[HealthConstants.FORCED_EXPIRATORY_VOLUME] =
            HKSampleType.quantityType(forIdentifier: .forcedExpiratoryVolume1)!
        dataTypesDict[HealthConstants.HEART_RATE] =
            HKSampleType.quantityType(forIdentifier: .heartRate)!
        dataTypesDict[HealthConstants.HEART_RATE_VARIABILITY_SDNN] =
            HKSampleType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        dataTypesDict[HealthConstants.HEIGHT] =
            HKSampleType.quantityType(forIdentifier: .height)!
        dataTypesDict[HealthConstants.INSULIN_DELIVERY] =
            HKSampleType.quantityType(forIdentifier: .insulinDelivery)!
        dataTypesDict[HealthConstants.RESTING_HEART_RATE] =
            HKSampleType.quantityType(forIdentifier: .restingHeartRate)!
        dataTypesDict[HealthConstants.STEPS] = HKSampleType.quantityType(forIdentifier: .stepCount)!
        dataTypesDict[HealthConstants.WAIST_CIRCUMFERENCE] =
            HKSampleType.quantityType(forIdentifier: .waistCircumference)!
        dataTypesDict[HealthConstants.WALKING_HEART_RATE] =
            HKSampleType.quantityType(forIdentifier: .walkingHeartRateAverage)!
        dataTypesDict[HealthConstants.WEIGHT] = HKSampleType.quantityType(forIdentifier: .bodyMass)!
        dataTypesDict[HealthConstants.DISTANCE_WALKING_RUNNING] =
            HKSampleType.quantityType(forIdentifier: .distanceWalkingRunning)!
        dataTypesDict[HealthConstants.DISTANCE_SWIMMING] =
            HKSampleType.quantityType(forIdentifier: .distanceSwimming)!
        dataTypesDict[HealthConstants.DISTANCE_CYCLING] =
            HKSampleType.quantityType(forIdentifier: .distanceCycling)!
        dataTypesDict[HealthConstants.FLIGHTS_CLIMBED] =
            HKSampleType.quantityType(forIdentifier: .flightsClimbed)!
        dataTypesDict[HealthConstants.MINDFULNESS] =
            HKSampleType.categoryType(forIdentifier: .mindfulSession)!
        dataTypesDict[HealthConstants.SLEEP_AWAKE] =
            HKSampleType.categoryType(forIdentifier: .sleepAnalysis)!
        dataTypesDict[HealthConstants.SLEEP_DEEP] =
            HKSampleType.categoryType(forIdentifier: .sleepAnalysis)!
        dataTypesDict[HealthConstants.SLEEP_IN_BED] =
            HKSampleType.categoryType(forIdentifier: .sleepAnalysis)!
        dataTypesDict[HealthConstants.SLEEP_LIGHT] =
            HKSampleType.categoryType(forIdentifier: .sleepAnalysis)!
        dataTypesDict[HealthConstants.SLEEP_REM] =
            HKSampleType.categoryType(forIdentifier: .sleepAnalysis)!
        dataTypesDict[HealthConstants.SLEEP_ASLEEP] =
            HKSampleType.categoryType(forIdentifier: .sleepAnalysis)!
        dataTypesDict[HealthConstants.MENSTRUATION_FLOW] =
            HKSampleType.categoryType(forIdentifier: .menstrualFlow)!
        dataTypesDict[HealthConstants.EXERCISE_TIME] =
            HKSampleType.quantityType(forIdentifier: .appleExerciseTime)!
        dataTypesDict[HealthConstants.WORKOUT] = HKSampleType.workoutType()
        dataTypesDict[HealthConstants.NUTRITION] =
            HKSampleType.correlationType(forIdentifier: .food)!
        characteristicsTypesDict[HealthConstants.BIRTH_DATE] =
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        characteristicsTypesDict[HealthConstants.GENDER] =
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        characteristicsTypesDict[HealthConstants.BLOOD_TYPE] =
            HKObjectType.characteristicType(forIdentifier: .bloodType)!
    }

    /// Copies nutrition quantity types into the general sample registry.
    private mutating func initializeNutritionTypes() {
        for nutritionType in nutritionList {
            guard let quantityType = dataQuantityTypesDict[nutritionType] else { continue }
            dataTypesDict[nutritionType] = quantityType
        }
    }
}
