import HealthKit

/// Shared unit, nutrition, and workout registrations.
extension HealthCatalogBuilder {
    /// Registers plugin unit keys with their matching `HKUnit`.
    mutating func initializeUnits() {
        unitDict[HealthConstants.GRAM] = HKUnit.gram()
        unitDict[HealthConstants.KILOGRAM] = HKUnit.gramUnit(with: .kilo)
        unitDict[HealthConstants.OUNCE] = HKUnit.ounce()
        unitDict[HealthConstants.POUND] = HKUnit.pound()
        unitDict[HealthConstants.STONE] = HKUnit.stone()
        unitDict[HealthConstants.METER] = HKUnit.meter()
        unitDict[HealthConstants.INCH] = HKUnit.inch()
        unitDict[HealthConstants.FOOT] = HKUnit.foot()
        unitDict[HealthConstants.YARD] = HKUnit.yard()
        unitDict[HealthConstants.MILE] = HKUnit.mile()
        unitDict[HealthConstants.LITER] = HKUnit.liter()
        unitDict[HealthConstants.MILLILITER] = HKUnit.literUnit(with: .milli)
        unitDict[HealthConstants.FLUID_OUNCE_US] = HKUnit.fluidOunceUS()
        unitDict[HealthConstants.FLUID_OUNCE_IMPERIAL] = HKUnit.fluidOunceImperial()
        unitDict[HealthConstants.CUP_US] = HKUnit.cupUS()
        unitDict[HealthConstants.CUP_IMPERIAL] = HKUnit.cupImperial()
        unitDict[HealthConstants.PINT_US] = HKUnit.pintUS()
        unitDict[HealthConstants.PINT_IMPERIAL] = HKUnit.pintImperial()
        unitDict[HealthConstants.PASCAL] = HKUnit.pascal()
        unitDict[HealthConstants.MILLIMETER_OF_MERCURY] = HKUnit.millimeterOfMercury()
        unitDict[HealthConstants.CENTIMETER_OF_WATER] = HKUnit.centimeterOfWater()
        unitDict[HealthConstants.ATMOSPHERE] = HKUnit.atmosphere()
        unitDict[HealthConstants.DECIBEL_A_WEIGHTED_SOUND_PRESSURE_LEVEL] =
            HKUnit.decibelAWeightedSoundPressureLevel()
        unitDict[HealthConstants.SECOND] = HKUnit.second()
        unitDict[HealthConstants.MILLISECOND] = HKUnit.secondUnit(with: .milli)
        unitDict[HealthConstants.MINUTE] = HKUnit.minute()
        unitDict[HealthConstants.HOUR] = HKUnit.hour()
        unitDict[HealthConstants.DAY] = HKUnit.day()
        unitDict[HealthConstants.JOULE] = HKUnit.joule()
        unitDict[HealthConstants.KILOCALORIE] = HKUnit.kilocalorie()
        unitDict[HealthConstants.LARGE_CALORIE] = HKUnit.largeCalorie()
        unitDict[HealthConstants.SMALL_CALORIE] = HKUnit.smallCalorie()
        unitDict[HealthConstants.DEGREE_CELSIUS] = HKUnit.degreeCelsius()
        unitDict[HealthConstants.DEGREE_FAHRENHEIT] = HKUnit.degreeFahrenheit()
        unitDict[HealthConstants.KELVIN] = HKUnit.kelvin()
        unitDict[HealthConstants.DECIBEL_HEARING_LEVEL] = HKUnit.decibelHearingLevel()
        unitDict[HealthConstants.HERTZ] = HKUnit.hertz()
        unitDict[HealthConstants.SIEMEN] = HKUnit.siemen()
        unitDict[HealthConstants.INTERNATIONAL_UNIT] = HKUnit.internationalUnit()
        unitDict[HealthConstants.COUNT] = HKUnit.count()
        unitDict[HealthConstants.PERCENT] = HKUnit.percent()
        unitDict[HealthConstants.BEATS_PER_MINUTE] = HKUnit(from: "count/min")
        unitDict[HealthConstants.RESPIRATIONS_PER_MINUTE] = HKUnit(from: "count/min")
        unitDict[HealthConstants.MILLIGRAM_PER_DECILITER] = HKUnit(from: "mg/dL")
        unitDict[HealthConstants.METER_PER_SECOND] = HKUnit(from: "m/s")
        unitDict[HealthConstants.UNKNOWN_UNIT] = HKUnit(from: "")
        unitDict[HealthConstants.NO_UNIT] = HKUnit(from: "")
    }

    /// Registers the nutrition keys expanded from umbrella operations.
    mutating func initializeNutritionList() {
        nutritionList = [
            HealthConstants.DIETARY_ENERGY_CONSUMED,
            HealthConstants.DIETARY_CARBS_CONSUMED,
            HealthConstants.DIETARY_PROTEIN_CONSUMED,
            HealthConstants.DIETARY_FATS_CONSUMED,
            HealthConstants.DIETARY_CAFFEINE,
            HealthConstants.DIETARY_FIBER,
            HealthConstants.DIETARY_SUGAR,
            HealthConstants.DIETARY_FAT_MONOUNSATURATED,
            HealthConstants.DIETARY_FAT_POLYUNSATURATED,
            HealthConstants.DIETARY_FAT_SATURATED,
            HealthConstants.DIETARY_CHOLESTEROL,
            HealthConstants.DIETARY_VITAMIN_A,
            HealthConstants.DIETARY_THIAMIN,
            HealthConstants.DIETARY_RIBOFLAVIN,
            HealthConstants.DIETARY_NIACIN,
            HealthConstants.DIETARY_PANTOTHENIC_ACID,
            HealthConstants.DIETARY_VITAMIN_B6,
            HealthConstants.DIETARY_BIOTIN,
            HealthConstants.DIETARY_VITAMIN_B12,
            HealthConstants.DIETARY_VITAMIN_C,
            HealthConstants.DIETARY_VITAMIN_D,
            HealthConstants.DIETARY_VITAMIN_E,
            HealthConstants.DIETARY_VITAMIN_K,
            HealthConstants.DIETARY_FOLATE,
            HealthConstants.DIETARY_CALCIUM,
            HealthConstants.DIETARY_CHLORIDE,
            HealthConstants.DIETARY_IRON,
            HealthConstants.DIETARY_MAGNESIUM,
            HealthConstants.DIETARY_PHOSPHORUS,
            HealthConstants.DIETARY_POTASSIUM,
            HealthConstants.DIETARY_SODIUM,
            HealthConstants.DIETARY_ZINC,
            HealthConstants.DIETARY_WATER,
            HealthConstants.DIETARY_CHROMIUM,
            HealthConstants.DIETARY_COPPER,
            HealthConstants.DIETARY_IODINE,
            HealthConstants.DIETARY_MANGANESE,
            HealthConstants.DIETARY_MOLYBDENUM,
            HealthConstants.DIETARY_SELENIUM,
        ]
    }

    /// Registers plugin workout keys with their matching `HKWorkoutActivityType`.
    mutating func initializeWorkoutTypes() {
        workoutActivityTypeMap["ARCHERY"] = .archery
        workoutActivityTypeMap["BOWLING"] = .bowling
        workoutActivityTypeMap["FENCING"] = .fencing
        workoutActivityTypeMap["GYMNASTICS"] = .gymnastics
        workoutActivityTypeMap["TRACK_AND_FIELD"] = .trackAndField
        workoutActivityTypeMap["AMERICAN_FOOTBALL"] = .americanFootball
        workoutActivityTypeMap["AUSTRALIAN_FOOTBALL"] = .australianFootball
        workoutActivityTypeMap["BASEBALL"] = .baseball
        workoutActivityTypeMap["BASKETBALL"] = .basketball
        workoutActivityTypeMap["CRICKET"] = .cricket
        workoutActivityTypeMap["DISC_SPORTS"] = .discSports
        workoutActivityTypeMap["HANDBALL"] = .handball
        workoutActivityTypeMap["HOCKEY"] = .hockey
        workoutActivityTypeMap["LACROSSE"] = .lacrosse
        workoutActivityTypeMap["RUGBY"] = .rugby
        workoutActivityTypeMap["SOCCER"] = .soccer
        workoutActivityTypeMap["SOFTBALL"] = .softball
        workoutActivityTypeMap["VOLLEYBALL"] = .volleyball
        workoutActivityTypeMap["PREPARATION_AND_RECOVERY"] = .preparationAndRecovery
        workoutActivityTypeMap["FLEXIBILITY"] = .flexibility
        workoutActivityTypeMap["WALKING"] = .walking
        workoutActivityTypeMap["RUNNING"] = .running
        workoutActivityTypeMap["RUNNING_TREADMILL"] = .running
        workoutActivityTypeMap["WHEELCHAIR_WALK_PACE"] = .wheelchairWalkPace
        workoutActivityTypeMap["WHEELCHAIR_RUN_PACE"] = .wheelchairRunPace
        workoutActivityTypeMap["BIKING"] = .cycling
        workoutActivityTypeMap["HAND_CYCLING"] = .handCycling
        workoutActivityTypeMap["CORE_TRAINING"] = .coreTraining
        workoutActivityTypeMap["ELLIPTICAL"] = .elliptical
        workoutActivityTypeMap["FUNCTIONAL_STRENGTH_TRAINING"] = .functionalStrengthTraining
        workoutActivityTypeMap["TRADITIONAL_STRENGTH_TRAINING"] = .traditionalStrengthTraining
        workoutActivityTypeMap["CROSS_TRAINING"] = .crossTraining
        workoutActivityTypeMap["MIXED_CARDIO"] = .mixedCardio
        workoutActivityTypeMap["HIGH_INTENSITY_INTERVAL_TRAINING"] =
            .highIntensityIntervalTraining
        workoutActivityTypeMap["JUMP_ROPE"] = .jumpRope
        workoutActivityTypeMap["STAIR_CLIMBING"] = .stairClimbing
        workoutActivityTypeMap["STAIRS"] = .stairs
        workoutActivityTypeMap["STEP_TRAINING"] = .stepTraining
        workoutActivityTypeMap["FITNESS_GAMING"] = .fitnessGaming
        workoutActivityTypeMap["BARRE"] = .barre
        workoutActivityTypeMap["YOGA"] = .yoga
        workoutActivityTypeMap["MIND_AND_BODY"] = .mindAndBody
        workoutActivityTypeMap["PILATES"] = .pilates
        workoutActivityTypeMap["BADMINTON"] = .badminton
        workoutActivityTypeMap["RACQUETBALL"] = .racquetball
        workoutActivityTypeMap["SQUASH"] = .squash
        workoutActivityTypeMap["TABLE_TENNIS"] = .tableTennis
        workoutActivityTypeMap["TENNIS"] = .tennis
        workoutActivityTypeMap["CLIMBING"] = .climbing
        workoutActivityTypeMap["ROCK_CLIMBING"] = .climbing
        workoutActivityTypeMap["EQUESTRIAN_SPORTS"] = .equestrianSports
        workoutActivityTypeMap["FISHING"] = .fishing
        workoutActivityTypeMap["GOLF"] = .golf
        workoutActivityTypeMap["HIKING"] = .hiking
        workoutActivityTypeMap["HUNTING"] = .hunting
        workoutActivityTypeMap["PLAY"] = .play
        workoutActivityTypeMap["CROSS_COUNTRY_SKIING"] = .crossCountrySkiing
        workoutActivityTypeMap["CURLING"] = .curling
        workoutActivityTypeMap["DOWNHILL_SKIING"] = .downhillSkiing
        workoutActivityTypeMap["SNOW_SPORTS"] = .snowSports
        workoutActivityTypeMap["SNOWBOARDING"] = .snowboarding
        workoutActivityTypeMap["SKATING"] = .skatingSports
        workoutActivityTypeMap["PADDLE_SPORTS"] = .paddleSports
        workoutActivityTypeMap["ROWING"] = .rowing
        workoutActivityTypeMap["SAILING"] = .sailing
        workoutActivityTypeMap["SURFING"] = .surfingSports
        workoutActivityTypeMap["SWIMMING"] = .swimming
        workoutActivityTypeMap["SWIMMING_OPEN_WATER"] = .swimming
        workoutActivityTypeMap["SWIMMING_POOL"] = .swimming
        workoutActivityTypeMap["WATER_FITNESS"] = .waterFitness
        workoutActivityTypeMap["WATER_POLO"] = .waterPolo
        workoutActivityTypeMap["WATER_SPORTS"] = .waterSports
        workoutActivityTypeMap["BOXING"] = .boxing
        workoutActivityTypeMap["KICKBOXING"] = .kickboxing
        workoutActivityTypeMap["MARTIAL_ARTS"] = .martialArts
        workoutActivityTypeMap["TAI_CHI"] = .taiChi
        workoutActivityTypeMap["WRESTLING"] = .wrestling
        workoutActivityTypeMap["OTHER"] = .other
        workoutActivityTypeMap["CARDIO_DANCE"] = .cardioDance
        workoutActivityTypeMap["SOCIAL_DANCE"] = .socialDance
        workoutActivityTypeMap["PICKLEBALL"] = .pickleball
        workoutActivityTypeMap["COOLDOWN"] = .cooldown

        if #available(iOS 17.0, macOS 14.0, *) {
            workoutActivityTypeMap["UNDERWATER_DIVING"] = .underwaterDiving
        }
    }
}
