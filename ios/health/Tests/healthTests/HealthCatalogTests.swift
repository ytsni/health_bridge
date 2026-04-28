import HealthKit
import XCTest
@testable import health

final class HealthCatalogTests: XCTestCase {
    func testCurrentCatalogIncludesCoreMappings() {
        let catalog = HealthCatalog.current()

        XCTAssertEqual(catalog.nutritionList, HealthConstants.nutritionDataTypes)
        XCTAssertNotNil(catalog.unitDict[HealthConstants.GRAM])
        XCTAssertNotNil(catalog.unitDict[HealthConstants.COUNT])
        XCTAssertNotNil(catalog.dataTypesDict[HealthConstants.WORKOUT])
        XCTAssertNotNil(catalog.dataTypesDict[HealthConstants.NUTRITION])
        XCTAssertNotNil(catalog.dataQuantityTypesDict[HealthConstants.STEPS])
        XCTAssertEqual(catalog.workoutActivityTypeMap["RUNNING_TREADMILL"], .running)
        XCTAssertEqual(catalog.workoutActivityTypeMap["ROCK_CLIMBING"], .climbing)
        XCTAssertEqual(catalog.activityType(for: "RUNNING"), .running)
        XCTAssertEqual(catalog.pluginKey(for: .running), "RUNNING")
        XCTAssertEqual(catalog.legacyName(for: .running), "running")
    }

    func testCurrentCatalogPreservesNutritionCompatibilityKeys() {
        let catalog = HealthCatalog.current()

        XCTAssertEqual(HealthConstants.DIETARY_WATER, "WATER")
        XCTAssertEqual(
            HealthConstants.NUTRITION_KEYS["fat_unsaturated"],
            .dietaryFatMonounsaturated
        )
        XCTAssertEqual(HealthConstants.NUTRITION_KEYS["water"], .dietaryWater)
        XCTAssertTrue(catalog.nutritionList.contains(HealthConstants.DIETARY_WATER))
    }

    func testPluginBuildsCatalogOnceAtInitialization() {
        let plugin = HealthPlugin()

        XCTAssertNotNil(plugin.catalog.dataTypesDict[HealthConstants.WORKOUT])
        XCTAssertNotNil(plugin.catalog.dataQuantityTypesDict[HealthConstants.STEPS])
        XCTAssertEqual(plugin.catalog.workoutActivityTypeMap["RUNNING"], .running)
    }
}
