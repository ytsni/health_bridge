import Foundation
import HealthKit

/// Deletes HealthKit samples using either date-range predicates or explicit UUID lookup.
public final class DeleteService {
    /// Store abstraction used to execute delete queries.
    private let store: HealthStoreProxying

    /// Sample types keyed by plugin data type.
    private let dataTypesDict: [String: HKSampleType]

    /// Characteristic types keyed by plugin data type.
    private let characteristicsTypesDict: [String: HKCharacteristicType]

    /// Creates a delete service with catalog lookups and a store abstraction.
    public init(
        store: HealthStoreProxying,
        dataTypesDict: [String: HKSampleType],
        characteristicsTypesDict: [String: HKCharacteristicType]
    ) {
        self.store = store
        self.dataTypesDict = dataTypesDict
        self.characteristicsTypesDict = characteristicsTypesDict
    }

    /// Deletes samples of the requested type owned by this app within the given date range.
    public func delete(_ request: DeleteRequest, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard characteristicsTypesDict[request.dataTypeKey] == nil else {
            completion(.success(false))
            return
        }

        guard let dataType = dataTypesDict[request.dataTypeKey] else {
            completion(.success(false))
            return
        }

        let samplePredicate = HKQuery.predicateForSamples(
            withStart: request.dateRange.startDate,
            end: request.dateRange.endDate,
            options: .strictStartDate
        )
        let ownerPredicate = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [samplePredicate, ownerPredicate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: dataType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            guard let samples else {
                completion(.success(false))
                return
            }

            if samples.isEmpty {
                completion(.success(true))
                return
            }

            self.store.delete(samples, completion: deleteResult(completion))
        }

        store.execute(query)
    }

    /// Deletes a single sample identified by UUID when the type key resolves to a sample type.
    public func deleteByUUID(_ request: DeleteByUUIDRequest, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let dataType = dataTypesDict[request.dataTypeKey] else {
            completion(.success(false))
            return
        }

        let predicate = HKQuery.predicateForObjects(with: [request.uuid])
        let query = HKSampleQuery(sampleType: dataType, predicate: predicate, limit: 1, sortDescriptors: nil) {
            [weak self] _, samples, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            guard let samples, !samples.isEmpty else {
                completion(.success(false))
                return
            }

            self.store.delete(samples, completion: deleteResult(completion))
        }

        store.execute(query)
    }

    /// Adapts HealthKit's delete callback shape to the service's `Result`-based completion.
    private func deleteResult(
        _ completion: @escaping (Result<Bool, Error>) -> Void
    ) -> (Bool, Error?) -> Void {
        { success, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(success))
            }
        }
    }
}
