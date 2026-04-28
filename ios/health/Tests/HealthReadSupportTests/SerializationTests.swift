import HealthKit
import XCTest
@testable import health

final class SerializationTests: XCTestCase {
    func testCategoryFilterMatchesConfiguredSleepVariants() {
        XCTAssertTrue(CategorySampleFilter.includes(4, for: HealthConstants.SLEEP_DEEP))
        XCTAssertFalse(CategorySampleFilter.includes(3, for: HealthConstants.SLEEP_DEEP))
        XCTAssertTrue(CategorySampleFilter.includes(2, for: HealthConstants.HEADACHE_MILD))
        XCTAssertFalse(CategorySampleFilter.includes(1, for: HealthConstants.HEADACHE_MILD))
    }

    func testQuantitySerializerUsesProvidedUnitAndMetadata() {
        let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 72.5),
            start: Date(timeIntervalSince1970: 10),
            end: Date(timeIntervalSince1970: 20),
            metadata: [HKMetadataKeyWasUserEntered: true, "source": "unit-test", "quality": 7]
        )

        let payload = QuantitySampleSerializer().serialize(
            sample,
            context: SampleSerializationContext(
                dataTypeKey: HealthConstants.WEIGHT,
                unit: HKUnit.gramUnit(with: .kilo),
                workoutActivityCoder: WorkoutActivityTypeCoder(activityTypesByPluginKey: [:])
            )
        )

        guard let value = payload?["value"] as? Double else {
            return XCTFail("Expected serialized quantity value")
        }

        XCTAssertEqual(value, 72.5, accuracy: 0.001)
        XCTAssertEqual(payload?["recording_method"] as? Int, HealthConstants.RecordingMethod.manual.rawValue)
        XCTAssertEqual(payload?["dataUnitKey"] as? String, HKUnit.gramUnit(with: .kilo).unitString)
        let metadata = payload?["metadata"] as? [String: Any]
        XCTAssertEqual(metadata?["source"] as? String, "unit-test")
        XCTAssertEqual(metadata?["quality"] as? Int, 7)
    }

    func testWorkoutSerializerProvidesLegacyFields() {
        let workout = HKWorkout(
            activityType: .running,
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200),
            duration: 100,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 350),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000),
            metadata: [HKMetadataKeyWasUserEntered: false]
        )

        let payload = WorkoutSampleSerializer().serialize(
            workout,
            context: SampleSerializationContext(
                dataTypeKey: HealthConstants.WORKOUT,
                unit: nil,
                workoutActivityCoder: WorkoutActivityTypeCoder(
                    activityTypesByPluginKey: ["RUNNING": .running]
                )
            )
        )

        XCTAssertEqual(payload?["workoutActivityType"] as? String, "RUNNING")
        XCTAssertEqual(payload?["total_energy_burned"] as? Int, 350)
        XCTAssertEqual(payload?["total_distance"] as? Int, 5000)
    }
}
