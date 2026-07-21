import Flutter
import Foundation
import HealthKit
import XCTest

@testable import health_bridge

final class HealthBodyMassChannelHandlerTests: XCTestCase {
    func testLookupUsesBodyMassTypeAndCombinesCurrentSourceWithExactSyncIdentifier() throws {
        let executor = FakeBodyMassQueryExecutor()
        let sample = makeSample(syncIdentifier: clientRecordID)
        executor.response = .success([sample])
        let handler = HealthBodyMassChannelHandler(
            operations: HealthBodyMassLookupOperations(executor: executor)
        )

        let value = receive(label: "present") { result in
            handler.lookup(call: flutterCall(arguments: validArguments()), result: result)
        }

        XCTAssertEqual(executor.queryCount, 1)
        XCTAssertEqual(executor.quantityType, bodyMassType)
        let expectedPredicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                HKQuery.predicateForObjects(from: HKSource.default()),
                HKQuery.predicateForObjects(
                    withMetadataKey: HKMetadataKeySyncIdentifier,
                    allowedValues: [clientRecordID]
                ),
            ]
        )
        XCTAssertEqual(executor.predicate?.predicateFormat, expectedPredicate.predicateFormat)

        let map = try methodChannelMap(value)
        XCTAssertEqual(Set(map.keys), Set(["status", "recordId", "platformCode"]))
        XCTAssertEqual(map["status"] as? String, "present")
        let recordID = try XCTUnwrap(map["recordId"] as? String)
        XCTAssertEqual(recordID, sample.uuid.uuidString)
        XCTAssertNotNil(UUID(uuidString: recordID))
        XCTAssertTrue(map["platformCode"] is NSNull)
    }

    func testLookupWithNoSamplesReturnsAbsent() throws {
        let executor = FakeBodyMassQueryExecutor()
        executor.response = .success([])
        let handler = HealthBodyMassChannelHandler(
            operations: HealthBodyMassLookupOperations(executor: executor)
        )

        let value = receive(label: "absent") { result in
            handler.lookup(call: flutterCall(arguments: validArguments()), result: result)
        }

        let map = try methodChannelMap(value)
        XCTAssertEqual(map["status"] as? String, "absent")
        XCTAssertTrue(map["recordId"] is NSNull)
        XCTAssertTrue(map["platformCode"] is NSNull)
    }

    func testLookupWithDuplicateSamplesReturnsUnavailable() throws {
        let executor = FakeBodyMassQueryExecutor()
        executor.response = .success([
            makeSample(syncIdentifier: clientRecordID),
            makeSample(syncIdentifier: clientRecordID),
        ])
        let handler = HealthBodyMassChannelHandler(
            operations: HealthBodyMassLookupOperations(executor: executor)
        )

        let value = receive(label: "duplicate") { result in
            handler.lookup(call: flutterCall(arguments: validArguments()), result: result)
        }

        let map = try methodChannelMap(value)
        XCTAssertEqual(map["status"] as? String, "unavailable")
        XCTAssertTrue(map["recordId"] is NSNull)
        XCTAssertEqual(map["platformCode"] as? String, "multipleMatchingRecords")
    }

    func testQueryPrivacyAndLockedFailuresAreTypedUnavailable() throws {
        let cases: [(HealthBodyMassLookupQueryError, String)] = [
            (.queryFailed, "healthKitLookupFailed"),
            (.privacyRestricted, "healthKitPrivacyUnavailable"),
            (.protectedDataUnavailable, "healthKitProtectedDataUnavailable"),
        ]

        for (error, expectedCode) in cases {
            let executor = FakeBodyMassQueryExecutor()
            executor.response = .failure(error)
            let handler = HealthBodyMassChannelHandler(
                operations: HealthBodyMassLookupOperations(executor: executor)
            )

            let value = receive(label: "unavailable-\(expectedCode)") { result in
                handler.lookup(call: flutterCall(arguments: validArguments()), result: result)
            }

            let map = try methodChannelMap(value)
            XCTAssertEqual(map["status"] as? String, "unavailable")
            XCTAssertTrue(map["recordId"] is NSNull)
            XCTAssertEqual(map["platformCode"] as? String, expectedCode)
        }
    }

    func testHandlerRejectsArgumentsOtherThanTheExactIdentityPair() throws {
        let executor = FakeBodyMassQueryExecutor()
        let handler = HealthBodyMassChannelHandler(
            operations: HealthBodyMassLookupOperations(executor: executor)
        )
        let arguments = validArguments()
        arguments["unexpected"] = true

        let value = receive(label: "invalid") { result in
            handler.lookup(call: flutterCall(arguments: arguments), result: result)
        }

        XCTAssertEqual(executor.queryCount, 0)
        let map = try methodChannelMap(value)
        XCTAssertEqual(map["status"] as? String, "unavailable")
        XCTAssertTrue(map["recordId"] is NSNull)
        XCTAssertEqual(map["platformCode"] as? String, "invalidInput")
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

private final class FakeBodyMassQueryExecutor: HealthBodyMassQueryExecuting, @unchecked Sendable {
    var response: Result<[HKQuantitySample], Error> = .success([])
    private(set) var queryCount = 0
    private(set) var quantityType: HKQuantityType?
    private(set) var predicate: NSPredicate?

    func execute(
        quantityType: HKQuantityType,
        predicate: NSPredicate,
        completion: @escaping @Sendable (Result<[HKQuantitySample], Error>) -> Void
    ) {
        queryCount += 1
        self.quantityType = quantityType
        self.predicate = predicate
        completion(response)
    }
}

private let clientRecordID = "018f8d7e-3333-7333-8333-333333333333"
private let measuredAt = Date(timeIntervalSince1970: 1_753_008_000)
private let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass)!

private func validArguments() -> NSMutableDictionary {
    [
        "clientRecordId": clientRecordID,
        "measuredAt": NSNumber(value: Int64(measuredAt.timeIntervalSince1970 * 1_000)),
    ]
}

private func flutterCall(arguments: Any?) -> FlutterMethodCall {
    FlutterMethodCall(methodName: "lookupBodyMassData", arguments: arguments)
}

private func makeSample(syncIdentifier: String) -> HKQuantitySample {
    HKQuantitySample(
        type: bodyMassType,
        quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 72.5),
        start: measuredAt,
        end: measuredAt,
        metadata: [
            HKMetadataKeySyncIdentifier: syncIdentifier,
            HKMetadataKeySyncVersion: 0,
        ]
    )
}

private func methodChannelMap(_ value: Any?) throws -> [String: Any] {
    try XCTUnwrap(value as? [String: Any])
}
