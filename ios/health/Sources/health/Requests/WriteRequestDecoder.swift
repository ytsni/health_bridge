import CoreLocation
import Foundation

/// Decodes raw Flutter write arguments into typed request models.
enum WriteRequestDecoder {
    /// Canonical nutrient keys supported by meal writes.
    private static let nutritionKeys = [
        "calories",
        "protein",
        "carbs",
        "fat",
        "caffeine",
        "vitamin_a",
        "b1_thiamine",
        "b2_riboflavin",
        "b3_niacin",
        "b5_pantothenic_acid",
        "b6_pyridoxine",
        "b7_biotin",
        "b9_folate",
        "b12_cobalamin",
        "vitamin_c",
        "vitamin_d",
        "vitamin_e",
        "vitamin_k",
        "calcium",
        "chloride",
        "cholesterol",
        "chromium",
        "copper",
        "fat_unsaturated",
        "fat_monounsaturated",
        "fat_polyunsaturated",
        "fat_saturated",
        "fiber",
        "iodine",
        "iron",
        "magnesium",
        "manganese",
        "molybdenum",
        "phosphorus",
        "potassium",
        "selenium",
        "sodium",
        "sugar",
        "water",
        "zinc",
    ]

    /// Decodes the common write payload used by generic quantity and category writes.
    static func decodeGeneric(arguments: Any?) throws -> GenericWriteRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        return GenericWriteRequest(
            value: try parser.requiredDouble("value", message: "Invalid Arguments"),
            dataTypeKey: try parser.requiredString("dataTypeKey", message: "Invalid Arguments"),
            dataUnitKey: try parser.requiredString("dataUnitKey", message: "Invalid Arguments"),
            startDate: try parser.requiredDate("startTime", message: "Invalid Arguments"),
            endDate: try parser.requiredDate("endTime", message: "Invalid Arguments"),
            recordingMethod: try parser.requiredInt("recordingMethod", message: "Invalid Arguments")
        )
    }

    /// Decodes an audiogram payload.
    static func decodeAudiogram(arguments: Any?) throws -> AudiogramWriteRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        guard
            let frequencies = parser.arguments["frequencies"] as? [Double],
            let leftEarSensitivities = parser.arguments["leftEarSensitivities"] as? [Double],
            let rightEarSensitivities = parser.arguments["rightEarSensitivities"] as? [Double]
        else {
            throw WriteRequestParsingError.invalidArguments("Invalid Arguments")
        }

        return AudiogramWriteRequest(
            frequencies: frequencies,
            leftEarSensitivities: leftEarSensitivities,
            rightEarSensitivities: rightEarSensitivities,
            startDate: try parser.requiredDate("startTime", message: "Invalid Arguments"),
            endDate: try parser.requiredDate("endTime", message: "Invalid Arguments"),
            metadata: parser.metadata("metadata")
        )
    }

    /// Decodes a blood pressure payload.
    static func decodeBloodPressure(arguments: Any?) throws -> BloodPressureWriteRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        return BloodPressureWriteRequest(
            systolic: try parser.requiredDouble("systolic"),
            diastolic: try parser.requiredDouble("diastolic"),
            startDate: try parser.requiredDate("startTime"),
            endDate: try parser.requiredDate("endTime"),
            recordingMethod: try parser.requiredInt("recordingMethod")
        )
    }

    /// Decodes a nutrition payload and gathers any present nutrient keys.
    static func decodeMeal(arguments: Any?) throws -> MealWriteRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        var nutrients: [String: Double] = [:]
        for key in nutritionKeys {
            if let value = parser.optionalDouble(key) {
                nutrients[key] = value
            }
        }

        return MealWriteRequest(
            name: parser.optionalString("name"),
            startDate: try parser.requiredDate("start_time"),
            endDate: try parser.requiredDate("end_time"),
            mealType: parser.optionalString("meal_type"),
            recordingMethod: try parser.requiredInt("recordingMethod"),
            nutrients: nutrients
        )
    }

    /// Decodes an insulin delivery payload.
    static func decodeInsulinDelivery(arguments: Any?) throws -> InsulinDeliveryWriteRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        return InsulinDeliveryWriteRequest(
            units: try parser.requiredDouble("units"),
            reason: try parser.requiredNSNumber("reason"),
            startDate: try parser.requiredDate("startTime"),
            endDate: try parser.requiredDate("endTime")
        )
    }

    /// Decodes a menstruation flow payload.
    static func decodeMenstruationFlow(arguments: Any?) throws -> MenstruationFlowWriteRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        return MenstruationFlowWriteRequest(
            value: try parser.requiredInt("value"),
            endDate: try parser.requiredDate("endTime"),
            isStartOfCycle: try parser.requiredNSNumber("isStartOfCycle"),
            recordingMethod: try parser.requiredInt("recordingMethod")
        )
    }

    /// Decodes a mindfulness payload.
    static func decodeMindfulness(arguments: Any?) throws -> MindfulnessWriteRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        return MindfulnessWriteRequest(
            startDate: try parser.requiredDate("startTime"),
            endDate: try parser.requiredDate("endTime"),
            recordingMethod: try parser.requiredInt("recordingMethod")
        )
    }

    /// Decodes a workout payload with optional energy and distance totals.
    static func decodeWorkout(arguments: Any?) throws -> WorkoutWriteRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        return WorkoutWriteRequest(
            activityType: try parser.requiredString("activityType"),
            startDate: try parser.requiredDate("startTime"),
            endDate: try parser.requiredDate("endTime"),
            totalEnergyBurned: parser.optionalDouble("totalEnergyBurned"),
            totalEnergyBurnedUnitKey: parser.optionalString("totalEnergyBurnedUnit"),
            totalDistance: parser.optionalDouble("totalDistance"),
            totalDistanceUnitKey: parser.optionalString("totalDistanceUnit")
        )
    }

    /// Decodes a request that appends route points to a workout route builder.
    static func decodeWorkoutRouteInsert(arguments: Any?) throws -> WorkoutRouteInsertRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        let locations = try parseLocations(
            parser.locationArray(
                "locations",
                message: "Missing builderId or locations for route insertion"
            )
        )

        return WorkoutRouteInsertRequest(
            builderId: try parser.requiredString(
                "builderId",
                message: "Missing builderId or locations for route insertion"
            ),
            locations: locations
        )
    }

    /// Decodes a request that finishes a workout route and links it to a workout.
    static func decodeWorkoutRouteFinish(arguments: Any?) throws -> WorkoutRouteFinishRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        let workoutUUIDString = try parser.requiredString(
            "workoutUUID",
            message: "Missing builderId or workoutUUID for finishing route"
        )
        guard let workoutUUID = UUID(uuidString: workoutUUIDString) else {
            throw WriteRequestParsingError.invalidArguments(
                "Missing builderId or workoutUUID for finishing route"
            )
        }

        return WorkoutRouteFinishRequest(
            builderId: try parser.requiredString(
                "builderId",
                message: "Missing builderId or workoutUUID for finishing route"
            ),
            workoutUUID: workoutUUID,
            workoutUUIDString: workoutUUIDString,
            metadata: parser.metadata("metadata")
        )
    }

    /// Decodes a request that discards an in-flight workout route builder.
    static func decodeWorkoutRouteDiscard(arguments: Any?) throws -> WorkoutRouteDiscardRequest {
        let parser = try WriteRequestValueParser(arguments: arguments)
        return WorkoutRouteDiscardRequest(
            builderId: try parser.requiredString(
                "builderId",
                message: "Missing builderId for discarding workout route"
            )
        )
    }

    /// Converts route point dictionaries into `CLLocation` values.
    private static func parseLocations(_ rawLocations: [NSDictionary]) throws -> [CLLocation] {
        try rawLocations.map { entry in
            guard
                let latitude = WriteRequestValueParser.doubleValue(entry["latitude"]),
                let longitude = WriteRequestValueParser.doubleValue(entry["longitude"]),
                let timestamp = WriteRequestValueParser.dateValue(from: entry["timestamp"])
            else {
                throw WriteRequestParsingError.invalidArguments(
                    "Invalid workout route location entry"
                )
            }

            let altitude = WriteRequestValueParser.doubleValue(entry["altitude"]) ?? 0
            let horizontalAccuracy =
                WriteRequestValueParser.doubleValue(entry["horizontalAccuracy"])
                ?? kCLLocationAccuracyHundredMeters
            let verticalAccuracy =
                WriteRequestValueParser.doubleValue(entry["verticalAccuracy"])
                ?? kCLLocationAccuracyHundredMeters
            let speed = WriteRequestValueParser.doubleValue(entry["speed"]) ?? -1
            let course = WriteRequestValueParser.doubleValue(entry["course"]) ?? -1
            let speedAccuracy = WriteRequestValueParser.doubleValue(entry["speedAccuracy"])
            let courseAccuracy = WriteRequestValueParser.doubleValue(entry["courseAccuracy"])

            if #available(iOS 13.4, *), let speedAccuracy, let courseAccuracy {
                return CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    altitude: altitude,
                    horizontalAccuracy: horizontalAccuracy,
                    verticalAccuracy: verticalAccuracy,
                    course: course,
                    courseAccuracy: courseAccuracy,
                    speed: speed,
                    speedAccuracy: speedAccuracy,
                    timestamp: timestamp
                )
            }

            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: verticalAccuracy,
                course: course,
                speed: speed,
                timestamp: timestamp
            )
        }
    }
}
