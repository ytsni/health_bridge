import Foundation

public enum HealthRecordingProvenance: String, CaseIterable, Equatable, Sendable {
    case activelyRecorded
    case manualEntry
}

public enum HealthRecordingDevice: String, CaseIterable, Equatable, Sendable {
    case phone
    case watch
}

// The single typed source of truth for the app-owned iOS activity contract.
// The HealthKit adapter maps these cases exhaustively without maintaining a
// second string-keyed table that could drift from request validation.
enum HealthWorkoutActivity: String, CaseIterable, Equatable, Sendable {
    case americanFootball = "AMERICAN_FOOTBALL"
    case archery = "ARCHERY"
    case australianFootball = "AUSTRALIAN_FOOTBALL"
    case badminton = "BADMINTON"
    case barre = "BARRE"
    case baseball = "BASEBALL"
    case basketball = "BASKETBALL"
    case biking = "BIKING"
    case bowling = "BOWLING"
    case boxing = "BOXING"
    case cardioDance = "CARDIO_DANCE"
    case climbing = "CLIMBING"
    case cooldown = "COOLDOWN"
    case coreTraining = "CORE_TRAINING"
    case cricket = "CRICKET"
    case crossCountrySkiing = "CROSS_COUNTRY_SKIING"
    case crossTraining = "CROSS_TRAINING"
    case curling = "CURLING"
    case discSports = "DISC_SPORTS"
    case downhillSkiing = "DOWNHILL_SKIING"
    case elliptical = "ELLIPTICAL"
    case equestrianSports = "EQUESTRIAN_SPORTS"
    case fencing = "FENCING"
    case fishing = "FISHING"
    case fitnessGaming = "FITNESS_GAMING"
    case flexibility = "FLEXIBILITY"
    case functionalStrengthTraining = "FUNCTIONAL_STRENGTH_TRAINING"
    case golf = "GOLF"
    case gymnastics = "GYMNASTICS"
    case handCycling = "HAND_CYCLING"
    case handball = "HANDBALL"
    case highIntensityIntervalTraining = "HIGH_INTENSITY_INTERVAL_TRAINING"
    case hiking = "HIKING"
    case hockey = "HOCKEY"
    case hunting = "HUNTING"
    case jumpRope = "JUMP_ROPE"
    case kickboxing = "KICKBOXING"
    case lacrosse = "LACROSSE"
    case martialArts = "MARTIAL_ARTS"
    case mindAndBody = "MIND_AND_BODY"
    case mixedCardio = "MIXED_CARDIO"
    case other = "OTHER"
    case paddleSports = "PADDLE_SPORTS"
    case pickleball = "PICKLEBALL"
    case pilates = "PILATES"
    case play = "PLAY"
    case preparationAndRecovery = "PREPARATION_AND_RECOVERY"
    case racquetball = "RACQUETBALL"
    case rowing = "ROWING"
    case rugby = "RUGBY"
    case running = "RUNNING"
    case sailing = "SAILING"
    case skating = "SKATING"
    case snowSports = "SNOW_SPORTS"
    case snowboarding = "SNOWBOARDING"
    case soccer = "SOCCER"
    case socialDance = "SOCIAL_DANCE"
    case softball = "SOFTBALL"
    case squash = "SQUASH"
    case stairClimbing = "STAIR_CLIMBING"
    case stairs = "STAIRS"
    case stepTraining = "STEP_TRAINING"
    case surfing = "SURFING"
    case swimming = "SWIMMING"
    case swimmingOpenWater = "SWIMMING_OPEN_WATER"
    case swimmingPool = "SWIMMING_POOL"
    case tableTennis = "TABLE_TENNIS"
    case taiChi = "TAI_CHI"
    case tennis = "TENNIS"
    case trackAndField = "TRACK_AND_FIELD"
    case traditionalStrengthTraining = "TRADITIONAL_STRENGTH_TRAINING"
    case underwaterDiving = "UNDERWATER_DIVING"
    case volleyball = "VOLLEYBALL"
    case walking = "WALKING"
    case waterFitness = "WATER_FITNESS"
    case waterPolo = "WATER_POLO"
    case waterSports = "WATER_SPORTS"
    case wheelchairRunPace = "WHEELCHAIR_RUN_PACE"
    case wheelchairWalkPace = "WHEELCHAIR_WALK_PACE"
    case wrestling = "WRESTLING"
    case yoga = "YOGA"
}

public enum WorkoutWriteStatus: String, CaseIterable, Equatable, Sendable {
    case written
    case alreadyPresent
    case writtenWithoutEnergy
    case blockedWorkoutPermission
    case verificationRequired
    case inconsistentNativeState
    case transientFailure
    case invalidInput
    case unavailable
}

public enum EnergyWriteStatus: String, CaseIterable, Equatable, Sendable {
    case notExpected
    case written
    case alreadyPresent
    case omittedPermission
    case absent
    case notSubmitted
    case verificationRequired
}

public enum SubmissionCertainty: String, CaseIterable, Equatable, Sendable {
    case notSubmitted
    case mayHaveSubmitted
    case submitted
}

public enum RecordLookupStatus: String, CaseIterable, Equatable, Sendable {
    case present
    case absent
    case unavailable
    case notExpected
}

public enum WorkoutLookupStatus: String, CaseIterable, Equatable, Sendable {
    case present
    case workoutOnly
    case absent
    case unavailable
    case inconsistent
}

public enum AuthorizationState: String, CaseIterable, Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
    case requestedOrUnknown
    case unavailable
    case unsupported
}

public enum WorkoutModelError: Error, Equatable, Sendable {
    case invalidWorkoutClientRecordId
    case invalidEnergyClientRecordId
    case invalidClientRecordVersion
    case invalidDateRange
    case invalidStartZoneOffset
    case invalidEndZoneOffset
    case invalidEnergyPair
    case invalidActiveEnergy
    case invalidActivityType
    case invalidTitle
}

public enum WorkoutResultError: Error, Equatable, Sendable {
    case blankWorkoutRecordId
    case blankEnergyRecordId
    case blankPlatformCode
    case invalidWriteStatusPair
    case invalidWorkoutRecordIdPresence
    case invalidEnergyRecordIdPresence
    case invalidSubmissionCertainty
    case invalidRecordLookup
    case workoutLookupNotExpected
    case invalidDerivedStatus
}

public enum HealthAuthorizationModelError: Error, Equatable, Sendable {
    case blankType
    case emptyTypes
    case duplicateType
    case blankPlatformCode
    case invalidAvailability
}

public struct WorkoutWriteRequest: Equatable, Sendable {
    public let workoutClientRecordId: String
    public let energyClientRecordId: String?
    public let clientRecordVersion: Int
    public let activityType: String
    public let startEpochMilliseconds: Int64
    public let endEpochMilliseconds: Int64
    public let startZoneOffsetSeconds: Int
    public let endZoneOffsetSeconds: Int
    public let activeEnergyKcal: Double?
    public let title: String
    public let recordingProvenance: HealthRecordingProvenance
    public let recordingDevice: HealthRecordingDevice

    public var start: Date {
        Date(
            timeIntervalSince1970: Double(startEpochMilliseconds) / 1_000
        )
    }

    public var end: Date {
        Date(
            timeIntervalSince1970: Double(endEpochMilliseconds) / 1_000
        )
    }

    public init(
        workoutClientRecordId: String,
        energyClientRecordId: String?,
        clientRecordVersion: Int,
        activityType: String,
        startEpochMilliseconds: Int64,
        endEpochMilliseconds: Int64,
        startZoneOffsetSeconds: Int,
        endZoneOffsetSeconds: Int,
        activeEnergyKcal: Double?,
        title: String,
        recordingProvenance: HealthRecordingProvenance,
        recordingDevice: HealthRecordingDevice
    ) throws {
        guard UUID(uuidString: workoutClientRecordId) != nil else {
            throw WorkoutModelError.invalidWorkoutClientRecordId
        }
        if let energyClientRecordId,
            UUID(uuidString: energyClientRecordId) == nil
        {
            throw WorkoutModelError.invalidEnergyClientRecordId
        }
        guard clientRecordVersion == 0 else {
            throw WorkoutModelError.invalidClientRecordVersion
        }
        guard HealthWorkoutActivity(rawValue: activityType) != nil else {
            throw WorkoutModelError.invalidActivityType
        }
        guard endEpochMilliseconds > startEpochMilliseconds else {
            throw WorkoutModelError.invalidDateRange
        }
        guard Self.validZoneOffset(startZoneOffsetSeconds) else {
            throw WorkoutModelError.invalidStartZoneOffset
        }
        guard Self.validZoneOffset(endZoneOffsetSeconds) else {
            throw WorkoutModelError.invalidEndZoneOffset
        }
        guard (energyClientRecordId == nil) == (activeEnergyKcal == nil) else {
            throw WorkoutModelError.invalidEnergyPair
        }
        if let activeEnergyKcal,
            !activeEnergyKcal.isFinite || activeEnergyKcal <= 0
        {
            throw WorkoutModelError.invalidActiveEnergy
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkoutModelError.invalidTitle
        }

        self.workoutClientRecordId = workoutClientRecordId
        self.energyClientRecordId = energyClientRecordId
        self.clientRecordVersion = clientRecordVersion
        self.activityType = activityType
        self.startEpochMilliseconds = startEpochMilliseconds
        self.endEpochMilliseconds = endEpochMilliseconds
        self.startZoneOffsetSeconds = startZoneOffsetSeconds
        self.endZoneOffsetSeconds = endZoneOffsetSeconds
        self.activeEnergyKcal = activeEnergyKcal
        self.title = title
        self.recordingProvenance = recordingProvenance
        self.recordingDevice = recordingDevice
    }

    private static func validZoneOffset(_ value: Int) -> Bool {
        (-64_800...64_800).contains(value)
    }

}

public struct WorkoutLookupRequest: Equatable, Sendable {
    public let workoutClientRecordId: String
    public let energyClientRecordId: String?
    public let start: Date
    public let end: Date

    public init(
        workoutClientRecordId: String,
        energyClientRecordId: String?,
        start: Date,
        end: Date
    ) throws {
        guard UUID(uuidString: workoutClientRecordId) != nil else {
            throw WorkoutModelError.invalidWorkoutClientRecordId
        }
        if let energyClientRecordId,
            UUID(uuidString: energyClientRecordId) == nil
        {
            throw WorkoutModelError.invalidEnergyClientRecordId
        }
        guard end > start else {
            throw WorkoutModelError.invalidDateRange
        }

        self.workoutClientRecordId = workoutClientRecordId
        self.energyClientRecordId = energyClientRecordId
        self.start = start
        self.end = end
    }
}

public struct WorkoutWriteResult: Equatable, Sendable {
    public let status: WorkoutWriteStatus
    public let workoutRecordId: String?
    public let energyRecordId: String?
    public let energyStatus: EnergyWriteStatus
    public let retryable: Bool
    public let submissionCertainty: SubmissionCertainty
    public let platformCode: String?

    public init(
        status: WorkoutWriteStatus,
        workoutRecordId: String?,
        energyRecordId: String?,
        energyStatus: EnergyWriteStatus,
        retryable: Bool,
        submissionCertainty: SubmissionCertainty,
        platformCode: String? = nil
    ) throws {
        if workoutRecordId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw WorkoutResultError.blankWorkoutRecordId
        }
        if energyRecordId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw WorkoutResultError.blankEnergyRecordId
        }
        if platformCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw WorkoutResultError.blankPlatformCode
        }
        guard Self.isAllowedPair(status: status, energyStatus: energyStatus) else {
            throw WorkoutResultError.invalidWriteStatusPair
        }
        guard (workoutRecordId != nil) == Self.requiresWorkoutRecordID(status) else {
            throw WorkoutResultError.invalidWorkoutRecordIdPresence
        }
        guard (energyRecordId != nil) == Self.requiresEnergyRecordID(energyStatus) else {
            throw WorkoutResultError.invalidEnergyRecordIdPresence
        }
        guard submissionCertainty == Self.requiredCertainty(status) else {
            throw WorkoutResultError.invalidSubmissionCertainty
        }

        self.status = status
        self.workoutRecordId = workoutRecordId
        self.energyRecordId = energyRecordId
        self.energyStatus = energyStatus
        self.retryable = retryable
        self.submissionCertainty = submissionCertainty
        self.platformCode = platformCode
    }

    private static func isAllowedPair(
        status: WorkoutWriteStatus,
        energyStatus: EnergyWriteStatus
    ) -> Bool {
        switch (status, energyStatus) {
        case (.written, .notExpected),
            (.written, .written),
            (.alreadyPresent, .notExpected),
            (.alreadyPresent, .alreadyPresent),
            (.alreadyPresent, .absent),
            (.writtenWithoutEnergy, .omittedPermission),
            (.blockedWorkoutPermission, .notExpected),
            (.blockedWorkoutPermission, .notSubmitted),
            (.verificationRequired, .notExpected),
            (.verificationRequired, .omittedPermission),
            (.verificationRequired, .verificationRequired),
            (.inconsistentNativeState, .alreadyPresent),
            (.transientFailure, .notExpected),
            (.transientFailure, .notSubmitted),
            (.invalidInput, .notExpected),
            (.invalidInput, .notSubmitted),
            (.unavailable, .notExpected),
            (.unavailable, .notSubmitted):
            true
        default:
            false
        }
    }

    private static func requiresWorkoutRecordID(
        _ status: WorkoutWriteStatus
    ) -> Bool {
        switch status {
        case .written, .alreadyPresent, .writtenWithoutEnergy:
            true
        case .blockedWorkoutPermission, .verificationRequired,
            .inconsistentNativeState, .transientFailure, .invalidInput,
            .unavailable:
            false
        }
    }

    private static func requiresEnergyRecordID(
        _ status: EnergyWriteStatus
    ) -> Bool {
        status == .written || status == .alreadyPresent
    }

    private static func requiredCertainty(
        _ status: WorkoutWriteStatus
    ) -> SubmissionCertainty {
        switch status {
        case .written, .alreadyPresent, .writtenWithoutEnergy,
            .inconsistentNativeState:
            .submitted
        case .verificationRequired:
            .mayHaveSubmitted
        case .blockedWorkoutPermission, .transientFailure, .invalidInput,
            .unavailable:
            .notSubmitted
        }
    }
}

public struct RecordLookup: Equatable, Sendable {
    public let status: RecordLookupStatus
    public let recordId: String?

    public init(
        status: RecordLookupStatus,
        recordId: String? = nil
    ) throws {
        if recordId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw WorkoutResultError.invalidRecordLookup
        }
        guard (status == .present) == (recordId != nil) else {
            throw WorkoutResultError.invalidRecordLookup
        }
        self.status = status
        self.recordId = recordId
    }
}

public struct WorkoutLookupResult: Equatable, Sendable {
    public let workout: RecordLookup
    public let energy: RecordLookup
    public let derivedStatus: WorkoutLookupStatus
    public let platformCode: String?

    public init(
        workout: RecordLookup,
        energy: RecordLookup,
        derivedStatus: WorkoutLookupStatus,
        platformCode: String? = nil
    ) throws {
        if platformCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw WorkoutResultError.blankPlatformCode
        }
        guard workout.status != .notExpected else {
            throw WorkoutResultError.workoutLookupNotExpected
        }
        guard
            derivedStatus
                == Self.deriveStatus(
                    workout: workout.status,
                    energy: energy.status
                )
        else {
            throw WorkoutResultError.invalidDerivedStatus
        }

        self.workout = workout
        self.energy = energy
        self.derivedStatus = derivedStatus
        self.platformCode = platformCode
    }

    private static func deriveStatus(
        workout: RecordLookupStatus,
        energy: RecordLookupStatus
    ) -> WorkoutLookupStatus {
        if workout == .unavailable || energy == .unavailable {
            return .unavailable
        }
        return switch (workout, energy) {
        case (.absent, .present):
            .inconsistent
        case (.absent, .absent), (.absent, .notExpected):
            .absent
        case (.present, .present):
            .present
        case (.present, .absent), (.present, .notExpected):
            .workoutOnly
        case (.notExpected, _):
            // The public initializer rejects this before derivation.
            .unavailable
        case (_, .unavailable), (.unavailable, _):
            .unavailable
        }
    }
}

public struct HealthTypeAuthorization: Equatable, Sendable {
    public let type: String
    public let read: AuthorizationState
    public let write: AuthorizationState

    public init(
        type: String,
        read: AuthorizationState,
        write: AuthorizationState
    ) throws {
        guard !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HealthAuthorizationModelError.blankType
        }
        self.type = type
        self.read = read
        self.write = write
    }
}

public struct HealthAuthorizationSnapshot: Equatable, Sendable {
    public let available: Bool
    public let types: [HealthTypeAuthorization]
    public let platformCode: String?

    public init(
        available: Bool,
        types: [HealthTypeAuthorization],
        platformCode: String? = nil
    ) throws {
        guard !types.isEmpty else {
            throw HealthAuthorizationModelError.emptyTypes
        }
        if platformCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            throw HealthAuthorizationModelError.blankPlatformCode
        }
        let canonicalTypes = types.sorted { $0.type < $1.type }
        guard Set(canonicalTypes.map(\.type)).count == canonicalTypes.count else {
            throw HealthAuthorizationModelError.duplicateType
        }
        if available {
            guard
                canonicalTypes.allSatisfy({
                    $0.read != .unavailable && $0.write != .unavailable
                })
            else {
                throw HealthAuthorizationModelError.invalidAvailability
            }
        } else {
            guard
                canonicalTypes.allSatisfy({
                    $0.read == .unavailable && $0.write == .unavailable
                })
            else {
                throw HealthAuthorizationModelError.invalidAvailability
            }
        }

        self.available = available
        self.types = canonicalTypes
        self.platformCode = platformCode
    }
}
