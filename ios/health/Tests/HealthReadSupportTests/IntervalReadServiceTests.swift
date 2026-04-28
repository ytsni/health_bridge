import HealthKit
import XCTest
@testable import health

final class IntervalReadServiceTests: XCTestCase {
    func testStatisticsOptionUsesAggregationStyle() {
        let service = IntervalReadService(
            store: TestIntervalStoreProxy(),
            dataQuantityTypesDict: [:],
            unitDict: [:]
        )

        XCTAssertEqual(
            service.statisticsOption(for: HKObjectType.quantityType(forIdentifier: .stepCount)!),
            .cumulativeSum
        )
        XCTAssertEqual(
            service.statisticsOption(for: HKObjectType.quantityType(forIdentifier: .heartRate)!),
            .discreteAverage
        )
    }
}

private final class TestIntervalStoreProxy: HealthStoreProxying {
    func execute(_ query: HKQuery) {}
    func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>, completion: @escaping (Bool, (any Error)?) -> Void) {}
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { .notDetermined }
    func delete(_ objects: [HKObject], completion: @escaping (Bool, (any Error)?) -> Void) {}
    func dateOfBirth() throws -> Date? { nil }
    func biologicalSex() throws -> HKBiologicalSex { .notSet }
    func bloodType() throws -> HKBloodType { .notSet }
}
