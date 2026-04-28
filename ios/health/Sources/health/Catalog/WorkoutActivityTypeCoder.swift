import HealthKit

/// Default translator between plugin workout keys and `HKWorkoutActivityType`.
struct WorkoutActivityTypeCoder: WorkoutActivityTypeCoding {
    /// Forward lookup keyed by the plugin's uppercase activity constants.
    private let activityTypesByPluginKey: [String: HKWorkoutActivityType]

    /// Reverse lookup keyed by the HealthKit enum raw value.
    private let pluginKeysByActivityType: [UInt: String]

    /// Creates a coder backed by the catalog's workout activity map.
    init(activityTypesByPluginKey: [String: HKWorkoutActivityType]) {
        self.activityTypesByPluginKey = activityTypesByPluginKey

        var pluginKeysByRawValue: [UInt: [String]] = [:]
        for (pluginKey, activityType) in activityTypesByPluginKey {
            pluginKeysByRawValue[activityType.rawValue, default: []].append(pluginKey)
        }

        pluginKeysByActivityType = pluginKeysByRawValue.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = entry.value.sorted().first
        }
    }

    /// Resolves the HealthKit activity type used for `pluginKey`.
    func activityType(for pluginKey: String) -> HKWorkoutActivityType? {
        activityTypesByPluginKey[pluginKey]
    }

    /// Resolves the canonical plugin key for `activityType`.
    func pluginKey(for activityType: HKWorkoutActivityType) -> String? {
        pluginKeysByActivityType[activityType.rawValue]
    }

    /// Resolves the legacy lower-camel workout string returned to Flutter summaries.
    func legacyName(for activityType: HKWorkoutActivityType) -> String {
        return switch activityType {
        case .americanFootball: "americanFootball"
        case .archery: "archery"
        case .australianFootball: "australianFootball"
        case .badminton: "badminton"
        case .baseball: "baseball"
        case .basketball: "basketball"
        case .bowling: "bowling"
        case .boxing: "boxing"
        case .climbing: "climbing"
        case .cricket: "cricket"
        case .crossTraining: "crossTraining"
        case .curling: "curling"
        case .cycling: "cycling"
        case .dance: "dance"
        case .danceInspiredTraining: "danceInspiredTraining"
        case .elliptical: "elliptical"
        case .equestrianSports: "equestrianSports"
        case .fencing: "fencing"
        case .fishing: "fishing"
        case .functionalStrengthTraining: "functionalStrengthTraining"
        case .golf: "golf"
        case .gymnastics: "gymnastics"
        case .handball: "handball"
        case .hiking: "hiking"
        case .hockey: "hockey"
        case .hunting: "hunting"
        case .lacrosse: "lacrosse"
        case .martialArts: "martialArts"
        case .mindAndBody: "mindAndBody"
        case .mixedMetabolicCardioTraining: "mixedMetabolicCardioTraining"
        case .paddleSports: "paddleSports"
        case .play: "play"
        case .preparationAndRecovery: "preparationAndRecovery"
        case .racquetball: "racquetball"
        case .rowing: "rowing"
        case .rugby: "rugby"
        case .running: "running"
        case .sailing: "sailing"
        case .skatingSports: "skatingSports"
        case .snowSports: "snowSports"
        case .soccer: "soccer"
        case .softball: "softball"
        case .squash: "squash"
        case .stairClimbing: "stairClimbing"
        case .surfingSports: "surfingSports"
        case .swimming: "swimming"
        case .tableTennis: "tableTennis"
        case .tennis: "tennis"
        case .trackAndField: "trackAndField"
        case .traditionalStrengthTraining: "traditionalStrengthTraining"
        case .volleyball: "volleyball"
        case .walking: "walking"
        case .waterFitness: "waterFitness"
        case .waterPolo: "waterPolo"
        case .waterSports: "waterSports"
        case .wrestling: "wrestling"
        case .yoga: "yoga"
        case .barre: "barre"
        case .coreTraining: "coreTraining"
        case .crossCountrySkiing: "crossCountrySkiing"
        case .downhillSkiing: "downhillSkiing"
        case .flexibility: "flexibility"
        case .highIntensityIntervalTraining: "highIntensityIntervalTraining"
        case .jumpRope: "jumpRope"
        case .kickboxing: "kickboxing"
        case .pilates: "pilates"
        case .snowboarding: "snowboarding"
        case .stairs: "stairs"
        case .stepTraining: "stepTraining"
        case .wheelchairWalkPace: "wheelchairWalkPace"
        case .wheelchairRunPace: "wheelchairRunPace"
        case .taiChi: "taiChi"
        case .mixedCardio: "mixedCardio"
        case .handCycling: "handCycling"
        default:
            if #available(iOS 17.0, macOS 14.0, *), activityType == .underwaterDiving {
                "underwaterDiving"
            } else {
                "other"
            }
        }
    }
}
