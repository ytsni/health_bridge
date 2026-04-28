import HealthKit

/// Nutrition keys and lookups used by meal reads and writes.
extension HealthConstants {
    /// The `DIETARY_CAFFEINE` nutrition data type key.
    static let DIETARY_CAFFEINE = "DIETARY_CAFFEINE"

    /// The `DIETARY_CALCIUM` nutrition data type key.
    static let DIETARY_CALCIUM = "DIETARY_CALCIUM"

    /// The `DIETARY_CARBS_CONSUMED` nutrition data type key.
    static let DIETARY_CARBS_CONSUMED = "DIETARY_CARBS_CONSUMED"

    /// The `DIETARY_CHLORIDE` nutrition data type key.
    static let DIETARY_CHLORIDE = "DIETARY_CHLORIDE"

    /// The `DIETARY_CHOLESTEROL` nutrition data type key.
    static let DIETARY_CHOLESTEROL = "DIETARY_CHOLESTEROL"

    /// The `DIETARY_CHROMIUM` nutrition data type key.
    static let DIETARY_CHROMIUM = "DIETARY_CHROMIUM"

    /// The `DIETARY_COPPER` nutrition data type key.
    static let DIETARY_COPPER = "DIETARY_COPPER"

    /// The `DIETARY_ENERGY_CONSUMED` nutrition data type key.
    static let DIETARY_ENERGY_CONSUMED = "DIETARY_ENERGY_CONSUMED"

    /// The `DIETARY_FAT_MONOUNSATURATED` nutrition data type key.
    static let DIETARY_FAT_MONOUNSATURATED = "DIETARY_FAT_MONOUNSATURATED"

    /// The `DIETARY_FAT_POLYUNSATURATED` nutrition data type key.
    static let DIETARY_FAT_POLYUNSATURATED = "DIETARY_FAT_POLYUNSATURATED"

    /// The `DIETARY_FAT_SATURATED` nutrition data type key.
    static let DIETARY_FAT_SATURATED = "DIETARY_FAT_SATURATED"

    /// The `DIETARY_FATS_CONSUMED` nutrition data type key.
    static let DIETARY_FATS_CONSUMED = "DIETARY_FATS_CONSUMED"

    /// The `DIETARY_FIBER` nutrition data type key.
    static let DIETARY_FIBER = "DIETARY_FIBER"

    /// The `DIETARY_FOLATE` nutrition data type key.
    static let DIETARY_FOLATE = "DIETARY_FOLATE"

    /// The `DIETARY_IODINE` nutrition data type key.
    static let DIETARY_IODINE = "DIETARY_IODINE"

    /// The `DIETARY_IRON` nutrition data type key.
    static let DIETARY_IRON = "DIETARY_IRON"

    /// The `DIETARY_MAGNESIUM` nutrition data type key.
    static let DIETARY_MAGNESIUM = "DIETARY_MAGNESIUM"

    /// The `DIETARY_MANGANESE` nutrition data type key.
    static let DIETARY_MANGANESE = "DIETARY_MANGANESE"

    /// The `DIETARY_MOLYBDENUM` nutrition data type key.
    static let DIETARY_MOLYBDENUM = "DIETARY_MOLYBDENUM"

    /// The `DIETARY_NIACIN` nutrition data type key.
    static let DIETARY_NIACIN = "DIETARY_NIACIN"

    /// The `DIETARY_PANTOTHENIC_ACID` nutrition data type key.
    static let DIETARY_PANTOTHENIC_ACID = "DIETARY_PANTOTHENIC_ACID"

    /// The `DIETARY_PHOSPHORUS` nutrition data type key.
    static let DIETARY_PHOSPHORUS = "DIETARY_PHOSPHORUS"

    /// The `DIETARY_POTASSIUM` nutrition data type key.
    static let DIETARY_POTASSIUM = "DIETARY_POTASSIUM"

    /// The `DIETARY_PROTEIN_CONSUMED` nutrition data type key.
    static let DIETARY_PROTEIN_CONSUMED = "DIETARY_PROTEIN_CONSUMED"

    /// The `DIETARY_RIBOFLAVIN` nutrition data type key.
    static let DIETARY_RIBOFLAVIN = "DIETARY_RIBOFLAVIN"

    /// The `DIETARY_SELENIUM` nutrition data type key.
    static let DIETARY_SELENIUM = "DIETARY_SELENIUM"

    /// The `DIETARY_SODIUM` nutrition data type key.
    static let DIETARY_SODIUM = "DIETARY_SODIUM"

    /// The `DIETARY_SUGAR` nutrition data type key.
    static let DIETARY_SUGAR = "DIETARY_SUGAR"

    /// The `DIETARY_THIAMIN` nutrition data type key.
    static let DIETARY_THIAMIN = "DIETARY_THIAMIN"

    /// The `DIETARY_VITAMIN_A` nutrition data type key.
    static let DIETARY_VITAMIN_A = "DIETARY_VITAMIN_A"

    /// The `DIETARY_VITAMIN_B12` nutrition data type key.
    static let DIETARY_VITAMIN_B12 = "DIETARY_VITAMIN_B12"

    /// The `DIETARY_VITAMIN_B6` nutrition data type key.
    static let DIETARY_VITAMIN_B6 = "DIETARY_VITAMIN_B6"

    /// The `DIETARY_VITAMIN_C` nutrition data type key.
    static let DIETARY_VITAMIN_C = "DIETARY_VITAMIN_C"

    /// The `DIETARY_VITAMIN_D` nutrition data type key.
    static let DIETARY_VITAMIN_D = "DIETARY_VITAMIN_D"

    /// The `DIETARY_VITAMIN_E` nutrition data type key.
    static let DIETARY_VITAMIN_E = "DIETARY_VITAMIN_E"

    /// The `DIETARY_VITAMIN_K` nutrition data type key.
    static let DIETARY_VITAMIN_K = "DIETARY_VITAMIN_K"

    /// The `DIETARY_WATER` nutrition data type key.
    static let DIETARY_WATER = "WATER"

    /// The `DIETARY_ZINC` nutrition data type key.
    static let DIETARY_ZINC = "DIETARY_ZINC"

    /// The `DIETARY_BIOTIN` nutrition data type key.
    static let DIETARY_BIOTIN = "DIETARY_BIOTIN"

    /// Nutrition data type keys supported by the plugin.
    static let nutritionDataTypes: [String] = [
        DIETARY_ENERGY_CONSUMED,
        DIETARY_CARBS_CONSUMED,
        DIETARY_PROTEIN_CONSUMED,
        DIETARY_FATS_CONSUMED,
        DIETARY_CAFFEINE,
        DIETARY_FIBER,
        DIETARY_SUGAR,
        DIETARY_FAT_MONOUNSATURATED,
        DIETARY_FAT_POLYUNSATURATED,
        DIETARY_FAT_SATURATED,
        DIETARY_CHOLESTEROL,
        DIETARY_VITAMIN_A,
        DIETARY_THIAMIN,
        DIETARY_RIBOFLAVIN,
        DIETARY_NIACIN,
        DIETARY_PANTOTHENIC_ACID,
        DIETARY_VITAMIN_B6,
        DIETARY_BIOTIN,
        DIETARY_VITAMIN_B12,
        DIETARY_VITAMIN_C,
        DIETARY_VITAMIN_D,
        DIETARY_VITAMIN_E,
        DIETARY_VITAMIN_K,
        DIETARY_FOLATE,
        DIETARY_CALCIUM,
        DIETARY_CHLORIDE,
        DIETARY_IRON,
        DIETARY_MAGNESIUM,
        DIETARY_PHOSPHORUS,
        DIETARY_POTASSIUM,
        DIETARY_SODIUM,
        DIETARY_ZINC,
        DIETARY_WATER,
        DIETARY_CHROMIUM,
        DIETARY_COPPER,
        DIETARY_IODINE,
        DIETARY_MANGANESE,
        DIETARY_MOLYBDENUM,
        DIETARY_SELENIUM,
    ]

    /// Maps nutrition data type keys to HealthKit quantity identifiers.
    static let nutritionTypeIdentifiers: [String: HKQuantityTypeIdentifier] = [
        DIETARY_CAFFEINE: .dietaryCaffeine,
        DIETARY_CALCIUM: .dietaryCalcium,
        DIETARY_CARBS_CONSUMED: .dietaryCarbohydrates,
        DIETARY_CHLORIDE: .dietaryChloride,
        DIETARY_CHOLESTEROL: .dietaryCholesterol,
        DIETARY_CHROMIUM: .dietaryChromium,
        DIETARY_COPPER: .dietaryCopper,
        DIETARY_ENERGY_CONSUMED: .dietaryEnergyConsumed,
        DIETARY_FAT_MONOUNSATURATED: .dietaryFatMonounsaturated,
        DIETARY_FAT_POLYUNSATURATED: .dietaryFatPolyunsaturated,
        DIETARY_FAT_SATURATED: .dietaryFatSaturated,
        DIETARY_FATS_CONSUMED: .dietaryFatTotal,
        DIETARY_FIBER: .dietaryFiber,
        DIETARY_FOLATE: .dietaryFolate,
        DIETARY_IODINE: .dietaryIodine,
        DIETARY_IRON: .dietaryIron,
        DIETARY_MAGNESIUM: .dietaryMagnesium,
        DIETARY_MANGANESE: .dietaryManganese,
        DIETARY_MOLYBDENUM: .dietaryMolybdenum,
        DIETARY_NIACIN: .dietaryNiacin,
        DIETARY_PANTOTHENIC_ACID: .dietaryPantothenicAcid,
        DIETARY_PHOSPHORUS: .dietaryPhosphorus,
        DIETARY_POTASSIUM: .dietaryPotassium,
        DIETARY_PROTEIN_CONSUMED: .dietaryProtein,
        DIETARY_RIBOFLAVIN: .dietaryRiboflavin,
        DIETARY_SELENIUM: .dietarySelenium,
        DIETARY_SODIUM: .dietarySodium,
        DIETARY_SUGAR: .dietarySugar,
        DIETARY_THIAMIN: .dietaryThiamin,
        DIETARY_VITAMIN_A: .dietaryVitaminA,
        DIETARY_VITAMIN_B12: .dietaryVitaminB12,
        DIETARY_VITAMIN_B6: .dietaryVitaminB6,
        DIETARY_VITAMIN_C: .dietaryVitaminC,
        DIETARY_VITAMIN_D: .dietaryVitaminD,
        DIETARY_VITAMIN_E: .dietaryVitaminE,
        DIETARY_VITAMIN_K: .dietaryVitaminK,
        DIETARY_WATER: .dietaryWater,
        DIETARY_ZINC: .dietaryZinc,
        DIETARY_BIOTIN: .dietaryBiotin,
    ]

    /// Maps Flutter meal nutrient keys to HealthKit quantity identifiers.
    static let NUTRITION_KEYS: [String: HKQuantityTypeIdentifier] = [
        "calories": .dietaryEnergyConsumed,
        "protein": .dietaryProtein,
        "carbs": .dietaryCarbohydrates,
        "fat": .dietaryFatTotal,
        "caffeine": .dietaryCaffeine,
        "vitamin_a": .dietaryVitaminA,
        "b1_thiamine": .dietaryThiamin,
        "b2_riboflavin": .dietaryRiboflavin,
        "b3_niacin": .dietaryNiacin,
        "b5_pantothenic_acid": .dietaryPantothenicAcid,
        "b6_pyridoxine": .dietaryVitaminB6,
        "b7_biotin": .dietaryBiotin,
        "b9_folate": .dietaryFolate,
        "b12_cobalamin": .dietaryVitaminB12,
        "vitamin_c": .dietaryVitaminC,
        "vitamin_d": .dietaryVitaminD,
        "vitamin_e": .dietaryVitaminE,
        "vitamin_k": .dietaryVitaminK,
        "calcium": .dietaryCalcium,
        "chloride": .dietaryChloride,
        "cholesterol": .dietaryCholesterol,
        "chromium": .dietaryChromium,
        "copper": .dietaryCopper,
        "fat_unsaturated": .dietaryFatMonounsaturated,
        "fat_monounsaturated": .dietaryFatMonounsaturated,
        "fat_polyunsaturated": .dietaryFatPolyunsaturated,
        "fat_saturated": .dietaryFatSaturated,
        "fiber": .dietaryFiber,
        "iodine": .dietaryIodine,
        "iron": .dietaryIron,
        "magnesium": .dietaryMagnesium,
        "manganese": .dietaryManganese,
        "molybdenum": .dietaryMolybdenum,
        "phosphorus": .dietaryPhosphorus,
        "potassium": .dietaryPotassium,
        "selenium": .dietarySelenium,
        "sodium": .dietarySodium,
        "sugar": .dietarySugar,
        "water": .dietaryWater,
        "zinc": .dietaryZinc,
    ]
}
