import Foundation
import HealthKit

/// Validates and builds the identity metadata for generic scalar samples.
///
/// `writeData` predates the workout-specific channel and accepts nullable
/// identity fields from Dart. Keeping this parsing pure makes the pair contract
/// testable without a real HealthKit store: either both fields are absent for
/// a legacy unowned sample, or both form the cross-platform sync identity used
/// by Health Connect. Sync identifiers may be arbitrary nonblank strings;
/// HealthKit's external UUID metadata is added only when that identifier is a
/// UUID.
enum HealthDataClientRecordMetadata {
    static func make(
        isManualEntry: Bool,
        clientRecordId rawClientRecordId: Any?,
        clientRecordVersion rawClientRecordVersion: Any?
    ) throws -> [String: Any] {
        let clientRecordId = normalizedOptional(rawClientRecordId)
        let clientRecordVersion = normalizedOptional(rawClientRecordVersion)

        var metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: NSNumber(value: isManualEntry),
        ]

        switch (clientRecordId, clientRecordVersion) {
        case (nil, nil):
            return metadata
        case let (id as String, version as NSNumber):
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HealthDataClientRecordMetadataError.invalidClientRecordId
            }
            let parsedVersion = try parseVersion(version)
            metadata[HKMetadataKeySyncIdentifier] = id
            metadata[HKMetadataKeySyncVersion] = parsedVersion
            if UUID(uuidString: id) != nil {
                metadata[HKMetadataKeyExternalUUID] = id
            }
            return metadata
        case (nil, _), (_, nil):
            throw HealthDataClientRecordMetadataError.incompleteClientRecordIdentity
        default:
            throw HealthDataClientRecordMetadataError.invalidClientRecordIdentity
        }
    }

    private static func normalizedOptional(_ value: Any?) -> Any? {
        value is NSNull ? nil : value
    }

    private static func parseVersion(_ value: NSNumber) throws -> Int {
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            throw HealthDataClientRecordMetadataError.invalidClientRecordVersion
        }
        let doubleValue = value.doubleValue
        guard doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue >= 0,
              let version = Int(exactly: doubleValue)
        else {
            throw HealthDataClientRecordMetadataError.invalidClientRecordVersion
        }
        return version
    }
}

enum HealthDataClientRecordMetadataError: Error, Equatable {
    case incompleteClientRecordIdentity
    case invalidClientRecordIdentity
    case invalidClientRecordId
    case invalidClientRecordVersion
}
