import Foundation
import HealthKit
import XCTest

@testable import HealthBridgeWorkoutCore

final class HealthWorkoutLookupTests: XCTestCase {
    private let workoutClientID = "018f8d7e-1111-7111-8111-111111111111"
    private let energyClientID = "018f8d7e-2222-7222-8222-222222222222"
    private let workoutNativeID = UUID(uuidString: "018f8d7e-aaaa-7aaa-8aaa-aaaaaaaaaaaa")!
    private let energyNativeID = UUID(uuidString: "018f8d7e-bbbb-7bbb-8bbb-bbbbbbbbbbbb")!
    private let start = Date(timeIntervalSince1970: 1_735_700_400)
    private let end = Date(timeIntervalSince1970: 1_735_704_000)

    func testConcreteHealthKitErrorsPreserveLockedAndUnavailableStates() {
        XCTAssertEqual(
            HealthKitWorkoutStore.lookupError(
                for: NSError(
                    domain: HKErrorDomain,
                    code: HKError.Code.errorDatabaseInaccessible.rawValue
                )
            ),
            .protectedDataUnavailable
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.lookupError(
                for: NSError(
                    domain: HKErrorDomain,
                    code: HKError.Code.errorHealthDataUnavailable.rawValue
                )
            ),
            .healthDataUnavailable
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.lookupError(
                for: NSError(domain: "test.query", code: 1)
            ),
            .queryFailed
        )
    }

    func testConcreteLookupPredicateUsesHealthKitMetadataKeyPath() {
        let predicate = HealthKitWorkoutStore.lookupMetadataPredicate(
            clientRecordId: workoutClientID
        )

        let metadataClause = String(describing: predicate)
        XCTAssertTrue(
            metadataClause.contains(
                "metadata.\(HKMetadataKeySyncIdentifier)"
            ),
            "Concrete lookup must use HealthKit's metadata key path; got \(metadataClause)"
        )
    }

    func testFullLookupReturnsIndependentRealNativeIdentifiers() throws {
        let store = LookupFakeWorkoutStore(
            workoutResult: .success([
                candidate(id: workoutNativeID, clientID: workoutClientID)
            ]),
            energyResult: .success([
                candidate(id: energyNativeID, clientID: energyClientID)
            ])
        )

        let result = try awaitLookup(store: store, energyExpected: true)

        XCTAssertEqual(result.workout.status, .present)
        XCTAssertEqual(result.workout.recordId, workoutNativeID.uuidString)
        XCTAssertEqual(result.energy.status, .present)
        XCTAssertEqual(result.energy.recordId, energyNativeID.uuidString)
        XCTAssertEqual(result.derivedStatus, .present)
        XCTAssertNil(result.platformCode)
        XCTAssertEqual(
            store.invocations,
            [
                LookupInvocation(
                    component: .workout,
                    clientRecordID: workoutClientID,
                    start: start,
                    end: end
                ),
                LookupInvocation(
                    component: .activeEnergy,
                    clientRecordID: energyClientID,
                    start: start,
                    end: end
                ),
            ]
        )
    }

    func testWorkoutOnlyAndNoEnergyRequestsDeriveWithoutBackfill() throws {
        let expectedEnergyStore = LookupFakeWorkoutStore(
            workoutResult: .success([
                candidate(id: workoutNativeID, clientID: workoutClientID)
            ]),
            energyResult: .success([])
        )

        let expectedEnergy = try awaitLookup(
            store: expectedEnergyStore,
            energyExpected: true
        )

        XCTAssertEqual(expectedEnergy.workout.status, .present)
        XCTAssertEqual(expectedEnergy.energy.status, .absent)
        XCTAssertEqual(expectedEnergy.derivedStatus, .workoutOnly)

        let noEnergyStore = LookupFakeWorkoutStore(
            workoutResult: .success([
                candidate(id: workoutNativeID, clientID: workoutClientID)
            ]),
            energyResult: .failure(.queryFailed)
        )

        let noEnergy = try awaitLookup(
            store: noEnergyStore,
            energyExpected: false
        )

        XCTAssertEqual(noEnergy.workout.status, .present)
        XCTAssertEqual(noEnergy.energy.status, .notExpected)
        XCTAssertEqual(noEnergy.derivedStatus, .workoutOnly)
        XCTAssertEqual(noEnergyStore.invocations.map(\.component), [.workout])
    }

    func testSuccessfulEmptyQueriesAreAbsent() throws {
        let store = LookupFakeWorkoutStore(
            workoutResult: .success([]),
            energyResult: .success([])
        )

        let result = try awaitLookup(store: store, energyExpected: true)

        XCTAssertEqual(result.workout.status, .absent)
        XCTAssertEqual(result.energy.status, .absent)
        XCTAssertEqual(result.derivedStatus, .absent)
        XCTAssertNil(result.platformCode)
    }

    func testQueryAndProtectedDataFailuresRemainUnavailableNotAbsent() throws {
        let workoutFailureStore = LookupFakeWorkoutStore(
            workoutResult: .failure(.queryFailed),
            energyResult: .success([
                candidate(id: energyNativeID, clientID: energyClientID)
            ])
        )

        let workoutFailure = try awaitLookup(
            store: workoutFailureStore,
            energyExpected: true
        )

        XCTAssertEqual(workoutFailure.workout.status, .unavailable)
        XCTAssertEqual(workoutFailure.energy.status, .present)
        XCTAssertEqual(workoutFailure.derivedStatus, .unavailable)
        XCTAssertEqual(workoutFailure.platformCode, "healthKitLookupFailed")

        let lockedEnergyStore = LookupFakeWorkoutStore(
            workoutResult: .success([
                candidate(id: workoutNativeID, clientID: workoutClientID)
            ]),
            energyResult: .failure(.protectedDataUnavailable)
        )

        let lockedEnergy = try awaitLookup(
            store: lockedEnergyStore,
            energyExpected: true
        )

        XCTAssertEqual(lockedEnergy.workout.status, .present)
        XCTAssertEqual(lockedEnergy.energy.status, .unavailable)
        XCTAssertEqual(lockedEnergy.derivedStatus, .unavailable)
        XCTAssertEqual(
            lockedEnergy.platformCode,
            "healthKitProtectedDataUnavailable"
        )
    }

    func testEnergyWithoutWorkoutIsInconsistent() throws {
        let store = LookupFakeWorkoutStore(
            workoutResult: .success([]),
            energyResult: .success([
                candidate(id: energyNativeID, clientID: energyClientID)
            ])
        )

        let result = try awaitLookup(store: store, energyExpected: true)

        XCTAssertEqual(result.workout.status, .absent)
        XCTAssertEqual(result.energy.status, .present)
        XCTAssertEqual(result.energy.recordId, energyNativeID.uuidString)
        XCTAssertEqual(result.derivedStatus, .inconsistent)
    }

    func testWrongSourceAndEitherWrongIdentifierAreIgnored() throws {
        let otherSourceWorkout = candidate(
            id: UUID(),
            clientID: workoutClientID,
            isFromCurrentSource: false
        )
        let wrongWorkoutSync = candidate(
            id: UUID(),
            clientID: workoutClientID,
            syncIdentifier: energyClientID
        )
        let wrongWorkoutExternal = candidate(
            id: UUID(),
            clientID: workoutClientID,
            externalIdentifier: energyClientID
        )
        let otherSourceEnergy = candidate(
            id: UUID(),
            clientID: energyClientID,
            isFromCurrentSource: false
        )
        let wrongEnergySync = candidate(
            id: UUID(),
            clientID: energyClientID,
            syncIdentifier: workoutClientID
        )
        let wrongEnergyExternal = candidate(
            id: UUID(),
            clientID: energyClientID,
            externalIdentifier: workoutClientID
        )
        let store = LookupFakeWorkoutStore(
            workoutResult: .success([
                otherSourceWorkout,
                wrongWorkoutSync,
                wrongWorkoutExternal,
            ]),
            energyResult: .success([
                otherSourceEnergy,
                wrongEnergySync,
                wrongEnergyExternal,
            ])
        )

        let result = try awaitLookup(store: store, energyExpected: true)

        XCTAssertEqual(result.workout.status, .absent)
        XCTAssertEqual(result.energy.status, .absent)
        XCTAssertEqual(result.derivedStatus, .absent)
    }

    func testMultipleExactMatchesAreUnavailableWithoutArbitraryIdentifier() throws {
        for duplicateComponent in [WorkoutComponent.workout, .activeEnergy] {
            let store = LookupFakeWorkoutStore(
                workoutResult: .success(
                    duplicateComponent == .workout
                        ? [
                            candidate(id: UUID(), clientID: workoutClientID),
                            candidate(id: UUID(), clientID: workoutClientID),
                        ]
                        : [candidate(id: workoutNativeID, clientID: workoutClientID)]
                ),
                energyResult: .success(
                    duplicateComponent == .activeEnergy
                        ? [
                            candidate(id: UUID(), clientID: energyClientID),
                            candidate(id: UUID(), clientID: energyClientID),
                        ]
                        : [candidate(id: energyNativeID, clientID: energyClientID)]
                )
            )

            let result = try awaitLookup(store: store, energyExpected: true)

            let duplicate =
                duplicateComponent == .workout
                ? result.workout
                : result.energy
            XCTAssertEqual(duplicate.status, .unavailable)
            XCTAssertNil(duplicate.recordId)
            XCTAssertEqual(result.derivedStatus, .unavailable)
            XCTAssertEqual(result.platformCode, "multipleMatchingRecords")
        }
    }

    func testDeniedGeneralReadStillUsesSuccessfulAppOwnedQuery() throws {
        let store = LookupFakeWorkoutStore(
            workoutResult: .success([
                candidate(id: workoutNativeID, clientID: workoutClientID)
            ]),
            energyResult: .success([])
        )
        store.generalReadVisible = false

        let result = try awaitLookup(store: store, energyExpected: true)

        XCTAssertFalse(store.generalReadVisible)
        XCTAssertEqual(result.derivedStatus, .workoutOnly)
        XCTAssertEqual(store.writeAuthorizationCount, 0)
    }

    private func awaitLookup(
        store: LookupFakeWorkoutStore,
        energyExpected: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> WorkoutLookupResult {
        let operations = try HealthWorkoutOperations(store: store)
        let request = try WorkoutLookupRequest(
            workoutClientRecordId: workoutClientID,
            energyClientRecordId: energyExpected ? energyClientID : nil,
            start: start,
            end: end
        )
        let capture = LookupResultCapture()
        let completion = expectation(description: "lookup completion")
        completion.assertForOverFulfill = true

        operations.lookup(request) { result in
            let count = capture.append(result)
            if count == 1 {
                completion.fulfill()
            }
        }

        wait(for: [completion], timeout: 1)
        XCTAssertEqual(capture.results.count, 1, file: file, line: line)
        guard let result = capture.results.first else {
            XCTFail("lookup did not complete", file: file, line: line)
            fatalError("lookup did not complete")
        }
        return result
    }

    private func candidate(
        id: UUID,
        clientID: String,
        syncIdentifier: String? = nil,
        externalIdentifier: String? = nil,
        isFromCurrentSource: Bool = true
    ) -> StoredRecordIdentity {
        StoredRecordIdentity(
            recordID: id,
            syncIdentifier: syncIdentifier ?? clientID,
            externalIdentifier: externalIdentifier ?? clientID,
            isFromCurrentSource: isFromCurrentSource
        )
    }
}

private struct LookupInvocation: Equatable, Sendable {
    let component: WorkoutComponent
    let clientRecordID: String
    let start: Date
    let end: Date
}

private final class LookupFakeWorkoutStore: HealthWorkoutStore, @unchecked Sendable {
    private let lock = NSLock()
    private let workoutResult: Result<[StoredRecordIdentity], HealthWorkoutLookupError>
    private let energyResult: Result<[StoredRecordIdentity], HealthWorkoutLookupError>
    private var capturedInvocations: [LookupInvocation] = []
    private var capturedWriteAuthorizationCount = 0

    var isHealthDataAvailable = true
    var generalReadVisible = true

    init(
        workoutResult: Result<[StoredRecordIdentity], HealthWorkoutLookupError>,
        energyResult: Result<[StoredRecordIdentity], HealthWorkoutLookupError>
    ) {
        self.workoutResult = workoutResult
        self.energyResult = energyResult
    }

    var invocations: [LookupInvocation] {
        lock.withLock { capturedInvocations }
    }

    var writeAuthorizationCount: Int {
        lock.withLock { capturedWriteAuthorizationCount }
    }

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
        let result = lock.withLock { () -> Result<[StoredRecordIdentity], HealthWorkoutLookupError> in
            capturedInvocations.append(
                LookupInvocation(
                    component: component,
                    clientRecordID: clientRecordId,
                    start: start,
                    end: end
                )
            )
            return component == .workout ? workoutResult : energyResult
        }
        completion(result)
    }

    func writeAuthorization(for component: WorkoutComponent) -> WriteAuthorization {
        lock.withLock { capturedWriteAuthorizationCount += 1 }
        return .denied
    }

    func makeBuilder(for request: WorkoutWriteRequest) throws -> HealthWorkoutBuilder {
        throw HealthWorkoutStoreError.builderUnavailable
    }
}

private final class LookupResultCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [WorkoutLookupResult] = []

    var results: [WorkoutLookupResult] { lock.withLock { storage } }

    @discardableResult
    func append(_ result: WorkoutLookupResult) -> Int {
        lock.withLock {
            storage.append(result)
            return storage.count
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
