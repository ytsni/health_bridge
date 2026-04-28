import Foundation
import HealthKit

/// Reads HealthKit samples and delegates serialization to type-specific serializers.
final class SampleReadService {
    /// Store abstraction used to execute sample queries.
    private let store: HealthStoreProxying

    /// Sample types keyed by plugin data type.
    private let dataTypesDict: [String: HKSampleType]

    /// Units keyed by plugin unit key.
    private let unitDict: [String: HKUnit]

    /// Workout activity translator used to map HealthKit workouts back to plugin keys.
    private let workoutActivityCoder: any WorkoutActivityTypeCoding

    /// Reader for characteristic values exposed outside sample queries.
    private let characteristicService: any CharacteristicReading

    /// Reader for workout route samples.
    private let workoutRouteService: any WorkoutRouteReading

    /// Reader for ECG samples.
    private let ecgService: any ECGReading

    /// Registry that serializes concrete sample subtypes.
    private let serializerRegistry: any SampleSerializing

    /// Creates a sample reader with its specialized collaborators.
    init(
        store: HealthStoreProxying,
        dataTypesDict: [String: HKSampleType],
        unitDict: [String: HKUnit],
        workoutActivityCoder: any WorkoutActivityTypeCoding,
        characteristicService: any CharacteristicReading,
        workoutRouteService: any WorkoutRouteReading,
        ecgService: any ECGReading,
        serializerRegistry: any SampleSerializing = SampleSerializerRegistry()
    ) {
        self.store = store
        self.dataTypesDict = dataTypesDict
        self.unitDict = unitDict
        self.workoutActivityCoder = workoutActivityCoder
        self.characteristicService = characteristicService
        self.workoutRouteService = workoutRouteService
        self.ecgService = ecgService
        self.serializerRegistry = serializerRegistry
    }

    /// Reads samples for the supplied request and returns either a list payload or
    /// a single value for UUID lookups.
    func read(_ request: SampleReadRequest, completion: @escaping (Result<Any?, Error>) -> Void) {
        switch characteristicService.read(for: request) {
        case let .success(.some(characteristicPayload)):
            completion(.success(request.isUUIDLookup ? characteristicPayload.first : characteristicPayload))
            return
        case .success(.none):
            break
        case let .failure(error):
            completion(.failure(error))
            return
        }

        guard let dataType = dataTypesDict[request.dataTypeKey] else {
            completion(.failure(PluginError(message: "Invalid dataTypeKey: \(request.dataTypeKey)")))
            return
        }

        let predicate = buildPredicate(for: request)
        let sortDescriptors = request.isUUIDLookup ? nil : [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        let query = HKSampleQuery(sampleType: dataType, predicate: predicate, limit: request.limit, sortDescriptors: sortDescriptors) {
            [weak self] _, samples, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }
            guard let samples else {
                completion(.success(request.isUUIDLookup ? nil : []))
                return
            }

            if request.dataTypeKey == HealthConstants.WORKOUT_ROUTE {
                self.workoutRouteService.read(
                    samples: samples,
                    includeManualEntries: request.includeManualEntries,
                    singleResult: request.isUUIDLookup,
                    completion: completion
                )
                return
            }

            if request.dataTypeKey == HealthConstants.ELECTROCARDIOGRAM {
                self.ecgService.read(samples: samples, singleResult: request.isUUIDLookup, completion: completion)
                return
            }

            let context = SampleSerializationContext(
                dataTypeKey: request.dataTypeKey,
                unit: request.dataUnitKey.flatMap { self.unitDict[$0] },
                workoutActivityCoder: self.workoutActivityCoder
            )
            let dictionaries = serializerRegistry.serialize(samples: samples, context: context)
            completion(.success(request.isUUIDLookup ? dictionaries.first : dictionaries))
        }

        store.execute(query)
    }

    /// Builds the HealthKit predicate used for either UUID lookups or range queries.
    private func buildPredicate(for request: SampleReadRequest) -> NSPredicate {
        if let uuid = request.uuid {
            return HKQuery.predicateForObjects(with: [uuid])
        }

        let base = HKQuery.predicateForSamples(
            withStart: request.dateRange?.startDate,
            end: request.dateRange?.endDate,
            options: .strictStartDate
        )
        guard !request.includeManualEntries else { return base }
        let manualPredicate = NSPredicate(format: "metadata.%K != YES", HKMetadataKeyWasUserEntered)
        return NSCompoundPredicate(type: .and, subpredicates: [base, manualPredicate])
    }
}
