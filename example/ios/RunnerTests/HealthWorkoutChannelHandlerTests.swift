import Flutter
import Foundation
import HealthKit
import XCTest

@testable import health_bridge

#if canImport(HealthBridgeWorkoutCore)
    import HealthBridgeWorkoutCore
#endif

final class HealthWorkoutChannelHandlerTests: XCTestCase {
    func testGenericScalarClientIdentityUsesHealthKitSyncMetadata() throws {
        let clientRecordId = "018f8d7e-3333-7333-8333-333333333333"

        let metadata = try HealthDataClientRecordMetadata.make(
            isManualEntry: true,
            clientRecordId: clientRecordId,
            clientRecordVersion: NSNumber(value: 7.0)
        )

        XCTAssertEqual(metadata[HKMetadataKeyWasUserEntered] as? NSNumber, NSNumber(value: true))
        XCTAssertEqual(metadata[HKMetadataKeyExternalUUID] as? String, clientRecordId)
        XCTAssertEqual(metadata[HKMetadataKeySyncIdentifier] as? String, clientRecordId)
        XCTAssertEqual(metadata[HKMetadataKeySyncVersion] as? Int, 7)
    }

    func testGenericScalarClientIdentityUsesSyncMetadataForArbitraryNonblankId() throws {
        let clientRecordId = "plates:weight-entry:2026-07-17T12:30:00Z"

        let metadata = try HealthDataClientRecordMetadata.make(
            isManualEntry: false,
            clientRecordId: clientRecordId,
            clientRecordVersion: NSNumber(value: 42)
        )

        XCTAssertNil(metadata[HKMetadataKeyExternalUUID])
        XCTAssertEqual(metadata[HKMetadataKeySyncIdentifier] as? String, clientRecordId)
        XCTAssertEqual(metadata[HKMetadataKeySyncVersion] as? Int, 42)
    }

    func testGenericScalarClientIdentityAllowsLegacyPairlessWritesOnly() throws {
        let legacyMetadata = try HealthDataClientRecordMetadata.make(
            isManualEntry: false,
            clientRecordId: NSNull(),
            clientRecordVersion: NSNull()
        )
        XCTAssertEqual(legacyMetadata.count, 1)
        XCTAssertEqual(legacyMetadata[HKMetadataKeyWasUserEntered] as? NSNumber, NSNumber(value: false))

        let clientRecordId = "018f8d7e-3333-7333-8333-333333333333"
        XCTAssertThrowsError(
            try HealthDataClientRecordMetadata.make(
                isManualEntry: false,
                clientRecordId: clientRecordId,
                clientRecordVersion: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? HealthDataClientRecordMetadataError,
                .incompleteClientRecordIdentity
            )
        }
    }

    func testGenericScalarClientIdentityRejectsIncompletePairsAndMalformedValues() {
        let clientRecordId = "018f8d7e-3333-7333-8333-333333333333"

        XCTAssertThrowsError(
            try HealthDataClientRecordMetadata.make(
                isManualEntry: false,
                clientRecordId: clientRecordId,
                clientRecordVersion: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? HealthDataClientRecordMetadataError,
                .incompleteClientRecordIdentity
            )
        }

        XCTAssertThrowsError(
            try HealthDataClientRecordMetadata.make(
                isManualEntry: false,
                clientRecordId: nil,
                clientRecordVersion: NSNumber(value: 0)
            )
        ) { error in
            XCTAssertEqual(
                error as? HealthDataClientRecordMetadataError,
                .incompleteClientRecordIdentity
            )
        }

        for blankId in ["", " \n\t "] {
            XCTAssertThrowsError(
                try HealthDataClientRecordMetadata.make(
                    isManualEntry: false,
                    clientRecordId: blankId,
                    clientRecordVersion: NSNumber(value: 0)
                )
            ) { error in
                XCTAssertEqual(
                    error as? HealthDataClientRecordMetadataError,
                    .invalidClientRecordId
                )
            }
        }

        for invalidVersion in [
            NSNumber(value: true),
            NSNumber(value: 1.5),
            NSNumber(value: Double.nan),
            NSNumber(value: Double.infinity),
            NSNumber(value: -1),
        ] {
            XCTAssertThrowsError(
                try HealthDataClientRecordMetadata.make(
                    isManualEntry: false,
                    clientRecordId: clientRecordId,
                    clientRecordVersion: invalidVersion
                )
            ) { error in
                XCTAssertEqual(
                    error as? HealthDataClientRecordMetadataError,
                    .invalidClientRecordVersion
                )
            }
        }
    }

    func testWriteForwardsEveryFieldWithoutLosingPositiveOrNegativeInt64EpochsAndEncodesEveryResultField() throws {
        let operations = try FakeWorkoutOperations()
        operations.writeResult = try WorkoutWriteResult(
            status: .written,
            workoutRecordId: "native-workout",
            energyRecordId: "native-energy",
            energyStatus: .written,
            retryable: false,
            submissionCertainty: .submitted,
            platformCode: "nativeSuccess"
        )
        let handler = HealthWorkoutChannelHandler(operations: operations)

        let value = receive(label: "write") { result in
            handler.write(call: flutterCall("writeWorkoutData", validWriteArguments()), result: result)
        }

        let request = try XCTUnwrap(operations.lastWriteRequest)
        XCTAssertEqual(request.workoutClientRecordId, workoutClientRecordID)
        XCTAssertEqual(request.energyClientRecordId, energyClientRecordID)
        XCTAssertEqual(request.clientRecordVersion, 0)
        XCTAssertEqual(request.activityType, "TRADITIONAL_STRENGTH_TRAINING")
        XCTAssertNotEqual(Int64(Double(exactStartEpochMilliseconds)), exactStartEpochMilliseconds)
        XCTAssertNotEqual(Int64(Double(exactEndEpochMilliseconds)), exactEndEpochMilliseconds)
        XCTAssertEqual(request.startEpochMilliseconds, exactStartEpochMilliseconds)
        XCTAssertEqual(request.endEpochMilliseconds, exactEndEpochMilliseconds)
        XCTAssertEqual(request.startZoneOffsetSeconds, -18_000)
        XCTAssertEqual(request.endZoneOffsetSeconds, -14_400)
        XCTAssertEqual(request.activeEnergyKcal, 321.75)
        XCTAssertEqual(request.title, "Strength Session")
        XCTAssertEqual(request.recordingProvenance, .activelyRecorded)
        XCTAssertEqual(request.recordingDevice, .watch)
        XCTAssertEqual(operations.writeCallCount, 1)

        let map = try methodChannelMap(value)
        XCTAssertEqual(
            Set(map.keys),
            Set([
                "status", "workoutRecordId", "energyRecordId", "energyStatus", "retryable",
                "submissionCertainty", "platformCode",
            ])
        )
        XCTAssertEqual(map["status"] as? String, "written")
        XCTAssertEqual(map["workoutRecordId"] as? String, "native-workout")
        XCTAssertEqual(map["energyRecordId"] as? String, "native-energy")
        XCTAssertEqual(map["energyStatus"] as? String, "written")
        XCTAssertEqual(map["retryable"] as? Bool, false)
        XCTAssertEqual(map["submissionCertainty"] as? String, "submitted")
        XCTAssertEqual(map["platformCode"] as? String, "nativeSuccess")

        let negativeArguments = validWriteArguments()
        negativeArguments.setObject(
            NSNumber(value: negativeExactStartEpochMilliseconds),
            forKey: "startTime" as NSString
        )
        negativeArguments.setObject(
            NSNumber(value: negativeExactEndEpochMilliseconds),
            forKey: "endTime" as NSString
        )

        _ = receive(label: "negative-epoch-write") { result in
            handler.write(call: flutterCall("writeWorkoutData", negativeArguments), result: result)
        }

        let negativeRequest = try XCTUnwrap(operations.lastWriteRequest)
        XCTAssertNotEqual(Int64(Double(negativeExactStartEpochMilliseconds)), negativeExactStartEpochMilliseconds)
        XCTAssertNotEqual(Int64(Double(negativeExactEndEpochMilliseconds)), negativeExactEndEpochMilliseconds)
        XCTAssertEqual(negativeRequest.startEpochMilliseconds, negativeExactStartEpochMilliseconds)
        XCTAssertEqual(negativeRequest.endEpochMilliseconds, negativeExactEndEpochMilliseconds)
        XCTAssertEqual(operations.writeCallCount, 2)
    }

    func testLookupForwardsIdentityAndDatesAndEncodesEveryResultField() throws {
        let operations = try FakeWorkoutOperations()
        operations.lookupResult = try WorkoutLookupResult(
            workout: RecordLookup(status: .present, recordId: "native-workout"),
            energy: RecordLookup(status: .absent),
            derivedStatus: .workoutOnly,
            platformCode: "lookupComplete"
        )
        let handler = HealthWorkoutChannelHandler(operations: operations)

        let value = receive(label: "lookup") { result in
            handler.lookup(call: flutterCall("lookupWorkoutData", validLookupArguments()), result: result)
        }

        let request = try XCTUnwrap(operations.lastLookupRequest)
        XCTAssertEqual(request.workoutClientRecordId, workoutClientRecordID)
        XCTAssertEqual(request.energyClientRecordId, energyClientRecordID)
        XCTAssertEqual(
            request.start.timeIntervalSince1970 * 1_000, Double(lookupStartEpochMilliseconds),
            accuracy: 0.25)
        XCTAssertEqual(
            request.end.timeIntervalSince1970 * 1_000, Double(lookupEndEpochMilliseconds), accuracy: 0.25)
        XCTAssertEqual(operations.lookupCallCount, 1)

        let map = try methodChannelMap(value)
        XCTAssertEqual(Set(map.keys), Set(["workout", "energy", "derivedStatus", "platformCode"]))
        let workout = try XCTUnwrap(map["workout"] as? [String: Any])
        let energy = try XCTUnwrap(map["energy"] as? [String: Any])
        XCTAssertEqual(Set(workout.keys), Set(["status", "recordId"]))
        XCTAssertEqual(Set(energy.keys), Set(["status", "recordId"]))
        XCTAssertEqual(workout["status"] as? String, "present")
        XCTAssertEqual(workout["recordId"] as? String, "native-workout")
        XCTAssertEqual(energy["status"] as? String, "absent")
        XCTAssertTrue(energy["recordId"] is NSNull)
        XCTAssertEqual(map["derivedStatus"] as? String, "workoutOnly")
        XCTAssertEqual(map["platformCode"] as? String, "lookupComplete")
    }

    func testAuthorizationForwardsExactTypesAndEncodesEveryState() throws {
        let operations = try FakeWorkoutOperations()
        operations.authorizationResult = try HealthAuthorizationSnapshot(
            available: true,
            types: [
                HealthTypeAuthorization(
                    type: "WORKOUT",
                    read: .requestedOrUnknown,
                    write: .denied
                ),
                HealthTypeAuthorization(
                    type: "ACTIVE_ENERGY_BURNED",
                    read: .requestedOrUnknown,
                    write: .authorized
                ),
                HealthTypeAuthorization(
                    type: "WEIGHT",
                    read: .requestedOrUnknown,
                    write: .notDetermined
                ),
                HealthTypeAuthorization(
                    type: "SLEEP_ASLEEP",
                    read: .requestedOrUnknown,
                    write: .denied
                ),
            ],
            platformCode: "exactSnapshot"
        )
        let handler = HealthWorkoutChannelHandler(operations: operations)
        let requestedTypes = [
            "WORKOUT", "ACTIVE_ENERGY_BURNED", "WEIGHT", "SLEEP_ASLEEP",
        ]

        let value = receive(label: "authorization") { result in
            let arguments: NSDictionary = ["types": requestedTypes]
            handler.authorizationSnapshot(
                call: flutterCall("getAuthorizationSnapshot", arguments),
                result: result
            )
        }

        XCTAssertEqual(operations.lastAuthorizationTypes, requestedTypes)
        XCTAssertEqual(operations.authorizationCallCount, 1)
        let map = try methodChannelMap(value)
        XCTAssertEqual(Set(map.keys), Set(["available", "types", "platformCode"]))
        XCTAssertEqual(map["available"] as? Bool, true)
        XCTAssertEqual(map["platformCode"] as? String, "exactSnapshot")
        let types = try XCTUnwrap(map["types"] as? [[String: Any]])
        XCTAssertEqual(types.count, 4)
        XCTAssertEqual(types[0]["type"] as? String, "ACTIVE_ENERGY_BURNED")
        XCTAssertEqual(types[0]["read"] as? String, "requestedOrUnknown")
        XCTAssertEqual(types[0]["write"] as? String, "authorized")
        XCTAssertEqual(types[1]["type"] as? String, "SLEEP_ASLEEP")
        XCTAssertEqual(types[1]["read"] as? String, "requestedOrUnknown")
        XCTAssertEqual(types[1]["write"] as? String, "denied")
        XCTAssertEqual(types[2]["type"] as? String, "WEIGHT")
        XCTAssertEqual(types[2]["read"] as? String, "requestedOrUnknown")
        XCTAssertEqual(types[2]["write"] as? String, "notDetermined")
        XCTAssertEqual(types[3]["type"] as? String, "WORKOUT")
        XCTAssertEqual(types[3]["read"] as? String, "requestedOrUnknown")
        XCTAssertEqual(types[3]["write"] as? String, "denied")
    }

    func testMalformedWriteReturnsStructuredInvalidInputWithoutCallingCore() throws {
        let operations = try FakeWorkoutOperations()
        let handler = HealthWorkoutChannelHandler(operations: operations)
        let arguments = validWriteArguments()
        arguments.setObject("not-a-uuid", forKey: "workoutClientRecordId" as NSString)

        let value = receive(label: "invalid-write") { result in
            handler.write(call: flutterCall("writeWorkoutData", arguments), result: result)
        }

        XCTAssertEqual(operations.writeCallCount, 0)
        let map = try methodChannelMap(value)
        XCTAssertEqual(map["status"] as? String, "invalidInput")
        XCTAssertTrue(map["workoutRecordId"] is NSNull)
        XCTAssertTrue(map["energyRecordId"] is NSNull)
        XCTAssertEqual(map["energyStatus"] as? String, "notSubmitted")
        XCTAssertEqual(map["retryable"] as? Bool, false)
        XCTAssertEqual(map["submissionCertainty"] as? String, "notSubmitted")
        XCTAssertEqual(map["platformCode"] as? String, "invalidInput")
    }

    func testMalformedWorkoutOnlyWriteReportsEnergyNotExpected() throws {
        let operations = try FakeWorkoutOperations()
        let handler = HealthWorkoutChannelHandler(operations: operations)
        let arguments = validWriteArguments()
        arguments.removeObject(forKey: "energyClientRecordId")
        arguments.removeObject(forKey: "activeEnergyKcal")
        arguments.setObject("not-a-uuid", forKey: "workoutClientRecordId" as NSString)

        let value = receive(label: "invalid-workout-only-write") { result in
            handler.write(call: flutterCall("writeWorkoutData", arguments), result: result)
        }

        XCTAssertEqual(operations.writeCallCount, 0)
        let map = try methodChannelMap(value)
        XCTAssertEqual(map["status"] as? String, "invalidInput")
        XCTAssertEqual(map["energyStatus"] as? String, "notExpected")
        XCTAssertEqual(map["submissionCertainty"] as? String, "notSubmitted")
    }

    func testStrictParserRejectsLossyNumbersRangesEnumsAndEnergyMismatches() throws {
        let operations = try FakeWorkoutOperations()
        let handler = HealthWorkoutChannelHandler(operations: operations)
        let invalidArguments: [NSDictionary] = [
            mutatedWriteArguments {
                $0.setObject(
                    NSNumber(value: Double(lookupStartEpochMilliseconds)), forKey: "startTime" as NSString)
            },
            mutatedWriteArguments {
                $0.setObject(NSNumber(value: true), forKey: "clientRecordVersion" as NSString)
            },
            mutatedWriteArguments {
                $0.setObject(NSNumber(value: UInt64.max), forKey: "clientRecordVersion" as NSString)
            },
            mutatedWriteArguments {
                $0.setObject(NSNumber(value: Int64.max), forKey: "startZoneOffsetSeconds" as NSString)
            },
            mutatedWriteArguments {
                $0.setObject(NSNumber(value: 64_801), forKey: "endZoneOffsetSeconds" as NSString)
            },
            mutatedWriteArguments { $0.setObject("321.75", forKey: "activeEnergyKcal" as NSString) },
            mutatedWriteArguments { $0.removeObject(forKey: "energyClientRecordId") },
            mutatedWriteArguments { $0.removeObject(forKey: "activeEnergyKcal") },
            mutatedWriteArguments {
                $0.setObject("automatic", forKey: "recordingProvenance" as NSString)
            },
            mutatedWriteArguments { $0.setObject("tablet", forKey: "recordingDevice" as NSString) },
            mutatedWriteArguments { $0.setObject("ROCK_CLIMBING", forKey: "activityType" as NSString) },
        ]

        for (index, arguments) in invalidArguments.enumerated() {
            let value = receive(label: "strict-invalid-\(index)") { result in
                handler.write(call: flutterCall("writeWorkoutData", arguments), result: result)
            }
            let map = try methodChannelMap(value)
            XCTAssertEqual(map["status"] as? String, "invalidInput", "case \(index)")
            XCTAssertEqual(map["submissionCertainty"] as? String, "notSubmitted", "case \(index)")
        }
        XCTAssertEqual(operations.writeCallCount, 0)
    }

    func testNonDictionaryAndNonStringKeysReturnInvalidInput() throws {
        let operations = try FakeWorkoutOperations()
        let handler = HealthWorkoutChannelHandler(operations: operations)
        let invalidKeyArguments = NSMutableDictionary(dictionary: validWriteArguments())
        invalidKeyArguments.setObject("malicious", forKey: NSNumber(value: 7))

        for (index, arguments) in (["not-a-dictionary", invalidKeyArguments] as [Any]).enumerated() {
            let value = receive(label: "container-invalid-\(index)") { result in
                handler.write(call: flutterCall("writeWorkoutData", arguments), result: result)
            }
            let map = try methodChannelMap(value)
            XCTAssertEqual(map["status"] as? String, "invalidInput")
            XCTAssertEqual(map["submissionCertainty"] as? String, "notSubmitted")
        }
        XCTAssertEqual(operations.writeCallCount, 0)
    }

    func testMalformedLookupReturnsTypedUnavailableInvalidInputWithoutCallingCore() throws {
        let operations = try FakeWorkoutOperations()
        let handler = HealthWorkoutChannelHandler(operations: operations)
        let arguments = validLookupArguments()
        arguments.setObject(
            NSNumber(value: Double(lookupEndEpochMilliseconds)), forKey: "endTime" as NSString)

        let value = receive(label: "invalid-lookup") { result in
            handler.lookup(call: flutterCall("lookupWorkoutData", arguments), result: result)
        }

        XCTAssertEqual(operations.lookupCallCount, 0)
        let map = try methodChannelMap(value)
        let workout = try XCTUnwrap(map["workout"] as? [String: Any])
        let energy = try XCTUnwrap(map["energy"] as? [String: Any])
        XCTAssertEqual(workout["status"] as? String, "unavailable")
        XCTAssertEqual(energy["status"] as? String, "unavailable")
        XCTAssertEqual(map["derivedStatus"] as? String, "unavailable")
        XCTAssertEqual(map["platformCode"] as? String, "invalidInput")
    }

    func testUnavailableHealthKitResultsStayStructuredForAllThreeMethods() throws {
        let operations = try FakeWorkoutOperations()
        operations.writeResult = try WorkoutWriteResult(
            status: .unavailable,
            workoutRecordId: nil,
            energyRecordId: nil,
            energyStatus: .notSubmitted,
            retryable: true,
            submissionCertainty: .notSubmitted,
            platformCode: "healthDataUnavailable"
        )
        operations.lookupResult = try WorkoutLookupResult(
            workout: RecordLookup(status: .unavailable),
            energy: RecordLookup(status: .unavailable),
            derivedStatus: .unavailable,
            platformCode: "healthDataUnavailable"
        )
        operations.authorizationResult = try HealthAuthorizationSnapshot(
            available: false,
            types: [
                HealthTypeAuthorization(type: "WORKOUT", read: .unavailable, write: .unavailable)
            ],
            platformCode: "healthDataUnavailable"
        )
        let handler = HealthWorkoutChannelHandler(operations: operations)

        let writeValue = receive(label: "unavailable-write") { result in
            handler.write(call: flutterCall("writeWorkoutData", validWriteArguments()), result: result)
        }
        let lookupValue = receive(label: "unavailable-lookup") { result in
            handler.lookup(call: flutterCall("lookupWorkoutData", validLookupArguments()), result: result)
        }
        let authorizationValue = receive(label: "unavailable-authorization") { result in
            let arguments: NSDictionary = ["types": ["WORKOUT"]]
            handler.authorizationSnapshot(
                call: flutterCall("getAuthorizationSnapshot", arguments),
                result: result
            )
        }

        let write = try methodChannelMap(writeValue)
        XCTAssertEqual(write["status"] as? String, "unavailable")
        XCTAssertEqual(write["energyStatus"] as? String, "notSubmitted")
        XCTAssertEqual(write["submissionCertainty"] as? String, "notSubmitted")
        XCTAssertEqual(write["platformCode"] as? String, "healthDataUnavailable")
        let lookup = try methodChannelMap(lookupValue)
        XCTAssertEqual(lookup["derivedStatus"] as? String, "unavailable")
        XCTAssertEqual(lookup["platformCode"] as? String, "healthDataUnavailable")
        let authorization = try methodChannelMap(authorizationValue)
        XCTAssertEqual(authorization["available"] as? Bool, false)
        XCTAssertEqual(authorization["platformCode"] as? String, "healthDataUnavailable")
    }

    func testMissingCoreOperationsReturnsTypedUnavailableResults() throws {
        let handler = HealthWorkoutChannelHandler(operations: nil)

        let writeValue = receive(label: "missing-core-write") { result in
            handler.write(call: flutterCall("writeWorkoutData", validWriteArguments()), result: result)
        }
        let write = try methodChannelMap(writeValue)
        XCTAssertEqual(write["status"] as? String, "unavailable")
        XCTAssertEqual(write["submissionCertainty"] as? String, "notSubmitted")
        XCTAssertEqual(write["platformCode"] as? String, "coreInitializationFailed")

        let lookupValue = receive(label: "missing-core-lookup") { result in
            handler.lookup(call: flutterCall("lookupWorkoutData", validLookupArguments()), result: result)
        }
        let lookup = try methodChannelMap(lookupValue)
        let workout = try XCTUnwrap(lookup["workout"] as? [String: Any])
        let energy = try XCTUnwrap(lookup["energy"] as? [String: Any])
        XCTAssertEqual(workout["status"] as? String, "unavailable")
        XCTAssertEqual(energy["status"] as? String, "unavailable")
        XCTAssertEqual(lookup["derivedStatus"] as? String, "unavailable")
        XCTAssertEqual(lookup["platformCode"] as? String, "coreInitializationFailed")

        let authorizationValue = receive(label: "missing-core-authorization") { result in
            let arguments: NSDictionary = ["types": ["WORKOUT"]]
            handler.authorizationSnapshot(
                call: flutterCall("getAuthorizationSnapshot", arguments),
                result: result
            )
        }
        let authorization = try methodChannelMap(authorizationValue)
        XCTAssertEqual(authorization["available"] as? Bool, false)
        XCTAssertEqual(authorization["platformCode"] as? String, "coreInitializationFailed")
    }

    func testMalformedAuthorizationCompletesOnceWithInvalidInputWithoutCallingCore() throws {
        let operations = try FakeWorkoutOperations()
        let handler = HealthWorkoutChannelHandler(operations: operations)
        let arguments: NSDictionary = ["types": ["WORKOUT", "WORKOUT"]]

        let value = receive(label: "invalid-authorization") { result in
            handler.authorizationSnapshot(
                call: flutterCall("getAuthorizationSnapshot", arguments),
                result: result
            )
        }

        XCTAssertEqual(operations.authorizationCallCount, 0)
        let error = try XCTUnwrap(value as? FlutterError)
        XCTAssertEqual(error.code, "invalidInput")
    }

    func testMaliciousDuplicateAndConcurrentCoreCompletionsReachFlutterExactlyOnceOnMain() throws {
        let operations = try FakeWorkoutOperations()
        operations.completeWriteTwice = true
        operations.concurrentWriteCompletionCount = 512
        operations.duplicateWriteResult = try WorkoutWriteResult(
            status: .unavailable,
            workoutRecordId: nil,
            energyRecordId: nil,
            energyStatus: .notSubmitted,
            retryable: true,
            submissionCertainty: .notSubmitted,
            platformCode: "maliciousDuplicate"
        )
        let handler = HealthWorkoutChannelHandler(operations: operations)
        let callback = expectation(description: "one Flutter callback")
        callback.assertForOverFulfill = true
        var callbackCount = 0
        var value: Any?

        handler.write(call: flutterCall("writeWorkoutData", validWriteArguments())) { received in
            XCTAssertTrue(Thread.isMainThread)
            callbackCount += 1
            value = received
            callback.fulfill()
        }
        wait(for: [callback], timeout: 2)

        XCTAssertEqual(callbackCount, 1)
        let map = try methodChannelMap(value)
        XCTAssertEqual(map["status"] as? String, "written")
        XCTAssertEqual(map["submissionCertainty"] as? String, "submitted")
    }

    private func receive(
        label: String,
        invoke: (@escaping FlutterResult) -> Void
    ) -> Any? {
        let callback = expectation(description: label)
        callback.assertForOverFulfill = true
        var value: Any?
        invoke { received in
            XCTAssertTrue(Thread.isMainThread)
            value = received
            callback.fulfill()
        }
        wait(for: [callback], timeout: 2)
        return value
    }
}

private final class FakeWorkoutOperations: HealthWorkoutOperationsProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedWriteRequest: WorkoutWriteRequest?
    private var capturedLookupRequest: WorkoutLookupRequest?
    private var capturedAuthorizationTypes: [String]?
    private var writeCalls = 0
    private var lookupCalls = 0
    private var authorizationCalls = 0

    var writeResult: WorkoutWriteResult
    var lookupResult: WorkoutLookupResult
    var authorizationResult: HealthAuthorizationSnapshot
    var duplicateWriteResult: WorkoutWriteResult?
    var completeWriteTwice = false
    var concurrentWriteCompletionCount = 0

    init() throws {
        writeResult = try WorkoutWriteResult(
            status: .written,
            workoutRecordId: "native-workout",
            energyRecordId: "native-energy",
            energyStatus: .written,
            retryable: false,
            submissionCertainty: .submitted
        )
        lookupResult = try WorkoutLookupResult(
            workout: RecordLookup(status: .present, recordId: "native-workout"),
            energy: RecordLookup(status: .absent),
            derivedStatus: .workoutOnly
        )
        authorizationResult = try HealthAuthorizationSnapshot(
            available: true,
            types: [
                HealthTypeAuthorization(
                    type: "WORKOUT",
                    read: .requestedOrUnknown,
                    write: .authorized
                ),
                HealthTypeAuthorization(
                    type: "ACTIVE_ENERGY_BURNED",
                    read: .requestedOrUnknown,
                    write: .authorized
                ),
            ]
        )
    }

    var lastWriteRequest: WorkoutWriteRequest? {
        lock.withLock { capturedWriteRequest }
    }

    var lastLookupRequest: WorkoutLookupRequest? {
        lock.withLock { capturedLookupRequest }
    }

    var lastAuthorizationTypes: [String]? {
        lock.withLock { capturedAuthorizationTypes }
    }

    var writeCallCount: Int {
        lock.withLock { writeCalls }
    }

    var lookupCallCount: Int {
        lock.withLock { lookupCalls }
    }

    var authorizationCallCount: Int {
        lock.withLock { authorizationCalls }
    }

    func write(
        _ request: WorkoutWriteRequest,
        completion: @escaping @Sendable (WorkoutWriteResult) -> Void
    ) {
        lock.withLock {
            capturedWriteRequest = request
            writeCalls += 1
        }
        completion(writeResult)
        if completeWriteTwice {
            completion(duplicateWriteResult ?? writeResult)
        }
        if concurrentWriteCompletionCount > 0 {
            let repeatedResult = duplicateWriteResult ?? writeResult
            DispatchQueue.concurrentPerform(iterations: concurrentWriteCompletionCount) { _ in
                completion(repeatedResult)
            }
        }
    }

    func lookup(
        _ request: WorkoutLookupRequest,
        completion: @escaping @Sendable (WorkoutLookupResult) -> Void
    ) {
        lock.withLock {
            capturedLookupRequest = request
            lookupCalls += 1
        }
        completion(lookupResult)
    }

    func authorizationSnapshot(for requestedTypes: [String]) throws -> HealthAuthorizationSnapshot {
        lock.withLock {
            capturedAuthorizationTypes = requestedTypes
            authorizationCalls += 1
        }
        return authorizationResult
    }
}

private let workoutClientRecordID = "11111111-1111-1111-1111-111111111111"
private let energyClientRecordID = "22222222-2222-2222-2222-222222222222"
private let exactStartEpochMilliseconds: Int64 = 9_007_199_254_740_993
private let exactEndEpochMilliseconds: Int64 = 9_007_199_254_745_993
private let negativeExactStartEpochMilliseconds: Int64 = -9_007_199_254_745_993
private let negativeExactEndEpochMilliseconds: Int64 = -9_007_199_254_740_993
private let lookupStartEpochMilliseconds: Int64 = 1_720_000_000_001
private let lookupEndEpochMilliseconds: Int64 = 1_720_003_600_001

private func validWriteArguments() -> NSMutableDictionary {
    [
        "workoutClientRecordId": workoutClientRecordID,
        "energyClientRecordId": energyClientRecordID,
        "clientRecordVersion": NSNumber(value: Int64(0)),
        "activityType": "TRADITIONAL_STRENGTH_TRAINING",
        "startTime": NSNumber(value: exactStartEpochMilliseconds),
        "endTime": NSNumber(value: exactEndEpochMilliseconds),
        "startZoneOffsetSeconds": NSNumber(value: Int64(-18_000)),
        "endZoneOffsetSeconds": NSNumber(value: Int64(-14_400)),
        "activeEnergyKcal": NSNumber(value: 321.75),
        "title": "Strength Session",
        "recordingProvenance": "activelyRecorded",
        "recordingDevice": "watch",
    ]
}

private func mutatedWriteArguments(
    _ mutation: (NSMutableDictionary) -> Void
) -> NSDictionary {
    let arguments = validWriteArguments()
    mutation(arguments)
    return arguments
}

private func validLookupArguments() -> NSMutableDictionary {
    [
        "workoutClientRecordId": workoutClientRecordID,
        "energyClientRecordId": energyClientRecordID,
        "startTime": NSNumber(value: lookupStartEpochMilliseconds),
        "endTime": NSNumber(value: lookupEndEpochMilliseconds),
    ]
}

private func flutterCall(_ method: String, _ arguments: Any?) -> FlutterMethodCall {
    FlutterMethodCall(methodName: method, arguments: arguments)
}

private func methodChannelMap(_ value: Any?) throws -> [String: Any] {
    try XCTUnwrap(value as? [String: Any])
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
