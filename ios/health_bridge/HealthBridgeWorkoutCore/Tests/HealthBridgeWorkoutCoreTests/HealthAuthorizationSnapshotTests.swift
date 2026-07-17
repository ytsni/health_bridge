import Foundation
import HealthKit
import XCTest

@testable import HealthBridgeWorkoutCore

final class HealthAuthorizationSnapshotTests: XCTestCase {
    func testHealthKitSharingStatusesMapExactly() {
        XCTAssertEqual(
            HealthKitWorkoutStore.writeAuthorization(from: .sharingAuthorized),
            .authorized
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.writeAuthorization(from: .sharingDenied),
            .denied
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.writeAuthorization(from: .notDetermined),
            .notDetermined
        )
    }

    func testExactSharingStatusesMapIndependentlyAndReadsRemainUnknown() throws {
        let cases: [(WriteAuthorization, AuthorizationState)] = [
            (.authorized, .authorized),
            (.denied, .denied),
            (.notDetermined, .notDetermined),
        ]

        for (workoutAuthorization, workoutState) in cases {
            for (energyAuthorization, energyState) in cases {
                let store = AuthorizationFakeWorkoutStore(
                    workoutAuthorization: workoutAuthorization,
                    energyAuthorization: energyAuthorization
                )
                let operations = try HealthWorkoutOperations(store: store)

                let snapshot = try operations.authorizationSnapshot(
                    for: ["ACTIVE_ENERGY_BURNED", "WORKOUT"]
                )

                XCTAssertTrue(snapshot.available)
                XCTAssertNil(snapshot.platformCode)
                XCTAssertEqual(
                    snapshot.types,
                    [
                        try HealthTypeAuthorization(
                            type: "ACTIVE_ENERGY_BURNED",
                            read: .requestedOrUnknown,
                            write: energyState
                        ),
                        try HealthTypeAuthorization(
                            type: "WORKOUT",
                            read: .requestedOrUnknown,
                            write: workoutState
                        ),
                    ]
                )
                XCTAssertEqual(
                    store.authorizationTypeNames,
                    ["ACTIVE_ENERGY_BURNED", "WORKOUT"]
                )
                XCTAssertEqual(store.lookupCount, 0)
            }
        }
    }

    func testMappedScalarAndSleepTypesReportExactWritesAndUnknownReads() throws {
        let store = AuthorizationFakeWorkoutStore(
            workoutAuthorization: .authorized,
            energyAuthorization: .authorized,
            additionalTypeAuthorizations: [
                "BODY_FAT_PERCENTAGE": .notDetermined,
                "SLEEP_ASLEEP": .denied,
                "WEIGHT": .authorized,
            ]
        )
        let operations = try HealthWorkoutOperations(store: store)

        let snapshot = try operations.authorizationSnapshot(
            for: ["WEIGHT", "BODY_FAT_PERCENTAGE", "SLEEP_ASLEEP"]
        )

        XCTAssertTrue(snapshot.available)
        XCTAssertEqual(
            snapshot.types,
            [
                try HealthTypeAuthorization(
                    type: "BODY_FAT_PERCENTAGE",
                    read: .requestedOrUnknown,
                    write: .notDetermined
                ),
                try HealthTypeAuthorization(
                    type: "SLEEP_ASLEEP",
                    read: .requestedOrUnknown,
                    write: .denied
                ),
                try HealthTypeAuthorization(
                    type: "WEIGHT",
                    read: .requestedOrUnknown,
                    write: .authorized
                ),
            ]
        )
        XCTAssertEqual(
            store.authorizationTypeNames,
            ["WEIGHT", "BODY_FAT_PERCENTAGE", "SLEEP_ASLEEP"]
        )
        XCTAssertEqual(store.lookupCount, 0)
    }

    func testUnmappedTypeIsExplicitWithoutHealthKitAuthorizationOrReadQuery() throws {
        let store = AuthorizationFakeWorkoutStore(
            workoutAuthorization: .authorized,
            energyAuthorization: .authorized
        )
        let operations = try HealthWorkoutOperations(store: store)

        let snapshot = try operations.authorizationSnapshot(
            for: ["UNMAPPED_DART_TYPE"]
        )

        XCTAssertTrue(snapshot.available)
        XCTAssertEqual(
            snapshot.types,
            [
                try HealthTypeAuthorization(
                    type: "UNMAPPED_DART_TYPE",
                    read: .unsupported,
                    write: .unsupported
                )
            ]
        )
        XCTAssertEqual(store.authorizationTypeNames, ["UNMAPPED_DART_TYPE"])
        XCTAssertEqual(store.lookupCount, 0)
    }

    func testWriteRevocationBetweenSnapshotsIsReflected() throws {
        let store = AuthorizationFakeWorkoutStore(
            workoutAuthorization: .authorized,
            energyAuthorization: .authorized,
            additionalTypeAuthorizations: ["WEIGHT": .authorized]
        )
        let operations = try HealthWorkoutOperations(store: store)

        let beforeRevocation = try operations.authorizationSnapshot(for: ["WEIGHT"])
        store.setAuthorization(.denied, for: "WEIGHT")
        let afterRevocation = try operations.authorizationSnapshot(for: ["WEIGHT"])

        XCTAssertEqual(beforeRevocation.types.first?.write, .authorized)
        XCTAssertEqual(afterRevocation.types.first?.write, .denied)
        XCTAssertEqual(
            store.authorizationTypeNames,
            ["WEIGHT", "WEIGHT"]
        )
    }

    func testUnavailableHealthDataMakesEveryRequestedAccessUnavailable() throws {
        let store = AuthorizationFakeWorkoutStore(
            isHealthDataAvailable: false,
            workoutAuthorization: .authorized,
            energyAuthorization: .authorized
        )
        let operations = try HealthWorkoutOperations(store: store)

        let snapshot = try operations.authorizationSnapshot(
            for: ["WORKOUT", "ACTIVE_ENERGY_BURNED", "WEIGHT", "SLEEP_ASLEEP"]
        )

        XCTAssertFalse(snapshot.available)
        XCTAssertEqual(snapshot.platformCode, "healthDataUnavailable")
        XCTAssertEqual(
            snapshot.types,
            [
                try HealthTypeAuthorization(
                    type: "ACTIVE_ENERGY_BURNED",
                    read: .unavailable,
                    write: .unavailable
                ),
                try HealthTypeAuthorization(
                    type: "SLEEP_ASLEEP",
                    read: .unavailable,
                    write: .unavailable
                ),
                try HealthTypeAuthorization(
                    type: "WEIGHT",
                    read: .unavailable,
                    write: .unavailable
                ),
                try HealthTypeAuthorization(
                    type: "WORKOUT",
                    read: .unavailable,
                    write: .unavailable
                ),
            ]
        )
        XCTAssertEqual(store.authorizationTypeNames, [])
        XCTAssertEqual(store.lookupCount, 0)
    }
}

private final class AuthorizationFakeWorkoutStore: HealthWorkoutStore, @unchecked Sendable {
    private let lock = NSLock()
    private var typeAuthorizations: [String: WriteAuthorization]
    private var capturedAuthorizationTypeNames: [String] = []
    private var capturedLookupCount = 0

    let isHealthDataAvailable: Bool

    init(
        isHealthDataAvailable: Bool = true,
        workoutAuthorization: WriteAuthorization,
        energyAuthorization: WriteAuthorization,
        additionalTypeAuthorizations: [String: WriteAuthorization] = [:]
    ) {
        self.isHealthDataAvailable = isHealthDataAvailable
        typeAuthorizations = additionalTypeAuthorizations.merging(
            [
                "WORKOUT": workoutAuthorization,
                "ACTIVE_ENERGY_BURNED": energyAuthorization,
            ],
            uniquingKeysWith: { _, base in base }
        )
    }

    var authorizationTypeNames: [String] {
        lock.withLock { capturedAuthorizationTypeNames }
    }

    var lookupCount: Int { lock.withLock { capturedLookupCount } }

    func lookup(
        component: WorkoutComponent,
        clientRecordId: String,
        start: Date,
        end: Date,
        completion:
            @escaping @Sendable (
                Result<[StoredRecordIdentity], HealthWorkoutLookupError>
            ) -> Void
    ) {
        lock.withLock { capturedLookupCount += 1 }
        completion(.success([]))
    }

    func writeAuthorization(for component: WorkoutComponent) -> WriteAuthorization {
        lock.withLock {
            typeAuthorizations[
                component == .workout ? "WORKOUT" : "ACTIVE_ENERGY_BURNED"
            ]!
        }
    }

    func writeAuthorization(for type: String) -> WriteAuthorization? {
        lock.withLock {
            capturedAuthorizationTypeNames.append(type)
            return typeAuthorizations[type]
        }
    }

    func setAuthorization(_ authorization: WriteAuthorization, for type: String) {
        lock.withLock { typeAuthorizations[type] = authorization }
    }

    func makeBuilder(for request: WorkoutWriteRequest) throws -> HealthWorkoutBuilder {
        throw HealthWorkoutStoreError.builderUnavailable
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
