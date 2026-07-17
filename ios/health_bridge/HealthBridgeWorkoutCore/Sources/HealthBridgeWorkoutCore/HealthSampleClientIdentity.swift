import Foundation
import HealthKit

/// Source-defined identity metadata for a HealthKit object.
public struct HealthSampleClientIdentity: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case healthKitSyncIdentifier
        case healthKitExternalUuid
    }

    public let recordID: String
    public let kind: Kind
    public let recordVersion: Int?

    public init(recordID: String, kind: Kind, recordVersion: Int?) {
        self.recordID = recordID
        self.kind = kind
        self.recordVersion = recordVersion
    }

    /// Prefer HealthKit's sync identity, which is versioned for replacement,
    /// then fall back to the source-provided external UUID. The HealthKit store
    /// UUID is exported separately and is never substituted here.
    public static func extract(from metadata: [String: Any]?) -> Self? {
        guard let metadata else { return nil }
        if let syncID = nonblank(metadata[HKMetadataKeySyncIdentifier]) {
            let version = (metadata[HKMetadataKeySyncVersion] as? NSNumber)?.intValue
            return Self(
                recordID: syncID,
                kind: .healthKitSyncIdentifier,
                recordVersion: version
            )
        }
        if let externalID = nonblank(metadata[HKMetadataKeyExternalUUID]) {
            return Self(
                recordID: externalID,
                kind: .healthKitExternalUuid,
                recordVersion: nil
            )
        }
        return nil
    }

    private static func nonblank(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
