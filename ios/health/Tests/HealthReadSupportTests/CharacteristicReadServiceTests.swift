import Foundation
import HealthKit
import XCTest
@testable import health

final class CharacteristicReadServiceTests: XCTestCase {
    func testReadReturnsFailureWhenStoreThrows() throws {
        let service = CharacteristicReadService(store: ThrowingCharacteristicStore())
        let request = try SampleReadRequest.list(arguments: ["dataTypeKey": HealthConstants.BIRTH_DATE])

        let result = service.read(for: request)

        switch result {
        case .success:
            XCTFail("Expected characteristic read to fail")
        case let .failure(error):
            XCTAssertEqual(error.localizedDescription, "boom")
        }
    }
}

private final class ThrowingCharacteristicStore: HealthStoreProxying {
    func execute(_ query: HKQuery) {}

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>,
        completion: @escaping (Bool, (any Error)?) -> Void
    ) {
        completion(true, nil)
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { .notDetermined }

    func delete(_ objects: [HKObject], completion: @escaping (Bool, (any Error)?) -> Void) {
        completion(true, nil)
    }

    func dateOfBirth() throws -> Date? { throw TestError.boom }
    func biologicalSex() throws -> HKBiologicalSex { .notSet }
    func bloodType() throws -> HKBloodType { .notSet }
}

private enum TestError: LocalizedError {
    case boom

    var errorDescription: String? { "boom" }
}
