import Foundation
import HealthKit
import XCTest

@testable import HealthBridgeWorkoutCore

final class HealthWorkoutWriteTests: XCTestCase {
    private let workoutClientID = "018f8d7e-1111-7111-8111-111111111111"
    private let energyClientID = "018f8d7e-2222-7222-8222-222222222222"
    private let startEpochMilliseconds: Int64 = 1_735_700_400_000
    private let endEpochMilliseconds: Int64 = 1_735_704_000_000
    private let start = Date(timeIntervalSince1970: 1_735_700_400)
    private let end = Date(timeIntervalSince1970: 1_735_704_000)

    func testActivityMappingCoversEveryCanonicalIOSActivityWithoutAnotherRawNameTable() {
        XCTAssertEqual(HealthWorkoutActivity.allCases.count, 81)
        XCTAssertEqual(
            Set(HealthWorkoutActivity.allCases.map(\.rawValue)).count,
            81
        )

        for activity in HealthWorkoutActivity.allCases {
            XCTAssertNotNil(
                HealthKitWorkoutStore.healthKitActivityType(for: activity),
                "Missing HealthKit mapping for \(activity.rawValue)"
            )
        }

        XCTAssertEqual(
            HealthKitWorkoutStore.healthKitActivityType(for: .biking),
            .cycling
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.healthKitActivityType(for: .skating),
            .skatingSports
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.healthKitActivityType(for: .surfing),
            .surfingSports
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.healthKitActivityType(for: .swimming),
            HealthKitWorkoutStore.healthKitActivityType(for: .swimmingOpenWater)
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.healthKitActivityType(for: .swimming),
            HealthKitWorkoutStore.healthKitActivityType(for: .swimmingPool)
        )
    }

    func testPhoneUsesTheLocalDeviceAndWatchOriginNeverFabricatesAWatch() {
        let phone = HealthKitWorkoutStore.builderDevice(for: .phone)

        XCTAssertNotNil(phone)
        XCTAssertTrue(phone?.isEqual(HKDevice.local()) == true)
        XCTAssertNil(HealthKitWorkoutStore.builderDevice(for: .watch))
    }

    func testPreflightFullMatchReturnsAlreadyPresentWithoutAuthorizationOrBuilder() throws {
        let workoutNativeID = UUID()
        let energyNativeID = UUID()
        let fixture = try Fixture(
            workoutLookupReplies: .one(
                .success([
                    lookupIdentity(
                        id: workoutNativeID,
                        clientID: workoutClientID
                    )
                ])
            ),
            energyLookupReplies: .one(
                .success([
                    lookupIdentity(
                        id: energyNativeID,
                        clientID: energyClientID
                    )
                ])
            )
        )

        let result = execute(
            fixture.operations,
            request: try makeRequest(withEnergy: true)
        )

        assertResult(
            result,
            status: .alreadyPresent,
            workoutRecordID: workoutNativeID.uuidString,
            energyRecordID: energyNativeID.uuidString,
            energyStatus: .alreadyPresent,
            retryable: false,
            certainty: .submitted
        )
        XCTAssertEqual(fixture.store.workoutAuthorizationCount, 0)
        XCTAssertEqual(fixture.store.energyAuthorizationCount, 0)
        XCTAssertEqual(fixture.store.makeBuilderCount, 0)
    }

    func testPreflightWorkoutOnlyIsAlreadyPresentAndNeverBackfillsEnergy() throws {
        let workoutNativeID = UUID()
        let fixture = try Fixture(
            workoutLookupReplies: .one(
                .success([
                    lookupIdentity(
                        id: workoutNativeID,
                        clientID: workoutClientID
                    )
                ])
            ),
            energyLookupReplies: .one(.success([]))
        )

        let result = execute(
            fixture.operations,
            request: try makeRequest(withEnergy: true)
        )

        assertResult(
            result,
            status: .alreadyPresent,
            workoutRecordID: workoutNativeID.uuidString,
            energyStatus: .absent,
            retryable: false,
            certainty: .submitted
        )
        XCTAssertEqual(fixture.store.workoutAuthorizationCount, 0)
        XCTAssertEqual(fixture.store.energyAuthorizationCount, 0)
        XCTAssertEqual(fixture.store.makeBuilderCount, 0)
    }

    func testPreflightWorkoutOnlyRequestDoesNotQueryOrRequireEnergy() throws {
        let workoutNativeID = UUID()
        let fixture = try Fixture(
            workoutLookupReplies: .one(
                .success([
                    lookupIdentity(
                        id: workoutNativeID,
                        clientID: workoutClientID
                    )
                ])
            ),
            energyLookupReplies: .one(.failure(.queryFailed))
        )

        let result = execute(
            fixture.operations,
            request: try makeRequest(withEnergy: false)
        )

        assertResult(
            result,
            status: .alreadyPresent,
            workoutRecordID: workoutNativeID.uuidString,
            energyStatus: .notExpected,
            retryable: false,
            certainty: .submitted
        )
        XCTAssertEqual(fixture.store.lookupCount(for: .activeEnergy), 0)
        XCTAssertEqual(fixture.store.makeBuilderCount, 0)
    }

    func testPreflightEnergyWithoutWorkoutIsInconsistentAndNeverWrites() throws {
        let energyNativeID = UUID()
        let fixture = try Fixture(
            workoutLookupReplies: .one(.success([])),
            energyLookupReplies: .one(
                .success([
                    lookupIdentity(
                        id: energyNativeID,
                        clientID: energyClientID
                    )
                ])
            )
        )

        let result = execute(
            fixture.operations,
            request: try makeRequest(withEnergy: true)
        )

        assertResult(
            result,
            status: .inconsistentNativeState,
            energyRecordID: energyNativeID.uuidString,
            energyStatus: .alreadyPresent,
            retryable: false,
            certainty: .submitted
        )
        XCTAssertEqual(fixture.store.workoutAuthorizationCount, 0)
        XCTAssertEqual(fixture.store.makeBuilderCount, 0)
    }

    func testPreflightUnavailableIsNotSubmittedAndNeverWrites() throws {
        let fixture = try Fixture(
            workoutLookupReplies: .one(.failure(.queryFailed)),
            energyLookupReplies: .one(.success([]))
        )

        let result = execute(
            fixture.operations,
            request: try makeRequest(withEnergy: true)
        )

        assertResult(
            result,
            status: .unavailable,
            energyStatus: .notSubmitted,
            retryable: true,
            certainty: .notSubmitted,
            platformCode: "healthKitLookupFailed"
        )
        XCTAssertEqual(fixture.store.workoutAuthorizationCount, 0)
        XCTAssertEqual(fixture.store.makeBuilderCount, 0)
    }

    func testOnlyAbsentPreflightWritesAndUsesFrozenRequestDates() throws {
        let builder = FakeWorkoutBuilder()
        let fixture = try Fixture(builders: [builder])
        let request = try makeRequest(withEnergy: true)

        let result = execute(fixture.operations, request: request)

        XCTAssertEqual(result.status, .written)
        XCTAssertEqual(
            fixture.store.lookupCalls,
            [
                WriteLookupCall(
                    component: .workout,
                    clientRecordID: workoutClientID,
                    start: request.start,
                    end: request.end
                ),
                WriteLookupCall(
                    component: .activeEnergy,
                    clientRecordID: energyClientID,
                    start: request.start,
                    end: request.end
                ),
            ]
        )
        XCTAssertEqual(fixture.store.makeBuilderCount, 1)
    }

    func testDuplicatePreflightCallbacksCannotCreateDuplicateBuilders() throws {
        let empty: StoreLookupReply = .success([])
        let builder = FakeWorkoutBuilder()
        let fixture = try Fixture(
            builders: [builder],
            workoutLookupReplies: .sequential([empty, empty]),
            energyLookupReplies: .concurrent(Array(repeating: empty, count: 64))
        )

        let execution = executeCounting(
            fixture.operations,
            request: try makeRequest(withEnergy: true)
        )

        XCTAssertEqual(execution.results.count, 1)
        XCTAssertEqual(execution.results.first?.status, .written)
        XCTAssertEqual(fixture.store.lookupCount(for: .workout), 1)
        XCTAssertEqual(fixture.store.lookupCount(for: .activeEnergy), 1)
        XCTAssertEqual(fixture.store.makeBuilderCount, 1)
        XCTAssertEqual(builder.finishCount, 1)
    }

    func testDeniedAndNotDeterminedWorkoutAuthorizationNeverCreateABuilder() throws {
        for authorization in [WriteAuthorization.denied, .notDetermined] {
            let fixture = try Fixture(
                workoutAuthorizations: [authorization],
                energyAuthorizations: [.authorized]
            )

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .blockedWorkoutPermission,
                energyStatus: .notSubmitted,
                retryable: false,
                certainty: .notSubmitted,
                platformCode: "workoutPermissionMissing"
            )
            XCTAssertEqual(fixture.store.makeBuilderCount, 0)
        }
    }

    func testWorkoutPermissionBlockWithoutEnergyUsesNotExpected() throws {
        let fixture = try Fixture(workoutAuthorizations: [.denied])

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: false))

        assertResult(
            result,
            status: .blockedWorkoutPermission,
            energyStatus: .notExpected,
            retryable: false,
            certainty: .notSubmitted,
            platformCode: "workoutPermissionMissing"
        )
        XCTAssertEqual(fixture.store.makeBuilderCount, 0)
    }

    func testDeniedAndNotDeterminedEnergyAuthorizationWriteWorkoutOnly() throws {
        for authorization in [WriteAuthorization.denied, .notDetermined] {
            let builder = FakeWorkoutBuilder()
            let fixture = try Fixture(
                energyAuthorizations: [authorization],
                builders: [builder]
            )

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .writtenWithoutEnergy,
                workoutRecordID: builder.workoutID.uuidString,
                energyStatus: .omittedPermission,
                retryable: false,
                certainty: .submitted
            )
            XCTAssertEqual(builder.addEnergyCount, 0)
            XCTAssertEqual(builder.finishCount, 1)
        }
    }

    func testFullWriteUsesExactSequenceRealUUIDsAndOneMillisecondEnergyOffset() throws {
        let events = LockedEvents()
        let builder = FakeWorkoutBuilder(events: events)
        let fixture = try Fixture(builders: [builder], events: events)
        let request = try makeRequest(withEnergy: true)

        let result = execute(fixture.operations, request: request)

        assertResult(
            result,
            status: .written,
            workoutRecordID: builder.workoutID.uuidString,
            energyRecordID: builder.energyID.uuidString,
            energyStatus: .written,
            retryable: false,
            certainty: .submitted
        )
        XCTAssertEqual(builder.beginDates, [request.start])
        XCTAssertEqual(builder.energyWrites.count, 1)
        XCTAssertEqual(
            builder.energyWrites[0].start,
            request.start.addingTimeInterval(0.001)
        )
        XCTAssertEqual(builder.energyWrites[0].end, request.end)
        XCTAssertLessThan(builder.energyWrites[0].start, request.end)
        XCTAssertEqual(builder.endDates, [request.end])
        XCTAssertEqual(
            events.values,
            [
                "lookup.workout",
                "lookup.activeEnergy",
                "authorization.workout",
                "authorization.activeEnergy",
                "makeBuilder.energy",
                "builder.begin",
                "builder.metadata",
                "authorization.activeEnergy",
                "builder.energy",
                "builder.end",
                "builder.finish",
            ]
        )
    }

    func testBothRequiredMetadataPayloadsArePrecomputedBeforeBuilderCreation() throws {
        let events = LockedEvents()
        let builder = FakeWorkoutBuilder(events: events)
        let store = FakeWorkoutStore(
            workoutAuthorizations: [.authorized],
            energyAuthorizations: [.authorized, .authorized],
            builders: [builder],
            builderError: nil,
            events: events,
            workoutLookupReplies: .one(.success([])),
            energyLookupReplies: .one(.success([]))
        )
        let expectedWorkoutClientID = workoutClientID
        let operations = try HealthWorkoutOperations(
            store: store,
            metadataFactory: { clientRecordID, version, provenance in
                events.append(
                    clientRecordID == expectedWorkoutClientID
                        ? "metadata.workout"
                        : "metadata.energy"
                )
                return try HealthWorkoutMetadata.make(
                    clientRecordId: clientRecordID,
                    clientRecordVersion: version,
                    provenance: provenance
                )
            }
        )

        _ = execute(operations, request: try makeRequest(withEnergy: true))

        XCTAssertEqual(
            Array(events.values.prefix(8)),
            [
                "lookup.workout",
                "lookup.activeEnergy",
                "authorization.workout",
                "authorization.activeEnergy",
                "metadata.workout",
                "metadata.energy",
                "makeBuilder.energy",
                "builder.begin",
            ]
        )
    }

    func testMetadataConstructionFailureIsInvalidBeforeBuilderCreation() throws {
        let builder = FakeWorkoutBuilder()
        let store = FakeWorkoutStore(
            workoutAuthorizations: [.authorized],
            energyAuthorizations: [.authorized],
            builders: [builder],
            builderError: nil,
            events: LockedEvents(),
            workoutLookupReplies: .one(.success([])),
            energyLookupReplies: .one(.success([]))
        )
        let operations = try HealthWorkoutOperations(
            store: store,
            metadataFactory: { _, _, _ in throw TestMetadataError.failed }
        )

        let result = execute(operations, request: try makeRequest(withEnergy: true))

        assertResult(
            result,
            status: .invalidInput,
            energyStatus: .notSubmitted,
            retryable: false,
            certainty: .notSubmitted,
            platformCode: "invalidMetadata"
        )
        XCTAssertEqual(store.makeBuilderCount, 0)
        XCTAssertEqual(builder.beginCount, 0)
    }

    func testWorkoutAndEnergyReceiveDistinctCompleteStringMetadata() throws {
        let builder = FakeWorkoutBuilder()
        let fixture = try Fixture(builders: [builder])

        _ = execute(
            fixture.operations,
            request: try makeRequest(withEnergy: true, provenance: .manualEntry)
        )

        XCTAssertEqual(builder.workoutMetadata.count, 1)
        XCTAssertEqual(builder.energyWrites.count, 1)
        assertMetadata(
            builder.workoutMetadata[0],
            clientID: workoutClientID,
            wasUserEntered: true
        )
        assertMetadata(
            builder.energyWrites[0].metadata,
            clientID: energyClientID,
            wasUserEntered: true
        )
        XCTAssertNotEqual(
            builder.workoutMetadata[0][HKMetadataKeyExternalUUID] as? String,
            builder.energyWrites[0].metadata[HKMetadataKeyExternalUUID] as? String
        )
    }

    func testLiveAndRecoveredLiveWritesStayNotUserEnteredOnBothRecords() throws {
        for _ in ["live", "recovered-live"] {
            let builder = FakeWorkoutBuilder()
            let fixture = try Fixture(builders: [builder])

            _ = execute(
                fixture.operations,
                request: try makeRequest(withEnergy: true, provenance: .activelyRecorded)
            )

            assertMetadata(
                builder.workoutMetadata[0],
                clientID: workoutClientID,
                wasUserEntered: false
            )
            assertMetadata(
                builder.energyWrites[0].metadata,
                clientID: energyClientID,
                wasUserEntered: false
            )
        }
    }

    func testNoEnergyRequestWritesWorkoutWithoutEnergyCalls() throws {
        let builder = FakeWorkoutBuilder()
        let fixture = try Fixture(builders: [builder])

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: false))

        assertResult(
            result,
            status: .written,
            workoutRecordID: builder.workoutID.uuidString,
            energyStatus: .notExpected,
            retryable: false,
            certainty: .submitted
        )
        XCTAssertEqual(fixture.store.energyAuthorizationCount, 0)
        XCTAssertEqual(builder.addEnergyCount, 0)
    }

    func testOneMillisecondEnergyIntervalIsInvalidBeforeBuilderCreation() throws {
        let fixture = try Fixture()
        let request = try makeRequest(
            withEnergy: true,
            endEpochMilliseconds: startEpochMilliseconds + 1
        )

        let result = execute(fixture.operations, request: request)

        assertResult(
            result,
            status: .invalidInput,
            energyStatus: .notSubmitted,
            retryable: false,
            certainty: .notSubmitted,
            platformCode: "energyIntervalTooShort"
        )
        XCTAssertEqual(fixture.store.workoutAuthorizationCount, 0)
        XCTAssertEqual(fixture.store.lookupCalls.count, 0)
        XCTAssertEqual(fixture.store.makeBuilderCount, 0)
    }

    func testExactOneMillisecondIntervalsWinBeforeNativeDateValidation() throws {
        let dartMinimumEpochMilliseconds: Int64 = -8_640_000_000_000_000
        let dartMaximumEpochMilliseconds: Int64 = 8_640_000_000_000_000

        for (boundary, isLowerBoundary) in [
            (dartMinimumEpochMilliseconds, true),
            (dartMaximumEpochMilliseconds, false),
            (Int64.min, true),
            (Int64.max, false),
        ] {
            let fixture = try Fixture()
            let startMilliseconds = isLowerBoundary ? boundary : boundary - 1
            let endMilliseconds = startMilliseconds + 1
            let request = try makeRequest(
                withEnergy: true,
                startEpochMilliseconds: startMilliseconds,
                endEpochMilliseconds: endMilliseconds
            )

            let result = execute(fixture.operations, request: request)

            assertResult(
                result,
                status: .invalidInput,
                energyStatus: .notSubmitted,
                retryable: false,
                certainty: .notSubmitted,
                platformCode: "energyIntervalTooShort"
            )
            XCTAssertEqual(fixture.store.workoutAuthorizationCount, 0)
            XCTAssertEqual(fixture.store.lookupCalls.count, 0)
            XCTAssertEqual(fixture.store.makeBuilderCount, 0)
        }
    }

    func testRepresentableTwoMillisecondIntervalsReachStrictBuilderGeometry() throws {
        let dartMinimumEpochMilliseconds: Int64 = -8_640_000_000_000_000
        let dartMaximumEpochMilliseconds: Int64 = 8_640_000_000_000_000
        let year0000EpochMilliseconds: Int64 = -62_167_219_200_000
        let year9999EpochMilliseconds: Int64 = 253_402_300_799_999

        for (startMilliseconds, endMilliseconds) in [
            (startEpochMilliseconds, startEpochMilliseconds + 2),
            (year0000EpochMilliseconds, year0000EpochMilliseconds + 2),
            (year9999EpochMilliseconds - 2, year9999EpochMilliseconds),
            (dartMinimumEpochMilliseconds, dartMinimumEpochMilliseconds + 2),
            (dartMaximumEpochMilliseconds - 2, dartMaximumEpochMilliseconds),
        ] {
            let builder = FakeWorkoutBuilder()
            let fixture = try Fixture(builders: [builder])
            let request = try makeRequest(
                withEnergy: true,
                startEpochMilliseconds: startMilliseconds,
                endEpochMilliseconds: endMilliseconds
            )
            let nativeEnergyStart = request.start.addingTimeInterval(0.001)

            XCTAssertLessThan(request.start, nativeEnergyStart)
            XCTAssertLessThan(nativeEnergyStart, request.end)

            let result = execute(fixture.operations, request: request)

            XCTAssertEqual(result.status, .written)
            XCTAssertEqual(builder.beginDates, [request.start])
            XCTAssertEqual(builder.endDates, [request.end])
            XCTAssertEqual(builder.energyWrites.count, 1)
            XCTAssertLessThan(builder.beginDates[0], builder.energyWrites[0].start)
            XCTAssertLessThan(builder.energyWrites[0].start, builder.energyWrites[0].end)
        }
    }

    func testCollapsedTwoMillisecondEnergyIntervalsAreInvalidBeforeAuthorization() throws {
        for (startMilliseconds, endMilliseconds) in [
            (Int64.min, Int64.min + 2),
            (Int64.max - 2, Int64.max),
        ] {
            let forbiddenBuilder = FakeWorkoutBuilder()
            let fixture = try Fixture(builders: [forbiddenBuilder])
            let request = try makeRequest(
                withEnergy: true,
                startEpochMilliseconds: startMilliseconds,
                endEpochMilliseconds: endMilliseconds
            )

            XCTAssertEqual(request.start, request.end)

            let result = execute(fixture.operations, request: request)

            assertResult(
                result,
                status: .invalidInput,
                energyStatus: .notSubmitted,
                retryable: false,
                certainty: .notSubmitted,
                platformCode: "healthKitDateIntervalUnrepresentable"
            )
            XCTAssertEqual(fixture.store.workoutAuthorizationCount, 0)
            XCTAssertEqual(fixture.store.lookupCalls.count, 0)
            XCTAssertEqual(fixture.store.makeBuilderCount, 0)
            XCTAssertEqual(forbiddenBuilder.beginCount, 0)
        }
    }

    func testCollapsedTwoMillisecondWorkoutOnlyIntervalsAreInvalidBeforeAuthorization() throws {
        for (startMilliseconds, endMilliseconds) in [
            (Int64.min, Int64.min + 2),
            (Int64.max - 2, Int64.max),
        ] {
            let forbiddenBuilder = FakeWorkoutBuilder()
            let fixture = try Fixture(builders: [forbiddenBuilder])
            let request = try makeRequest(
                withEnergy: false,
                startEpochMilliseconds: startMilliseconds,
                endEpochMilliseconds: endMilliseconds
            )

            XCTAssertEqual(request.start, request.end)

            let result = execute(fixture.operations, request: request)

            assertResult(
                result,
                status: .invalidInput,
                energyStatus: .notExpected,
                retryable: false,
                certainty: .notSubmitted,
                platformCode: "healthKitDateIntervalUnrepresentable"
            )
            XCTAssertEqual(fixture.store.workoutAuthorizationCount, 0)
            XCTAssertEqual(fixture.store.lookupCalls.count, 0)
            XCTAssertEqual(fixture.store.makeBuilderCount, 0)
            XCTAssertEqual(forbiddenBuilder.beginCount, 0)
        }
    }

    func testFullInt64EnergyRangeIsExactButNativeEnergyStartIsUnrepresentable() throws {
        let forbiddenBuilder = FakeWorkoutBuilder()
        let fixture = try Fixture(builders: [forbiddenBuilder])
        let request = try makeRequest(
            withEnergy: true,
            startEpochMilliseconds: Int64.min,
            endEpochMilliseconds: Int64.max
        )

        XCTAssertLessThan(request.start, request.end)
        XCTAssertEqual(request.start.addingTimeInterval(0.001), request.start)

        let result = execute(fixture.operations, request: request)

        assertResult(
            result,
            status: .invalidInput,
            energyStatus: .notSubmitted,
            retryable: false,
            certainty: .notSubmitted,
            platformCode: "healthKitDateIntervalUnrepresentable"
        )
        XCTAssertEqual(fixture.store.workoutAuthorizationCount, 0)
        XCTAssertEqual(fixture.store.lookupCalls.count, 0)
        XCTAssertEqual(fixture.store.makeBuilderCount, 0)
        XCTAssertEqual(forbiddenBuilder.beginCount, 0)
    }

    func testFullInt64WorkoutOnlyRangeDoesNotRequireAnEnergyMidpoint() throws {
        let builder = FakeWorkoutBuilder()
        let fixture = try Fixture(builders: [builder])
        let request = try makeRequest(
            withEnergy: false,
            startEpochMilliseconds: Int64.min,
            endEpochMilliseconds: Int64.max
        )

        let result = execute(fixture.operations, request: request)

        XCTAssertEqual(result.status, .written)
        XCTAssertEqual(fixture.store.makeBuilderCount, 1)
        XCTAssertLessThan(builder.beginDates[0], builder.endDates[0])
        XCTAssertEqual(builder.finishCount, 1)
    }

    func testOneMillisecondConstraintDoesNotRejectWorkoutOnlyRequest() throws {
        let builder = FakeWorkoutBuilder()
        let fixture = try Fixture(builders: [builder])
        let request = try makeRequest(
            withEnergy: false,
            endEpochMilliseconds: startEpochMilliseconds + 1
        )

        let result = execute(fixture.operations, request: request)

        XCTAssertEqual(result.status, .written)
        XCTAssertEqual(builder.finishCount, 1)
    }

    func testBuilderFactoryFailureIsUnavailableAndNotSubmitted() throws {
        let fixture = try Fixture(builderError: .activityUnavailable)

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

        assertResult(
            result,
            status: .unavailable,
            energyStatus: .notSubmitted,
            retryable: true,
            certainty: .notSubmitted,
            platformCode: "activityUnavailable"
        )
    }

    func testEveryBeginBoolErrorFailureShapeIsProvenNotSubmitted() throws {
        for reply in failingBoolReplies {
            let builder = FakeWorkoutBuilder()
            builder.beginReplies = .one(reply)
            let fixture = try Fixture(builders: [builder])

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .transientFailure,
                energyStatus: .notSubmitted,
                retryable: true,
                certainty: .notSubmitted,
                platformCode: "beginCollectionFailed"
            )
            XCTAssertEqual(builder.discardCount, 1)
            XCTAssertEqual(builder.addMetadataCount, 0)
        }
    }

    func testEveryRequiredMetadataBoolErrorFailureShapeIsProvenNotSubmitted() throws {
        for reply in failingBoolReplies {
            let builder = FakeWorkoutBuilder()
            builder.metadataReplies = .one(reply)
            let fixture = try Fixture(builders: [builder])

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .transientFailure,
                energyStatus: .notSubmitted,
                retryable: true,
                certainty: .notSubmitted,
                platformCode: "workoutMetadataFailed"
            )
            XCTAssertEqual(builder.discardCount, 1)
            XCTAssertEqual(builder.addEnergyCount, 0)
        }
    }

    func testProvenEnergyAddFailuresAreNotSubmittedAndNeverFallback() throws {
        for reply in [
            BoolReply(success: false, error: .operationFailed),
            BoolReply(success: false, error: nil),
        ] {
            let first = FakeWorkoutBuilder()
            first.energyReplies = .one(reply)
            let unusedFallback = FakeWorkoutBuilder()
            let fixture = try Fixture(builders: [first, unusedFallback])

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .transientFailure,
                energyStatus: .notSubmitted,
                retryable: true,
                certainty: .notSubmitted,
                platformCode: "energySampleFailed"
            )
            XCTAssertEqual(fixture.store.makeBuilderCount, 1)
            XCTAssertEqual(first.discardCount, 1)
            XCTAssertEqual(unusedFallback.beginCount, 0)
        }
    }

    func testSuccessfulEnergyBoolWithErrorIsConservativelyVerificationRequired() throws {
        let builder = FakeWorkoutBuilder()
        builder.energyReplies = .one(
            BoolReply(success: true, error: .operationFailed)
        )
        let fixture = try Fixture(builders: [builder])

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

        assertResult(
            result,
            status: .verificationRequired,
            energyStatus: .verificationRequired,
            retryable: false,
            certainty: .mayHaveSubmitted,
            platformCode: "energySampleAmbiguous"
        )
        XCTAssertEqual(builder.discardCount, 1)
        XCTAssertEqual(builder.endCount, 0)
    }

    func testEnergyAuthorizationErrorBeforeAcceptanceFallsBackExactlyOnce() throws {
        for error in [
            HealthWorkoutBuilderError.authorizationDenied(.activeEnergy),
            .authorizationNotDetermined(.activeEnergy),
        ] {
            let first = FakeWorkoutBuilder()
            first.energyReplies = .one(BoolReply(success: false, error: error))
            let fallback = FakeWorkoutBuilder()
            let fixture = try Fixture(
                workoutAuthorizations: [.authorized, .authorized],
                builders: [first, fallback]
            )

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .writtenWithoutEnergy,
                workoutRecordID: fallback.workoutID.uuidString,
                energyStatus: .omittedPermission,
                retryable: false,
                certainty: .submitted
            )
            XCTAssertEqual(first.discardCount, 1)
            XCTAssertEqual(first.finishCount, 0)
            XCTAssertEqual(fallback.addEnergyCount, 0)
            XCTAssertEqual(fallback.finishCount, 1)
            XCTAssertEqual(fixture.store.makeBuilderCount, 2)
        }
    }

    func testFreshEnergyAuthorizationRaceFallsBackBeforeCallingAdd() throws {
        let first = FakeWorkoutBuilder()
        let fallback = FakeWorkoutBuilder()
        let fixture = try Fixture(
            workoutAuthorizations: [.authorized, .authorized],
            energyAuthorizations: [.authorized, .denied],
            builders: [first, fallback]
        )

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

        XCTAssertEqual(result.status, .writtenWithoutEnergy)
        XCTAssertEqual(result.workoutRecordId, fallback.workoutID.uuidString)
        XCTAssertEqual(first.addEnergyCount, 0)
        XCTAssertEqual(first.discardCount, 1)
        XCTAssertEqual(fixture.store.makeBuilderCount, 2)
    }

    func testFallbackRequiresFreshWorkoutAuthorization() throws {
        for authorization in [WriteAuthorization.denied, .notDetermined] {
            let first = FakeWorkoutBuilder()
            first.energyReplies = .one(
                BoolReply(
                    success: false,
                    error: .authorizationDenied(.activeEnergy)
                )
            )
            let unusedFallback = FakeWorkoutBuilder()
            let fixture = try Fixture(
                workoutAuthorizations: [.authorized, authorization],
                builders: [first, unusedFallback]
            )

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .blockedWorkoutPermission,
                energyStatus: .notSubmitted,
                retryable: false,
                certainty: .notSubmitted,
                platformCode: "workoutPermissionMissing"
            )
            XCTAssertEqual(fixture.store.makeBuilderCount, 1)
            XCTAssertEqual(unusedFallback.beginCount, 0)
        }
    }

    func testFallbackUsesANewBuilderWithoutEnergyReuseOrBackfill() throws {
        let first = FakeWorkoutBuilder()
        first.energyReplies = .one(
            BoolReply(
                success: false,
                error: .authorizationDenied(.activeEnergy)
            )
        )
        let fallback = FakeWorkoutBuilder()
        let third = FakeWorkoutBuilder()
        let fixture = try Fixture(
            workoutAuthorizations: [.authorized, .authorized],
            builders: [first, fallback, third]
        )

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

        XCTAssertEqual(result.workoutRecordId, fallback.workoutID.uuidString)
        XCTAssertNotEqual(result.workoutRecordId, first.workoutID.uuidString)
        XCTAssertNil(result.energyRecordId)
        XCTAssertEqual(fixture.store.makeBuilderCount, 2)
        XCTAssertEqual(first.addEnergyCount, 1)
        XCTAssertEqual(fallback.addEnergyCount, 0)
        XCTAssertEqual(third.beginCount, 0)
    }

    func testFallbackBuilderFailureNeverAttemptsASecondFallback() throws {
        let first = FakeWorkoutBuilder()
        first.energyReplies = .one(
            BoolReply(
                success: false,
                error: .authorizationDenied(.activeEnergy)
            )
        )
        let fallback = FakeWorkoutBuilder()
        fallback.beginReplies = .one(
            BoolReply(
                success: false,
                error: .authorizationDenied(.workout)
            )
        )
        let forbiddenThird = FakeWorkoutBuilder()
        let fixture = try Fixture(
            workoutAuthorizations: [.authorized, .authorized],
            builders: [first, fallback, forbiddenThird]
        )

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

        XCTAssertEqual(result.status, .blockedWorkoutPermission)
        XCTAssertEqual(fixture.store.makeBuilderCount, 2)
        XCTAssertEqual(forbiddenThird.beginCount, 0)
    }

    func testWorkoutAuthorizationErrorsAtBeginAndMetadataArePermissionBlocks() throws {
        for stage in ["begin", "metadata"] {
            let builder = FakeWorkoutBuilder()
            let reply = BoolReply(
                success: false,
                error: HealthWorkoutBuilderError.authorizationDenied(.workout)
            )
            if stage == "begin" {
                builder.beginReplies = .one(reply)
            } else {
                builder.metadataReplies = .one(reply)
            }
            let fixture = try Fixture(builders: [builder])

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .blockedWorkoutPermission,
                energyStatus: .notSubmitted,
                retryable: false,
                certainty: .notSubmitted,
                platformCode: "workoutPermissionMissing"
            )
            XCTAssertEqual(builder.discardCount, 1)
        }
    }

    func testEveryEndFailureAfterEnergyAcceptanceRequiresVerification() throws {
        for reply in failingBoolReplies {
            let builder = FakeWorkoutBuilder()
            builder.endReplies = .one(reply)
            let fixture = try Fixture(builders: [builder])

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .verificationRequired,
                energyStatus: .verificationRequired,
                retryable: false,
                certainty: .mayHaveSubmitted,
                platformCode: "endCollectionFailed"
            )
            XCTAssertEqual(builder.addEnergyCount, 1)
            XCTAssertEqual(builder.discardCount, 1)
            XCTAssertEqual(builder.finishCount, 0)
        }
    }

    func testWorkoutAuthorizationLossAtEndAfterEnergyAcceptanceStillRequiresVerification() throws {
        let builder = FakeWorkoutBuilder()
        builder.endReplies = .one(
            BoolReply(
                success: false,
                error: .authorizationDenied(.workout)
            )
        )
        let fixture = try Fixture(builders: [builder])

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

        assertResult(
            result,
            status: .verificationRequired,
            energyStatus: .verificationRequired,
            retryable: false,
            certainty: .mayHaveSubmitted,
            platformCode: "endCollectionFailed"
        )
    }

    func testWorkoutOnlyEndFailuresRemainProvenNotSubmitted() throws {
        for reply in failingBoolReplies {
            let builder = FakeWorkoutBuilder()
            builder.endReplies = .one(reply)
            let fixture = try Fixture(builders: [builder])

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: false))

            assertResult(
                result,
                status: .transientFailure,
                energyStatus: .notExpected,
                retryable: true,
                certainty: .notSubmitted,
                platformCode: "endCollectionFailed"
            )
            XCTAssertEqual(builder.discardCount, 1)
        }
    }

    func testWorkoutAuthorizationLossAtWorkoutOnlyEndIsStillProvenBlocked() throws {
        let builder = FakeWorkoutBuilder()
        builder.endReplies = .one(
            BoolReply(
                success: false,
                error: .authorizationNotDetermined(.workout)
            )
        )
        let fixture = try Fixture(builders: [builder])

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: false))

        assertResult(
            result,
            status: .blockedWorkoutPermission,
            energyStatus: .notExpected,
            retryable: false,
            certainty: .notSubmitted,
            platformCode: "workoutPermissionMissing"
        )
    }

    func testNilFinishWithNilOrErrorAlwaysRequiresVerification() throws {
        for reply in [
            FinishReply(value: nil, error: nil),
            FinishReply(value: nil, error: .operationFailed),
        ] {
            let builder = FakeWorkoutBuilder()
            builder.finishReplies = .one(reply)
            let fixture = try Fixture(builders: [builder])

            let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

            assertResult(
                result,
                status: .verificationRequired,
                energyStatus: .verificationRequired,
                retryable: false,
                certainty: .mayHaveSubmitted,
                platformCode: reply.error == nil
                    ? "finishWorkoutUnavailable"
                    : "finishWorkoutFailed"
            )
            XCTAssertEqual(builder.finishCount, 1)
            XCTAssertEqual(builder.discardCount, 0)
        }
    }

    func testReturnedWorkoutWinsOverAContradictoryFinishError() throws {
        let builder = FakeWorkoutBuilder()
        builder.finishReplies = .one(
            FinishReply(
                value: builder.storedWorkoutAndEnergy,
                error: .operationFailed
            )
        )
        let fixture = try Fixture(builders: [builder])

        let result = execute(fixture.operations, request: try makeRequest(withEnergy: true))

        XCTAssertEqual(result.status, .written)
        XCTAssertEqual(result.submissionCertainty, .submitted)
        XCTAssertEqual(result.workoutRecordId, builder.workoutID.uuidString)
        XCTAssertEqual(result.energyRecordId, builder.energyID.uuidString)
    }

    func testMissingOrUnexpectedFinishedEnergyIdentityRequiresVerification() throws {
        let noEnergy = StoredWorkoutAndEnergy(
            workoutRecordID: UUID(),
            energyRecordID: nil
        )
        let unexpectedEnergy = StoredWorkoutAndEnergy(
            workoutRecordID: UUID(),
            energyRecordID: UUID()
        )

        for (requestHasEnergy, stored) in [
            (true, noEnergy),
            (false, unexpectedEnergy),
        ] {
            let builder = FakeWorkoutBuilder()
            builder.finishReplies = .one(FinishReply(value: stored, error: nil))
            let fixture = try Fixture(builders: [builder])

            let result = execute(
                fixture.operations,
                request: try makeRequest(withEnergy: requestHasEnergy)
            )

            assertResult(
                result,
                status: .verificationRequired,
                energyStatus: requestHasEnergy ? .verificationRequired : .notExpected,
                retryable: false,
                certainty: .mayHaveSubmitted,
                platformCode: "finishResultMismatch"
            )
        }
    }

    func testSequentialDuplicateCallbacksAdvanceEveryStageAndCompleteOnlyOnce() throws {
        let builder = FakeWorkoutBuilder()
        builder.beginReplies = .sequential([.ok, .ok])
        builder.metadataReplies = .sequential([.ok, .ok])
        builder.energyReplies = .sequential([.ok, .ok])
        builder.endReplies = .sequential([.ok, .ok])
        builder.finishReplies = .sequential([
            .success(builder.storedWorkoutAndEnergy),
            .success(builder.storedWorkoutAndEnergy),
        ])
        let fixture = try Fixture(builders: [builder])

        let execution = executeCounting(
            fixture.operations,
            request: try makeRequest(withEnergy: true)
        )

        XCTAssertEqual(execution.results.count, 1)
        XCTAssertEqual(execution.results[0].status, .written)
        XCTAssertEqual(builder.beginCount, 1)
        XCTAssertEqual(builder.addMetadataCount, 1)
        XCTAssertEqual(builder.addEnergyCount, 1)
        XCTAssertEqual(builder.endCount, 1)
        XCTAssertEqual(builder.finishCount, 1)
    }

    func testConcurrentDuplicateCallbacksCompleteExactlyOnceWithoutDuplicateSideEffects() throws {
        for _ in 0..<64 {
            let builder = FakeWorkoutBuilder()
            builder.beginReplies = .concurrent([.ok, .ok])
            builder.metadataReplies = .concurrent([.ok, .ok])
            builder.energyReplies = .concurrent([.ok, .ok])
            builder.endReplies = .concurrent([.ok, .ok])
            builder.finishReplies = .concurrent([
                .success(builder.storedWorkoutAndEnergy),
                .success(builder.storedWorkoutAndEnergy),
            ])
            let fixture = try Fixture(builders: [builder])

            let execution = executeCounting(
                fixture.operations,
                request: try makeRequest(withEnergy: true)
            )

            XCTAssertEqual(execution.results.count, 1)
            XCTAssertEqual(execution.results[0].status, .written)
            XCTAssertEqual(builder.beginCount, 1)
            XCTAssertEqual(builder.addMetadataCount, 1)
            XCTAssertEqual(builder.addEnergyCount, 1)
            XCTAssertEqual(builder.endCount, 1)
            XCTAssertEqual(builder.finishCount, 1)
        }
    }

    func testConcurrentDuplicateEnergySuccessCallbacksNeverStartFallback() throws {
        for _ in 0..<64 {
            let first = FakeWorkoutBuilder()
            first.energyReplies = .concurrent([
                .ok,
                .ok,
            ])
            let forbiddenFallback = FakeWorkoutBuilder()
            let fixture = try Fixture(
                workoutAuthorizations: [.authorized, .authorized],
                builders: [first, forbiddenFallback]
            )

            let execution = executeCounting(
                fixture.operations,
                request: try makeRequest(withEnergy: true)
            )

            XCTAssertEqual(execution.results.count, 1)
            XCTAssertEqual(execution.results[0].status, .written)
            XCTAssertEqual(fixture.store.makeBuilderCount, 1)
            XCTAssertEqual(first.finishCount, 1)
            XCTAssertEqual(forbiddenFallback.beginCount, 0)
        }
    }

    func testEveryEmittedResultCanBeReconstructedThroughTheThrowingValidator() throws {
        let scenarios: [(Fixture, WorkoutWriteRequest)] = [
            (try Fixture(), try makeRequest(withEnergy: true)),
            (
                try Fixture(workoutAuthorizations: [.denied]),
                try makeRequest(withEnergy: true)
            ),
            (
                try Fixture(energyAuthorizations: [.denied]),
                try makeRequest(withEnergy: true)
            ),
        ]

        for (fixture, request) in scenarios {
            let result = execute(fixture.operations, request: request)
            let reconstructed = try WorkoutWriteResult(
                status: result.status,
                workoutRecordId: result.workoutRecordId,
                energyRecordId: result.energyRecordId,
                energyStatus: result.energyStatus,
                retryable: result.retryable,
                submissionCertainty: result.submissionCertainty,
                platformCode: result.platformCode
            )
            XCTAssertEqual(reconstructed, result)
        }
    }

    private var failingBoolReplies: [BoolReply] {
        [
            BoolReply(success: false, error: .operationFailed),
            BoolReply(success: false, error: nil),
            BoolReply(success: true, error: .operationFailed),
        ]
    }

    private func lookupIdentity(
        id: UUID,
        clientID: String
    ) -> StoredRecordIdentity {
        StoredRecordIdentity(
            recordID: id,
            syncIdentifier: clientID,
            externalIdentifier: clientID,
            isFromCurrentSource: true
        )
    }

    private func makeRequest(
        withEnergy: Bool,
        startEpochMilliseconds: Int64? = nil,
        endEpochMilliseconds: Int64? = nil,
        provenance: HealthRecordingProvenance = .activelyRecorded,
        device: HealthRecordingDevice = .phone
    ) throws -> WorkoutWriteRequest {
        try WorkoutWriteRequest(
            workoutClientRecordId: workoutClientID,
            energyClientRecordId: withEnergy ? energyClientID : nil,
            clientRecordVersion: 0,
            activityType: "TRADITIONAL_STRENGTH_TRAINING",
            startEpochMilliseconds: startEpochMilliseconds
                ?? self.startEpochMilliseconds,
            endEpochMilliseconds: endEpochMilliseconds
                ?? self.endEpochMilliseconds,
            startZoneOffsetSeconds: -18_000,
            endZoneOffsetSeconds: -14_400,
            activeEnergyKcal: withEnergy ? 314.25 : nil,
            title: "Strength Training",
            recordingProvenance: provenance,
            recordingDevice: device
        )
    }

    private func execute(
        _ operations: HealthWorkoutOperations,
        request: WorkoutWriteRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> WorkoutWriteResult {
        let execution = executeCounting(
            operations,
            request: request,
            file: file,
            line: line
        )
        guard let result = execution.results.first else {
            XCTFail("write did not complete", file: file, line: line)
            fatalError("write did not complete")
        }
        return result
    }

    private func executeCounting(
        _ operations: HealthWorkoutOperations,
        request: WorkoutWriteRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ResultCapture {
        let capture = ResultCapture()
        let completion = expectation(description: "write completion")
        completion.assertForOverFulfill = true
        operations.write(request) { result in
            let count = capture.append(result)
            if count == 1 {
                completion.fulfill()
            }
        }
        wait(for: [completion], timeout: 1)
        XCTAssertEqual(capture.results.count, 1, file: file, line: line)
        return capture
    }

    private func assertResult(
        _ result: WorkoutWriteResult,
        status: WorkoutWriteStatus,
        workoutRecordID: String? = nil,
        energyRecordID: String? = nil,
        energyStatus: EnergyWriteStatus,
        retryable: Bool,
        certainty: SubmissionCertainty,
        platformCode: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.status, status, file: file, line: line)
        XCTAssertEqual(result.workoutRecordId, workoutRecordID, file: file, line: line)
        XCTAssertEqual(result.energyRecordId, energyRecordID, file: file, line: line)
        XCTAssertEqual(result.energyStatus, energyStatus, file: file, line: line)
        XCTAssertEqual(result.retryable, retryable, file: file, line: line)
        XCTAssertEqual(result.submissionCertainty, certainty, file: file, line: line)
        XCTAssertEqual(result.platformCode, platformCode, file: file, line: line)
        XCTAssertNoThrow(
            try WorkoutWriteResult(
                status: result.status,
                workoutRecordId: result.workoutRecordId,
                energyRecordId: result.energyRecordId,
                energyStatus: result.energyStatus,
                retryable: result.retryable,
                submissionCertainty: result.submissionCertainty,
                platformCode: result.platformCode
            ),
            file: file,
            line: line
        )
    }

    private func assertMetadata(
        _ metadata: [String: Any],
        clientID: String,
        wasUserEntered: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            metadata[HKMetadataKeyExternalUUID] as? String,
            clientID,
            file: file,
            line: line
        )
        XCTAssertNil(
            metadata[HKMetadataKeyExternalUUID] as? UUID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            metadata[HKMetadataKeySyncIdentifier] as? String,
            clientID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            metadata[HKMetadataKeySyncVersion] as? Int,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            metadata[HKMetadataKeyWasUserEntered] as? Bool,
            wasUserEntered,
            file: file,
            line: line
        )
    }
}

private typealias StoreLookupReply =
    Result<[StoredRecordIdentity], HealthWorkoutLookupError>

private struct WriteLookupCall: Equatable, Sendable {
    let component: WorkoutComponent
    let clientRecordID: String
    let start: Date
    let end: Date
}

private final class Fixture {
    let store: FakeWorkoutStore
    let operations: HealthWorkoutOperations

    init(
        workoutAuthorizations: [WriteAuthorization] = [.authorized],
        energyAuthorizations: [WriteAuthorization] = [.authorized, .authorized],
        builders: [FakeWorkoutBuilder] = [FakeWorkoutBuilder()],
        builderError: HealthWorkoutStoreError? = nil,
        events: LockedEvents = LockedEvents(),
        workoutLookupReplies: ReplyMode<StoreLookupReply> = .one(.success([])),
        energyLookupReplies: ReplyMode<StoreLookupReply> = .one(.success([]))
    ) throws {
        store = FakeWorkoutStore(
            workoutAuthorizations: workoutAuthorizations,
            energyAuthorizations: energyAuthorizations,
            builders: builders,
            builderError: builderError,
            events: events,
            workoutLookupReplies: workoutLookupReplies,
            energyLookupReplies: energyLookupReplies
        )
        operations = try HealthWorkoutOperations(store: store)
    }
}

private final class FakeWorkoutStore: HealthWorkoutStore, @unchecked Sendable {
    private let lock = NSLock()
    private let workoutAuthorizations: [WriteAuthorization]
    private let energyAuthorizations: [WriteAuthorization]
    private let builders: [FakeWorkoutBuilder]
    private let builderError: HealthWorkoutStoreError?
    private let events: LockedEvents
    private let workoutLookupReplies: ReplyMode<StoreLookupReply>
    private let energyLookupReplies: ReplyMode<StoreLookupReply>
    private var workoutAuthorizationIndex = 0
    private var energyAuthorizationIndex = 0
    private var builderIndex = 0
    private var capturedLookupCalls: [WriteLookupCall] = []

    let isHealthDataAvailable = true

    init(
        workoutAuthorizations: [WriteAuthorization],
        energyAuthorizations: [WriteAuthorization],
        builders: [FakeWorkoutBuilder],
        builderError: HealthWorkoutStoreError?,
        events: LockedEvents,
        workoutLookupReplies: ReplyMode<StoreLookupReply> = .one(.success([])),
        energyLookupReplies: ReplyMode<StoreLookupReply> = .one(.success([]))
    ) {
        self.workoutAuthorizations = workoutAuthorizations
        self.energyAuthorizations = energyAuthorizations
        self.builders = builders
        self.builderError = builderError
        self.events = events
        self.workoutLookupReplies = workoutLookupReplies
        self.energyLookupReplies = energyLookupReplies
    }

    var workoutAuthorizationCount: Int {
        lock.withLock { workoutAuthorizationIndex }
    }

    var energyAuthorizationCount: Int {
        lock.withLock { energyAuthorizationIndex }
    }

    var makeBuilderCount: Int {
        lock.withLock { builderIndex }
    }

    var lookupCalls: [WriteLookupCall] {
        lock.withLock { capturedLookupCalls }
    }

    func lookupCount(for component: WorkoutComponent) -> Int {
        lock.withLock {
            capturedLookupCalls.count { $0.component == component }
        }
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
        lock.withLock {
            capturedLookupCalls.append(
                WriteLookupCall(
                    component: component,
                    clientRecordID: clientRecordId,
                    start: start,
                    end: end
                )
            )
        }
        events.append("lookup.\(component.rawValue)")
        deliver(
            component == .workout
                ? workoutLookupReplies
                : energyLookupReplies,
            callback: completion
        )
    }

    func writeAuthorization(for component: WorkoutComponent) -> WriteAuthorization {
        let authorization = lock.withLock { () -> WriteAuthorization in
            switch component {
            case .workout:
                defer { workoutAuthorizationIndex += 1 }
                return workoutAuthorizations[
                    min(workoutAuthorizationIndex, workoutAuthorizations.count - 1)
                ]
            case .activeEnergy:
                defer { energyAuthorizationIndex += 1 }
                return energyAuthorizations[
                    min(energyAuthorizationIndex, energyAuthorizations.count - 1)
                ]
            }
        }
        events.append("authorization.\(component.rawValue)")
        return authorization
    }

    func makeBuilder(for request: WorkoutWriteRequest) throws -> HealthWorkoutBuilder {
        let builder = try lock.withLock { () throws -> FakeWorkoutBuilder in
            if let builderError {
                throw builderError
            }
            guard builderIndex < builders.count else {
                throw HealthWorkoutStoreError.builderUnavailable
            }
            defer { builderIndex += 1 }
            return builders[builderIndex]
        }
        events.append(request.activeEnergyKcal == nil ? "makeBuilder.workout" : "makeBuilder.energy")
        return builder
    }
}

private final class FakeWorkoutBuilder: HealthWorkoutBuilder, @unchecked Sendable {
    struct EnergyWrite {
        let kilocalories: Double
        let start: Date
        let end: Date
        let metadata: [String: Any]
    }

    let workoutID: UUID
    let energyID: UUID
    let events: LockedEvents
    var beginReplies: ReplyMode<BoolReply> = .one(.ok)
    var metadataReplies: ReplyMode<BoolReply> = .one(.ok)
    var energyReplies: ReplyMode<BoolReply> = .one(.ok)
    var endReplies: ReplyMode<BoolReply> = .one(.ok)
    var finishReplies: ReplyMode<FinishReply>?

    private let lock = NSLock()
    private var _beginDates: [Date] = []
    private var _workoutMetadata: [[String: Any]] = []
    private var _energyWrites: [EnergyWrite] = []
    private var _endDates: [Date] = []
    private var _finishCount = 0
    private var _discardCount = 0

    init(
        workoutID: UUID = UUID(),
        energyID: UUID = UUID(),
        events: LockedEvents = LockedEvents()
    ) {
        self.workoutID = workoutID
        self.energyID = energyID
        self.events = events
        finishReplies = nil
    }

    var storedWorkoutAndEnergy: StoredWorkoutAndEnergy {
        StoredWorkoutAndEnergy(
            workoutRecordID: workoutID,
            energyRecordID: energyID
        )
    }

    var beginDates: [Date] { lock.withLock { _beginDates } }
    var workoutMetadata: [[String: Any]] { lock.withLock { _workoutMetadata } }
    var energyWrites: [EnergyWrite] { lock.withLock { _energyWrites } }
    var endDates: [Date] { lock.withLock { _endDates } }
    var beginCount: Int { beginDates.count }
    var addMetadataCount: Int { workoutMetadata.count }
    var addEnergyCount: Int { energyWrites.count }
    var endCount: Int { endDates.count }
    var finishCount: Int { lock.withLock { _finishCount } }
    var discardCount: Int { lock.withLock { _discardCount } }

    func begin(
        at start: Date,
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    ) {
        lock.withLock { _beginDates.append(start) }
        events.append("builder.begin")
        deliver(beginReplies) { completion($0.success, $0.error) }
    }

    func addEnergy(
        kilocalories: Double,
        start: Date,
        end: Date,
        metadata: [String: Any],
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    ) {
        let hasValidGeometry = lock.withLock { () -> Bool in
            _energyWrites.append(
                EnergyWrite(
                    kilocalories: kilocalories,
                    start: start,
                    end: end,
                    metadata: metadata
                )
            )
            guard let workoutStart = _beginDates.last else { return false }
            return workoutStart < start && start < end
        }
        events.append("builder.energy")
        guard hasValidGeometry else {
            completion(false, .operationFailed)
            return
        }
        deliver(energyReplies) { completion($0.success, $0.error) }
    }

    func addWorkoutMetadata(
        _ metadata: [String: Any],
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    ) {
        lock.withLock { _workoutMetadata.append(metadata) }
        events.append("builder.metadata")
        deliver(metadataReplies) { completion($0.success, $0.error) }
    }

    func end(
        at end: Date,
        completion: @escaping @Sendable (Bool, HealthWorkoutBuilderError?) -> Void
    ) {
        let hasValidGeometry = lock.withLock { () -> Bool in
            _endDates.append(end)
            guard let workoutStart = _beginDates.last else { return false }
            return workoutStart < end
        }
        events.append("builder.end")
        guard hasValidGeometry else {
            completion(false, .operationFailed)
            return
        }
        deliver(endReplies) { completion($0.success, $0.error) }
    }

    func finish(
        completion: @escaping @Sendable (StoredWorkoutAndEnergy?, HealthWorkoutBuilderError?) -> Void
    ) {
        lock.withLock { _finishCount += 1 }
        events.append("builder.finish")
        let replies =
            finishReplies
            ?? .one(
                .success(
                    StoredWorkoutAndEnergy(
                        workoutRecordID: workoutID,
                        energyRecordID: addEnergyCount > 0 ? energyID : nil
                    )
                )
            )
        deliver(replies) { completion($0.value, $0.error) }
    }

    func discard() {
        lock.withLock { _discardCount += 1 }
        events.append("builder.discard")
    }
}

private struct BoolReply: Sendable {
    let success: Bool
    let error: HealthWorkoutBuilderError?

    static let ok = BoolReply(success: true, error: nil)
}

private struct FinishReply: Sendable {
    let value: StoredWorkoutAndEnergy?
    let error: HealthWorkoutBuilderError?

    static func success(_ value: StoredWorkoutAndEnergy) -> FinishReply {
        FinishReply(value: value, error: nil)
    }
}

private enum ReplyMode<Reply: Sendable>: Sendable {
    case one(Reply)
    case sequential([Reply])
    case concurrent([Reply])
}

private func deliver<Reply: Sendable>(
    _ mode: ReplyMode<Reply>,
    callback: @escaping @Sendable (Reply) -> Void
) {
    switch mode {
    case .one(let reply):
        callback(reply)
    case .sequential(let replies):
        replies.forEach(callback)
    case .concurrent(let replies):
        DispatchQueue.concurrentPerform(iterations: replies.count) { index in
            callback(replies[index])
        }
    }
}

private enum TestMetadataError: Error {
    case failed
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private final class ResultCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [WorkoutWriteResult] = []

    var results: [WorkoutWriteResult] { lock.withLock { storage } }

    @discardableResult
    func append(_ result: WorkoutWriteResult) -> Int {
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
