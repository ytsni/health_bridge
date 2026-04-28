import Foundation
import HealthKit

/// Reads aggregate statistics for interval-based HealthKit queries.
public final class IntervalReadService {
    /// Store abstraction used to execute statistics queries.
    private let store: HealthStoreProxying

    /// Quantity types keyed by plugin data type.
    private let dataQuantityTypesDict: [String: HKQuantityType]

    /// Units keyed by plugin unit key.
    private let unitDict: [String: HKUnit]

    /// Creates an interval reader backed by catalog lookups and `store`.
    public init(
        store: HealthStoreProxying,
        dataQuantityTypesDict: [String: HKQuantityType],
        unitDict: [String: HKUnit]
    ) {
        self.store = store
        self.dataQuantityTypesDict = dataQuantityTypesDict
        self.unitDict = unitDict
    }

    /// Executes a statistics collection query for the requested quantity type.
    public func readInterval(_ request: IntervalReadRequest, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        guard let quantityType = dataQuantityTypesDict[request.dataTypeKey] else {
            completion(.failure(PluginError(message: "Invalid dataTypeKey for interval query: \(request.dataTypeKey)")))
            return
        }

        let predicate = samplePredicate(
            from: request.dateRange,
            includeManualEntries: request.includeManualEntries,
            strictStart: false
        )
        var interval = DateComponents()
        interval.second = request.intervalInSeconds
        let statisticsOptions = statisticsOption(for: quantityType)

        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: statisticsOptions,
            anchorDate: request.dateRange.startDate,
            intervalComponents: interval
        )

        query.initialResultsHandler = { [weak self] _, collection, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            guard let collection else {
                completion(.success([]))
                return
            }

            let dictionaries = self.serializeStatistics(
                collection: collection,
                request: request,
                statisticsOptions: statisticsOptions
            )
            completion(.success(dictionaries))
        }

        store.execute(query)
    }

    /// Computes the total step count across the requested date range.
    public func readTotalSteps(_ request: TotalStepsRequest, completion: @escaping (Result<Int, Error>) -> Void) {
        let sampleType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = samplePredicate(
            from: request.dateRange,
            includeManualEntries: request.includeManualEntries,
            strictStart: true
        )

        let query = HKStatisticsCollectionQuery(
            quantityType: sampleType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: request.dateRange.startDate,
            intervalComponents: DateComponents(day: 1)
        )

        query.initialResultsHandler = { _, results, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let results else {
                completion(.success(0))
                return
            }

            var totalSteps = 0.0
            results.enumerateStatistics(from: request.dateRange.startDate, to: request.dateRange.endDate) {
                statistics, _ in
                totalSteps += statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
            }
            completion(.success(Int(totalSteps)))
        }

        store.execute(query)
    }

    /// Chooses the most appropriate HealthKit aggregation mode for a quantity type.
    public func statisticsOption(for quantityType: HKQuantityType) -> HKStatisticsOptions {
        switch quantityType.aggregationStyle {
        case .cumulative:
            return .cumulativeSum
        case .discreteArithmetic, .discrete:
            return .discreteAverage
        case .discreteTemporallyWeighted:
            return .discreteAverage
        case .discreteEquivalentContinuousLevel:
            return .discreteAverage
        @unknown default:
            return .cumulativeSum
        }
    }

    /// Builds a date predicate and optionally filters out manual entries.
    private func samplePredicate(from range: DateRange, includeManualEntries: Bool, strictStart: Bool) -> NSPredicate {
        let options: HKQueryOptions = strictStart ? .strictStartDate : []
        let datePredicate = HKQuery.predicateForSamples(withStart: range.startDate, end: range.endDate, options: options)
        guard !includeManualEntries else { return datePredicate }
        let manualPredicate = NSPredicate(format: "metadata.%K != YES", HKMetadataKeyWasUserEntered)
        return NSCompoundPredicate(type: .and, subpredicates: [datePredicate, manualPredicate])
    }

    /// Converts each statistics bucket into the dictionary payload expected by Flutter.
    private func serializeStatistics(
        collection: HKStatisticsCollection,
        request: IntervalReadRequest,
        statisticsOptions: HKStatisticsOptions
    ) -> [[String: Any]] {
        guard let dataUnitKey = request.dataUnitKey,
              let unit = unitDict[dataUnitKey]
        else {
            return []
        }

        var dictionaries = [[String: Any]]()
        collection.enumerateStatistics(from: request.dateRange.startDate, to: request.dateRange.endDate) {
            statistic, _ in
            let value: Double? = switch statisticsOptions {
            case .cumulativeSum: statistic.sumQuantity()?.doubleValue(for: unit)
            case .discreteAverage: statistic.averageQuantity()?.doubleValue(for: unit)
            case .discreteMin: statistic.minimumQuantity()?.doubleValue(for: unit)
            case .discreteMax: statistic.maximumQuantity()?.doubleValue(for: unit)
            default: statistic.sumQuantity()?.doubleValue(for: unit)
            }

            guard let value else { return }
            dictionaries.append([
                "value": value,
                "date_from": Int(statistic.startDate.timeIntervalSince1970 * 1000),
                "date_to": Int(statistic.endDate.timeIntervalSince1970 * 1000),
                "source_id": statistic.sources?.first?.bundleIdentifier ?? "",
                "source_name": statistic.sources?.first?.name ?? "",
            ])
        }
        return dictionaries
    }
}
