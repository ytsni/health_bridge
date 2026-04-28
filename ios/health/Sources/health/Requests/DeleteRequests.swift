import Foundation

/// Typed payload for delete-by-range operations.
public struct DeleteRequest: Equatable {
    /// The plugin data type key to delete.
    let dataTypeKey: String

    /// The date range used to select samples.
    let dateRange: DateRange

    /// Decodes a delete request using `dataTypeKey`, `startTime`, and `endTime`.
    public static func parse(arguments: NSDictionary?) throws -> DeleteRequest {
        guard let arguments,
              let dataTypeKey = arguments["dataTypeKey"] as? String
        else {
            throw PluginError(message: "Missing dataTypeKey in arguments")
        }

        let startTime = (arguments["startTime"] as? NSNumber) ?? 0
        let endTime = (arguments["endTime"] as? NSNumber) ?? 0

        return DeleteRequest(
            dataTypeKey: dataTypeKey,
            dateRange: DateRange(startTimeMillis: startTime, endTimeMillis: endTime)
        )
    }
}

/// Typed payload for delete-by-UUID operations.
public struct DeleteByUUIDRequest: Equatable {
    /// The plugin data type key to delete.
    let dataTypeKey: String

    /// The UUID of the sample to delete.
    let uuid: UUID

    /// Decodes a UUID-targeted delete request from Flutter arguments.
    public static func parse(arguments: NSDictionary?) throws -> DeleteByUUIDRequest {
        guard let arguments,
              let uuidString = arguments["uuid"] as? String,
              let dataTypeKey = arguments["dataTypeKey"] as? String,
              let uuid = UUID(uuidString: uuidString)
        else {
            throw PluginError(message: "Invalid Arguments - UUID or DataTypeKey invalid")
        }

        return DeleteByUUIDRequest(dataTypeKey: dataTypeKey, uuid: uuid)
    }
}
