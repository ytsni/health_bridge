import Foundation
@preconcurrency import HealthKit

public enum WorkoutComponent: String, Equatable, Sendable {
    case workout
    case activeEnergy
}

public enum WriteAuthorization: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
}

public enum HealthWorkoutBuilderError: Error, Equatable, Sendable {
    case authorizationDenied(WorkoutComponent)
    case authorizationNotDetermined(WorkoutComponent)
    case operationFailed
}

public enum HealthWorkoutStoreError: Error, Equatable, Sendable {
    case activityUnavailable
    case builderUnavailable
}

public enum HealthWorkoutLookupError: Error, Equatable, Sendable {
    case healthDataUnavailable
    case typeUnavailable
    case protectedDataUnavailable
    case queryFailed
}

public struct StoredRecordIdentity: Equatable, Sendable {
    public let recordID: UUID
    public let syncIdentifier: String?
    public let externalIdentifier: String?
    public let isFromCurrentSource: Bool

    public init(
        recordID: UUID,
        syncIdentifier: String?,
        externalIdentifier: String?,
        isFromCurrentSource: Bool
    ) {
        self.recordID = recordID
        self.syncIdentifier = syncIdentifier
        self.externalIdentifier = externalIdentifier
        self.isFromCurrentSource = isFromCurrentSource
    }
}

public struct StoredWorkoutAndEnergy: Equatable, Sendable {
    public let workoutRecordID: UUID
    public let energyRecordID: UUID?

    public init(workoutRecordID: UUID, energyRecordID: UUID?) {
        self.workoutRecordID = workoutRecordID
        self.energyRecordID = energyRecordID
    }
}

public protocol HealthWorkoutStore: AnyObject, Sendable {
    var isHealthDataAvailable: Bool { get }

    func writeAuthorization(for component: WorkoutComponent) -> WriteAuthorization
    func writeAuthorization(for type: String) -> WriteAuthorization?

    func lookup(
        component: WorkoutComponent,
        clientRecordId: String,
        start: Date,
        end: Date,
        completion:
            @escaping @Sendable (
                Result<[StoredRecordIdentity], HealthWorkoutLookupError>
            ) -> Void
    )

    func makeBuilder(for request: WorkoutWriteRequest) throws -> HealthWorkoutBuilder
}

public extension HealthWorkoutStore {
    func writeAuthorization(for type: String) -> WriteAuthorization? {
        switch type {
        case "WORKOUT":
            return writeAuthorization(for: .workout)
        case "ACTIVE_ENERGY_BURNED":
            return writeAuthorization(for: .activeEnergy)
        default:
            return nil
        }
    }
}

public protocol HealthWorkoutBuilder: AnyObject, Sendable {
    func begin(
        at start: Date,
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    )

    func addEnergy(
        kilocalories: Double,
        start: Date,
        end: Date,
        metadata: [String: Any],
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    )

    func addWorkoutMetadata(
        _ metadata: [String: Any],
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    )

    func end(
        at end: Date,
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    )

    func finish(
        completion:
            @escaping @Sendable (
                StoredWorkoutAndEnergy?,
                HealthWorkoutBuilderError?
            ) -> Void
    )

    func discard()
}

public final class HealthKitWorkoutStore: HealthWorkoutStore, @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let authorizationTypes: [String: HKObjectType]

    public init(
        healthStore: HKHealthStore = HKHealthStore(),
        authorizationTypes: [String: HKObjectType]? = nil
    ) {
        self.healthStore = healthStore
        self.authorizationTypes = authorizationTypes
            ?? Self.defaultAuthorizationTypes()
    }

    public var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    public func writeAuthorization(
        for component: WorkoutComponent
    ) -> WriteAuthorization {
        let objectType: HKObjectType
        switch component {
        case .workout:
            objectType = HKObjectType.workoutType()
        case .activeEnergy:
            guard
                let energyType = HKObjectType.quantityType(
                    forIdentifier: .activeEnergyBurned
                )
            else {
                return .denied
            }
            objectType = energyType
        }

        return Self.writeAuthorization(
            from: healthStore.authorizationStatus(for: objectType)
        )
    }

    public func writeAuthorization(for type: String) -> WriteAuthorization? {
        guard let objectType = authorizationTypes[type] else { return nil }
        return Self.writeAuthorization(
            from: healthStore.authorizationStatus(for: objectType)
        )
    }

    private static func defaultAuthorizationTypes() -> [String: HKObjectType] {
        var types: [String: HKObjectType] = [
            "WORKOUT": HKObjectType.workoutType()
        ]
        if let activeEnergy = HKObjectType.quantityType(
            forIdentifier: .activeEnergyBurned
        ) {
            types["ACTIVE_ENERGY_BURNED"] = activeEnergy
        }
        return types
    }

    static func writeAuthorization(
        from status: HKAuthorizationStatus
    ) -> WriteAuthorization {
        switch status {
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    public func lookup(
        component: WorkoutComponent,
        clientRecordId: String,
        start: Date,
        end: Date,
        completion:
            @escaping @Sendable (
                Result<[StoredRecordIdentity], HealthWorkoutLookupError>
            ) -> Void
    ) {
        guard isHealthDataAvailable else {
            completion(.failure(.healthDataUnavailable))
            return
        }

        let sampleType: HKSampleType
        switch component {
        case .workout:
            sampleType = HKObjectType.workoutType()
        case .activeEnergy:
            guard
                let energyType = HKObjectType.quantityType(
                    forIdentifier: .activeEnergyBurned
                )
            else {
                completion(.failure(.typeUnavailable))
                return
            }
            sampleType = energyType
        }

        let currentSource = HKSource.default()
        let predicate = Self.lookupPredicate(
            clientRecordId: clientRecordId,
            start: start,
            end: end,
            source: currentSource
        )
        let query = HKSampleQuery(
            sampleType: sampleType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error {
                completion(.failure(Self.lookupError(for: error)))
                return
            }

            let identities = (samples ?? []).map { sample in
                StoredRecordIdentity(
                    recordID: sample.uuid,
                    syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier]
                        as? String,
                    externalIdentifier: sample.metadata?[HKMetadataKeyExternalUUID]
                        as? String,
                    isFromCurrentSource: sample.sourceRevision.source.isEqual(
                        currentSource
                    )
                )
            }
            completion(.success(identities))
        }
        healthStore.execute(query)
    }

    static func lookupPredicate(
        clientRecordId: String,
        start: Date,
        end: Date,
        source: HKSource
    ) -> NSPredicate {
        NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                HKQuery.predicateForSamples(withStart: start, end: end),
                HKQuery.predicateForObjects(from: source),
                Self.lookupMetadataPredicate(clientRecordId: clientRecordId),
            ]
        )
    }

    static func lookupMetadataPredicate(
        clientRecordId: String
    ) -> NSPredicate {
        HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: clientRecordId
        )
    }

    public func makeBuilder(
        for request: WorkoutWriteRequest
    ) throws -> HealthWorkoutBuilder {
        guard
            let activity = HealthWorkoutActivity(rawValue: request.activityType),
            let healthKitActivity = Self.healthKitActivityType(for: activity)
        else {
            throw HealthWorkoutStoreError.activityUnavailable
        }
        let activeEnergyType = HKObjectType.quantityType(
            forIdentifier: .activeEnergyBurned
        )

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = healthKitActivity
        let device = Self.builderDevice(for: request.recordingDevice)
        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: device
        )
        return HealthKitWorkoutBuilder(
            builder: builder,
            activeEnergyType: activeEnergyType,
            sampleDevice: device
        )
    }

    static func builderDevice(
        for recordingDevice: HealthRecordingDevice
    ) -> HKDevice? {
        switch recordingDevice {
        case .phone:
            return HKDevice.local()
        case .watch:
            // This adapter runs in the phone process. HealthKit must attribute a
            // Watch-origin import itself; manufacturing an HKDevice would forge
            // provenance and does not make the sample a Watch record.
            return nil
        }
    }

    static func lookupError(for error: Error) -> HealthWorkoutLookupError {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain else {
            return .queryFailed
        }
        switch HKError.Code(rawValue: nsError.code) {
        case .errorDatabaseInaccessible:
            return .protectedDataUnavailable
        case .errorHealthDataUnavailable, .errorHealthDataRestricted:
            return .healthDataUnavailable
        default:
            return .queryFailed
        }
    }

    static func healthKitActivityType(
        for activity: HealthWorkoutActivity
    ) -> HKWorkoutActivityType? {
        switch activity {
        case .americanFootball: return .americanFootball
        case .archery: return .archery
        case .australianFootball: return .australianFootball
        case .badminton: return .badminton
        case .barre: return .barre
        case .baseball: return .baseball
        case .basketball: return .basketball
        case .biking: return .cycling
        case .bowling: return .bowling
        case .boxing: return .boxing
        case .cardioDance: return .cardioDance
        case .climbing: return .climbing
        case .cooldown: return .cooldown
        case .coreTraining: return .coreTraining
        case .cricket: return .cricket
        case .crossCountrySkiing: return .crossCountrySkiing
        case .crossTraining: return .crossTraining
        case .curling: return .curling
        case .discSports: return .discSports
        case .downhillSkiing: return .downhillSkiing
        case .elliptical: return .elliptical
        case .equestrianSports: return .equestrianSports
        case .fencing: return .fencing
        case .fishing: return .fishing
        case .fitnessGaming: return .fitnessGaming
        case .flexibility: return .flexibility
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .golf: return .golf
        case .gymnastics: return .gymnastics
        case .handCycling: return .handCycling
        case .handball: return .handball
        case .highIntensityIntervalTraining: return .highIntensityIntervalTraining
        case .hiking: return .hiking
        case .hockey: return .hockey
        case .hunting: return .hunting
        case .jumpRope: return .jumpRope
        case .kickboxing: return .kickboxing
        case .lacrosse: return .lacrosse
        case .martialArts: return .martialArts
        case .mindAndBody: return .mindAndBody
        case .mixedCardio: return .mixedCardio
        case .other: return .other
        case .paddleSports: return .paddleSports
        case .pickleball: return .pickleball
        case .pilates: return .pilates
        case .play: return .play
        case .preparationAndRecovery: return .preparationAndRecovery
        case .racquetball: return .racquetball
        case .rowing: return .rowing
        case .rugby: return .rugby
        case .running: return .running
        case .sailing: return .sailing
        case .skating: return .skatingSports
        case .snowSports: return .snowSports
        case .snowboarding: return .snowboarding
        case .soccer: return .soccer
        case .socialDance: return .socialDance
        case .softball: return .softball
        case .squash: return .squash
        case .stairClimbing: return .stairClimbing
        case .stairs: return .stairs
        case .stepTraining: return .stepTraining
        case .surfing: return .surfingSports
        case .swimming, .swimmingOpenWater, .swimmingPool: return .swimming
        case .tableTennis: return .tableTennis
        case .taiChi: return .taiChi
        case .tennis: return .tennis
        case .trackAndField: return .trackAndField
        case .traditionalStrengthTraining: return .traditionalStrengthTraining
        case .underwaterDiving:
            if #available(iOS 17.0, macOS 14.0, *) {
                return .underwaterDiving
            }
            return nil
        case .volleyball: return .volleyball
        case .walking: return .walking
        case .waterFitness: return .waterFitness
        case .waterPolo: return .waterPolo
        case .waterSports: return .waterSports
        case .wheelchairRunPace: return .wheelchairRunPace
        case .wheelchairWalkPace: return .wheelchairWalkPace
        case .wrestling: return .wrestling
        case .yoga: return .yoga
        }
    }
}

private final class HealthKitWorkoutBuilder: HealthWorkoutBuilder, @unchecked Sendable {
    private let builder: HKWorkoutBuilder
    private let activeEnergyType: HKQuantityType?
    private let sampleDevice: HKDevice?
    private let lock = NSLock()
    private var energyRecordID: UUID?

    init(
        builder: HKWorkoutBuilder,
        activeEnergyType: HKQuantityType?,
        sampleDevice: HKDevice?
    ) {
        self.builder = builder
        self.activeEnergyType = activeEnergyType
        self.sampleDevice = sampleDevice
    }

    func begin(
        at start: Date,
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    ) {
        builder.beginCollection(withStart: start) { success, error in
            completion(
                success,
                Self.builderError(error, component: .workout)
            )
        }
    }

    func addEnergy(
        kilocalories: Double,
        start: Date,
        end: Date,
        metadata: [String: Any],
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    ) {
        guard let activeEnergyType else {
            completion(false, .operationFailed)
            return
        }
        let quantity = HKQuantity(
            unit: HKUnit.kilocalorie(),
            doubleValue: kilocalories
        )
        let sample = HKCumulativeQuantitySample(
            type: activeEnergyType,
            quantity: quantity,
            start: start,
            end: end,
            device: sampleDevice,
            metadata: metadata
        )
        lock.withLock { energyRecordID = sample.uuid }
        builder.add([sample]) { success, error in
            completion(
                success,
                Self.builderError(error, component: .activeEnergy)
            )
        }
    }

    func addWorkoutMetadata(
        _ metadata: [String: Any],
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    ) {
        builder.addMetadata(metadata) { success, error in
            completion(
                success,
                Self.builderError(error, component: .workout)
            )
        }
    }

    func end(
        at end: Date,
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    ) {
        builder.endCollection(withEnd: end) { success, error in
            completion(
                success,
                Self.builderError(error, component: .workout)
            )
        }
    }

    func finish(
        completion:
            @escaping @Sendable (
                StoredWorkoutAndEnergy?,
                HealthWorkoutBuilderError?
            ) -> Void
    ) {
        builder.finishWorkout { [self] workout, error in
            let stored = workout.map {
                StoredWorkoutAndEnergy(
                    workoutRecordID: $0.uuid,
                    energyRecordID: lock.withLock { energyRecordID }
                )
            }
            completion(
                stored,
                Self.builderError(error, component: .workout)
            )
        }
    }

    func discard() {
        builder.discardWorkout()
    }

    private static func builderError(
        _ error: Error?,
        component: WorkoutComponent
    ) -> HealthWorkoutBuilderError? {
        guard let error else { return nil }
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain else {
            return .operationFailed
        }
        switch HKError.Code(rawValue: nsError.code) {
        case .errorAuthorizationDenied, .errorRequiredAuthorizationDenied:
            return .authorizationDenied(component)
        case .errorAuthorizationNotDetermined:
            return .authorizationNotDetermined(component)
        default:
            return .operationFailed
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
