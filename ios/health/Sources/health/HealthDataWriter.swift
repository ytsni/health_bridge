#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Facade for all write-specific HealthKit flows.
final class HealthDataWriter: HealthDataWriting {
    /// Writer for generic quantity and category samples.
    private let genericWriter: GenericSampleWriter

    /// Writer for audiogram samples.
    private let audiogramWriter: AudiogramWriter

    /// Writer for blood pressure correlations.
    private let bloodPressureWriter: BloodPressureWriter

    /// Writer for meal correlations.
    private let mealWriter: MealWriter

    /// Writer for insulin delivery samples.
    private let insulinDeliveryWriter: InsulinDeliveryWriter

    /// Writer for menstruation flow samples.
    private let menstruationFlowWriter: MenstruationFlowWriter

    /// Writer for mindfulness session samples.
    private let mindfulnessWriter: MindfulnessWriter

    /// Writer for workout samples.
    private let workoutWriter: WorkoutWriter

    /// Writer for workout route sessions and routes.
    private let workoutRouteWriter: WorkoutRouteWriter

    /// Creates the write facade and wires its specialized writers.
    init(
        healthStore: HKHealthStore,
        catalog: any HealthCatalogProviding
    ) {
        let context = HealthWriteContext(
            healthStore: healthStore,
            dataTypesDict: catalog.dataTypesDict,
            unitDict: catalog.unitDict,
            workoutActivityCoder: catalog
        )
        let sessionManager = WorkoutRouteSessionManager()
        genericWriter = GenericSampleWriter(context: context)
        audiogramWriter = AudiogramWriter(context: context)
        bloodPressureWriter = BloodPressureWriter(context: context)
        mealWriter = MealWriter(context: context)
        insulinDeliveryWriter = InsulinDeliveryWriter(context: context)
        menstruationFlowWriter = MenstruationFlowWriter(context: context)
        mindfulnessWriter = MindfulnessWriter(context: context)
        workoutWriter = WorkoutWriter(context: context)
        workoutRouteWriter = WorkoutRouteWriter(context: context, sessionManager: sessionManager)
    }

    /// Routes a generic write call, including special handling for mindfulness
    /// sessions that do not carry a quantity value.
    func writeData(call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        let request: GenericWriteRequest
        do {
            request = try WriteRequestDecoder.decodeGeneric(arguments: call.arguments)
        } catch {
            throw PluginError(message: "Invalid Arguments")
        }

        if request.dataTypeKey == HealthConstants.MINDFULNESS {
            try mindfulnessWriter.write(
                MindfulnessWriteRequest(
                    startDate: request.startDate,
                    endDate: request.endDate,
                    recordingMethod: request.recordingMethod
                ),
                result: result
            )
            return
        }

        genericWriter.write(request, result: result)
    }

    /// Writes an audiogram sample from the decoded Flutter arguments.
    func writeAudiogram(call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        do {
            try audiogramWriter.write(WriteRequestDecoder.decodeAudiogram(arguments: call.arguments), result: result)
        } catch let error as WriteRequestParsingError {
            throw PluginError(message: error.localizedDescription)
        }
    }

    /// Writes paired systolic and diastolic samples as a single blood pressure reading.
    func writeBloodPressure(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let request = decodeOrReturn(
            { try WriteRequestDecoder.decodeBloodPressure(arguments: call.arguments) },
            message: "Missing or invalid systolic, diastolic, startTime, endTime, or recordingMethod",
            result: result
        ) else { return }
        bloodPressureWriter.write(request, result: result)
    }

    /// Writes a nutrition sample and attached nutrient metadata.
    func writeMeal(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let request = decodeOrReturn(
            { try WriteRequestDecoder.decodeMeal(arguments: call.arguments) },
            message: "Missing or invalid name, start_time, end_time, meal_type, or recordingMethod",
            result: result
        ) else { return }
        mealWriter.write(request, result: result)
    }

    /// Writes an insulin delivery sample.
    func writeInsulinDelivery(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let request = decodeOrReturn(
            { try WriteRequestDecoder.decodeInsulinDelivery(arguments: call.arguments) },
            message: "Missing or invalid units, reason, startTime, or endTime for insulin delivery",
            result: result
        ) else { return }
        insulinDeliveryWriter.write(request, result: result)
    }

    /// Writes a menstruation flow category sample.
    func writeMenstruationFlow(call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        guard let request = decodeOrReturn(
            { try WriteRequestDecoder.decodeMenstruationFlow(arguments: call.arguments) },
            message: "Missing or invalid value, endTime, isStartOfCycle, or recordingMethod for menstruation flow",
            result: result
        ) else { return }
        try menstruationFlowWriter.write(request, result: result)
    }

    /// Writes a workout sample with optional distance and energy totals.
    func writeWorkoutData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let request = decodeOrReturn(
            { try WriteRequestDecoder.decodeWorkout(arguments: call.arguments) },
            message: "Missing or invalid activityType, startTime, or endTime",
            result: result
        ) else { return }
        workoutWriter.write(request, result: result)
    }

    /// Starts a new workout route builder session.
    func startWorkoutRoute(call _: FlutterMethodCall, result: @escaping FlutterResult) {
        workoutRouteWriter.start(result: result)
    }

    /// Appends route points to an in-flight workout route builder.
    func insertWorkoutRouteData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let request = decodeOrReturn(
            { try WriteRequestDecoder.decodeWorkoutRouteInsert(arguments: call.arguments) },
            message: "Missing builderId or locations for route insertion",
            result: result
        ) else { return }
        workoutRouteWriter.insert(request, result: result)
    }

    /// Finishes a workout route builder and associates it with an existing workout.
    func finishWorkoutRoute(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let request = decodeOrReturn(
            { try WriteRequestDecoder.decodeWorkoutRouteFinish(arguments: call.arguments) },
            message: "Missing builderId or workoutUUID for finishing route",
            result: result
        ) else { return }
        workoutRouteWriter.finish(request, result: result)
    }

    /// Discards an in-flight workout route builder without persisting it.
    func discardWorkoutRoute(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let request = decodeOrReturn(
            { try WriteRequestDecoder.decodeWorkoutRouteDiscard(arguments: call.arguments) },
            message: "Missing builderId for discarding workout route",
            result: result
        ) else { return }
        workoutRouteWriter.discard(request, result: result)
    }

    /// Converts request decoding failures into a standard Flutter argument error.
    private func decodeOrReturn<T>(
        _ decode: () throws -> T,
        message: String,
        result: @escaping FlutterResult
    ) -> T? {
        do {
            return try decode()
        } catch {
            result(HealthWriteResultHandler.flutterError(code: "ARGUMENT_ERROR", message: message))
            return nil
        }
    }
}
