import XCTest
@testable import health

final class RequestParsingTests: XCTestCase {
    func testListReadRequestParsesRangeAndManualFilter() throws {
        let request = try SampleReadRequest.list(arguments: [
            "dataTypeKey": HealthConstants.STEPS,
            "dataUnitKey": HealthConstants.COUNT,
            "startTime": NSNumber(value: 1000),
            "endTime": NSNumber(value: 2000),
            "limit": 15,
            "recordingMethodsToFilter": [HealthConstants.RecordingMethod.manual.rawValue],
        ])

        XCTAssertEqual(request.dataTypeKey, HealthConstants.STEPS)
        XCTAssertEqual(request.dataUnitKey, HealthConstants.COUNT)
        XCTAssertEqual(request.limit, 15)
        XCTAssertFalse(request.includeManualEntries)
        XCTAssertEqual(request.dateRange?.startDate.timeIntervalSince1970, 1)
        XCTAssertEqual(request.dateRange?.endDate.timeIntervalSince1970, 2)
    }

    func testSingleReadRequestRequiresUUID() {
        XCTAssertThrowsError(try SampleReadRequest.single(arguments: ["dataTypeKey": HealthConstants.STEPS]))
    }

    func testAuthorizationRequestParsesPermissions() throws {
        let request = try AuthorizationRequest.parse(arguments: [
            "types": [HealthConstants.STEPS, HealthConstants.BIRTH_DATE],
            "permissions": [0, 1],
        ])

        XCTAssertEqual(request.permissions.count, 2)
        XCTAssertEqual(request.permissions[0].access, .read)
        XCTAssertEqual(request.permissions[1].access, .write)
    }

    func testDeleteByUUIDRequestParsesUUID() throws {
        let uuid = UUID()
        let request = try DeleteByUUIDRequest.parse(arguments: [
            "uuid": uuid.uuidString,
            "dataTypeKey": HealthConstants.STEPS,
        ])

        XCTAssertEqual(request.uuid, uuid)
        XCTAssertEqual(request.dataTypeKey, HealthConstants.STEPS)
    }
}
