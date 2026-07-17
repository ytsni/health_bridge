import Foundation
import HealthKit

public enum HealthWorkoutMetadataError: Error, Equatable, Sendable {
    case invalidClientRecordId
    case invalidClientRecordVersion
}

public enum HealthWorkoutMetadata {
    public static func make(
        clientRecordId: String,
        clientRecordVersion: Int,
        provenance: HealthRecordingProvenance
    ) throws -> [String: Any] {
        guard UUID(uuidString: clientRecordId) != nil else {
            throw HealthWorkoutMetadataError.invalidClientRecordId
        }
        guard clientRecordVersion == 0 else {
            throw HealthWorkoutMetadataError.invalidClientRecordVersion
        }

        return [
            HKMetadataKeyExternalUUID: clientRecordId,
            HKMetadataKeySyncIdentifier: clientRecordId,
            HKMetadataKeySyncVersion: clientRecordVersion,
            HKMetadataKeyWasUserEntered: provenance == .manualEntry,
        ]
    }
}
