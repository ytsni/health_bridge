import CoreLocation
import XCTest
@testable import health

final class WriteRequestDecoderTests: XCTestCase {
    func testGenericWriteRequestDecoding() throws {
        let request = try WriteRequestDecoder.decodeGeneric(arguments: [
            "value": 98.6,
            "dataTypeKey": "BODY_TEMPERATURE",
            "dataUnitKey": "DEGREE_FAHRENHEIT",
            "startTime": 1_700_000_000_000 as NSNumber,
            "endTime": "1700000005000",
            "recordingMethod": 3,
        ])

        XCTAssertEqual(request.value, 98.6)
        XCTAssertEqual(request.dataTypeKey, "BODY_TEMPERATURE")
        XCTAssertEqual(request.dataUnitKey, "DEGREE_FAHRENHEIT")
        XCTAssertEqual(request.recordingMethod, 3)
        XCTAssertEqual(
            Int(request.endDate.timeIntervalSince1970 * 1000),
            1_700_000_005_000
        )
    }

    func testMealRequestCollectsPresentNutrients() throws {
        let request = try WriteRequestDecoder.decodeMeal(arguments: [
            "name": "Lunch",
            "meal_type": "lunch",
            "start_time": 1_700_000_000_000,
            "end_time": 1_700_000_300_000,
            "recordingMethod": 2,
            "calories": 550.0,
            "protein": 20.5,
            "water": 250,
        ])

        XCTAssertEqual(request.name, "Lunch")
        XCTAssertEqual(request.mealType, "lunch")
        XCTAssertEqual(request.nutrients.count, 3)
        XCTAssertEqual(request.nutrients["calories"], 550.0)
        XCTAssertEqual(request.nutrients["water"], 250.0)
    }

    func testWorkoutRouteInsertDecodingBuildsLocations() throws {
        let request = try WriteRequestDecoder.decodeWorkoutRouteInsert(arguments: [
            "builderId": "builder-1",
            "locations": [
                [
                    "latitude": 55.6761,
                    "longitude": 12.5683,
                    "timestamp": 1_700_000_000_000,
                    "altitude": 14.5,
                ] as NSDictionary,
                [
                    "latitude": "55.6762",
                    "longitude": "12.5684",
                    "timestamp": "1700000001000",
                    "speed": 2.5,
                ] as NSDictionary,
            ],
        ])

        XCTAssertEqual(request.builderId, "builder-1")
        XCTAssertEqual(request.locations.count, 2)
        XCTAssertEqual(request.locations[0].coordinate.latitude, 55.6761, accuracy: 0.0001)
        XCTAssertEqual(request.locations[1].speed, 2.5, accuracy: 0.0001)
    }

    func testWorkoutRouteFinishRejectsInvalidUUID() throws {
        XCTAssertThrowsError(
            try WriteRequestDecoder.decodeWorkoutRouteFinish(arguments: [
                "builderId": "builder-1",
                "workoutUUID": "not-a-uuid",
            ])
        ) { error in
            guard let error = error as? WriteRequestParsingError else {
                return XCTFail("Unexpected error type: \(error)")
            }

            XCTAssertEqual(
                error.localizedDescription,
                "Missing builderId or workoutUUID for finishing route"
            )
        }
    }
}
