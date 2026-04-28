import HealthKit
import XCTest
@testable import health

final class AuthorizationServiceTests: XCTestCase {
    func testHasPermissionsReturnsNilForReadPermissions() {
        let store = TestHealthStoreProxy()
        let service = AuthorizationService(
            store: store,
            dataTypesDict: [HealthConstants.STEPS: HKObjectType.quantityType(forIdentifier: .stepCount)!],
            characteristicsTypesDict: [:],
            nutritionList: []
        )

        let result = service.hasPermissions(.init(permissions: [
            PermissionRequest(dataTypeKey: HealthConstants.STEPS, access: .read),
        ]))

        XCTAssertNil(result)
    }

    func testHasPermissionsRequiresAuthorizedWritePermission() {
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let store = TestHealthStoreProxy(statuses: [stepType.identifier: .sharingAuthorized])
        let service = AuthorizationService(
            store: store,
            dataTypesDict: [HealthConstants.STEPS: stepType],
            characteristicsTypesDict: [:],
            nutritionList: []
        )

        let result = service.hasPermissions(.init(permissions: [
            PermissionRequest(dataTypeKey: HealthConstants.STEPS, access: .write),
        ]))

        XCTAssertEqual(result, true)
    }

    func testRequestAuthorizationExpandsNutritionAndCharacteristicReads() {
        let expectation = expectation(description: "authorization callback")
        let store = TestHealthStoreProxy()
        let caloriesType = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        let birthDate = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        let service = AuthorizationService(
            store: store,
            dataTypesDict: [HealthConstants.DIETARY_ENERGY_CONSUMED: caloriesType],
            characteristicsTypesDict: [HealthConstants.BIRTH_DATE: birthDate],
            nutritionList: [HealthConstants.DIETARY_ENERGY_CONSUMED]
        )

        service.requestAuthorization(.init(permissions: [
            PermissionRequest(dataTypeKey: HealthConstants.NUTRITION, access: .write),
            PermissionRequest(dataTypeKey: HealthConstants.BIRTH_DATE, access: .read),
        ])) { result in
            XCTAssertEqual(try? result.get(), true)
            XCTAssertEqual(store.lastSharedTypes.map(\.identifier), [caloriesType.identifier])
            XCTAssertEqual(Set(store.lastReadTypes.map(\.identifier)), [birthDate.identifier])
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)
    }
}

private final class TestHealthStoreProxy: HealthStoreProxying {
    private let statuses: [String: HKAuthorizationStatus]
    var lastSharedTypes = Set<HKSampleType>()
    var lastReadTypes = Set<HKObjectType>()

    init(statuses: [String: HKAuthorizationStatus] = [:]) {
        self.statuses = statuses
    }

    func execute(_ query: HKQuery) {}

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>,
        completion: @escaping (Bool, (any Error)?) -> Void
    ) {
        lastSharedTypes = typesToShare
        lastReadTypes = typesToRead
        completion(true, nil)
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        statuses[type.identifier] ?? .notDetermined
    }

    func delete(_ objects: [HKObject], completion: @escaping (Bool, (any Error)?) -> Void) {
        completion(true, nil)
    }

    func dateOfBirth() throws -> Date? { nil }
    func biologicalSex() throws -> HKBiologicalSex { .notSet }
    func bloodType() throws -> HKBloodType { .notSet }
}
