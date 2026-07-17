import HealthKit
import XCTest

@testable import HealthBridgeWorkoutCore

final class HealthSampleClientIdentityTests: XCTestCase {
    func testSyncIdentifierWinsAndCarriesVersion() {
        let identity = HealthSampleClientIdentity.extract(from: [
            HKMetadataKeySyncIdentifier: " sync-id ",
            HKMetadataKeySyncVersion: NSNumber(value: 7),
            HKMetadataKeyExternalUUID: "external-id",
        ])

        XCTAssertEqual(
            identity,
            HealthSampleClientIdentity(
                recordID: "sync-id",
                kind: .healthKitSyncIdentifier,
                recordVersion: 7
            )
        )
    }

    func testExternalUUIDIsFallbackWithoutUnrelatedSyncVersion() {
        let identity = HealthSampleClientIdentity.extract(from: [
            HKMetadataKeySyncIdentifier: "  ",
            HKMetadataKeySyncVersion: NSNumber(value: 9),
            HKMetadataKeyExternalUUID: " external-id ",
        ])

        XCTAssertEqual(
            identity,
            HealthSampleClientIdentity(
                recordID: "external-id",
                kind: .healthKitExternalUuid,
                recordVersion: nil
            )
        )
    }

    func testMissingOrNonStringIdentityIsOmitted() {
        XCTAssertNil(HealthSampleClientIdentity.extract(from: nil))
        XCTAssertNil(HealthSampleClientIdentity.extract(from: [:]))
        XCTAssertNil(HealthSampleClientIdentity.extract(from: [
            HKMetadataKeySyncIdentifier: 7,
            HKMetadataKeyExternalUUID: "\n",
        ]))
    }
}
