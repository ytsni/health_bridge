import Foundation
import HealthKit

/// Inclusive date window decoded from Flutter millisecond timestamps.
public struct DateRange: Equatable {
    /// The first date included in the range.
    let startDate: Date

    /// The last date included in the range.
    let endDate: Date

    /// Converts epoch millisecond arguments into Foundation dates.
    init(startTimeMillis: NSNumber, endTimeMillis: NSNumber) {
        startDate = HealthUtilities.dateFromMilliseconds(startTimeMillis.doubleValue)
        endDate = HealthUtilities.dateFromMilliseconds(endTimeMillis.doubleValue)
    }
}

/// Typed payload for sample reads after the Flutter argument boundary.
public struct SampleReadRequest: Equatable {
    /// The plugin data type key to read.
    let dataTypeKey: String

    /// The optional plugin unit key used for quantity conversion.
    let dataUnitKey: String?

    /// The optional date range for list reads.
    let dateRange: DateRange?

    /// The optional UUID for single-sample reads.
    let uuid: UUID?

    /// The maximum number of samples to return.
    let limit: Int

    /// Whether manual entries should remain in the result.
    let includeManualEntries: Bool

    /// Indicates whether the read should resolve to a single UUID-addressed sample.
    var isUUIDLookup: Bool { uuid != nil }

    /// Decodes a list-style read request for `getData`.
    ///
    /// Expected keys are `dataTypeKey` plus optional `dataUnitKey`, `startTime`,
    /// `endTime`, `limit`, and `recordingMethodsToFilter`.
    public static func list(arguments: NSDictionary?) throws -> SampleReadRequest {
        guard let arguments,
              let dataTypeKey = arguments["dataTypeKey"] as? String
        else {
            throw PluginError(message: "Missing required dataTypeKey argument")
        }

        let startTime = (arguments["startTime"] as? NSNumber) ?? 0
        let endTime = (arguments["endTime"] as? NSNumber) ?? 0
        let limit = (arguments["limit"] as? Int) ?? HKObjectQueryNoLimit
        let filters = (arguments["recordingMethodsToFilter"] as? [Int]) ?? []

        return SampleReadRequest(
            dataTypeKey: dataTypeKey,
            dataUnitKey: arguments["dataUnitKey"] as? String,
            dateRange: DateRange(startTimeMillis: startTime, endTimeMillis: endTime),
            uuid: nil,
            limit: limit,
            includeManualEntries: !filters.contains(HealthConstants.RecordingMethod.manual.rawValue)
        )
    }

    /// Decodes a UUID-based read request for `getDataByUUID`.
    public static func single(arguments: NSDictionary?) throws -> SampleReadRequest {
        guard let arguments,
              let dataTypeKey = arguments["dataTypeKey"] as? String,
              let uuidString = arguments["uuid"] as? String,
              let uuid = UUID(uuidString: uuidString)
        else {
            throw PluginError(message: "Invalid Arguments - UUID or DataTypeKey invalid")
        }

        return SampleReadRequest(
            dataTypeKey: dataTypeKey,
            dataUnitKey: arguments["dataUnitKey"] as? String,
            dateRange: nil,
            uuid: uuid,
            limit: 1,
            includeManualEntries: true
        )
    }
}

/// Typed payload for interval-based statistics reads.
public struct IntervalReadRequest: Equatable {
    /// The plugin data type key to read.
    let dataTypeKey: String

    /// The optional plugin unit key used for quantity conversion.
    let dataUnitKey: String?

    /// The inclusive date range for the query.
    let dateRange: DateRange

    /// The statistics bucket size in seconds.
    let intervalInSeconds: Int

    /// Whether manual entries should remain in the result.
    let includeManualEntries: Bool

    /// Decodes an interval query request, defaulting missing numeric values to zero or one.
    public static func parse(arguments: NSDictionary?) throws -> IntervalReadRequest {
        let dataTypeKey = (arguments?["dataTypeKey"] as? String) ?? "DEFAULT"
        let startTime = (arguments?["startTime"] as? NSNumber) ?? 0
        let endTime = (arguments?["endTime"] as? NSNumber) ?? 0
        let interval = (arguments?["interval"] as? Int) ?? 1
        let filters = (arguments?["recordingMethodsToFilter"] as? [Int]) ?? []

        return IntervalReadRequest(
            dataTypeKey: dataTypeKey,
            dataUnitKey: arguments?["dataUnitKey"] as? String,
            dateRange: DateRange(startTimeMillis: startTime, endTimeMillis: endTime),
            intervalInSeconds: interval,
            includeManualEntries: !filters.contains(HealthConstants.RecordingMethod.manual.rawValue)
        )
    }
}

/// Typed payload for total-step aggregation over a date range.
public struct TotalStepsRequest: Equatable {
    /// The inclusive date range for the query.
    let dateRange: DateRange

    /// Whether manual entries should remain in the result.
    let includeManualEntries: Bool

    /// Decodes the argument shape used by `getTotalStepsInInterval`.
    public static func parse(arguments: NSDictionary?) -> TotalStepsRequest {
        let startTime = (arguments?["startTime"] as? NSNumber) ?? 0
        let endTime = (arguments?["endTime"] as? NSNumber) ?? 0
        let filters = (arguments?["recordingMethodsToFilter"] as? [Int]) ?? []

        return TotalStepsRequest(
            dateRange: DateRange(startTimeMillis: startTime, endTimeMillis: endTime),
            includeManualEntries: !filters.contains(HealthConstants.RecordingMethod.manual.rawValue)
        )
    }
}
