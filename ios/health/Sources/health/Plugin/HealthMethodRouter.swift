#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif

/// Routes Flutter method names to the legacy read, write, and operational service surfaces.
final class HealthMethodRouter {
    /// Facade that serves read-related method calls.
    private let healthDataReader: any HealthDataReading

    /// Facade that serves write-related method calls.
    private let healthDataWriter: any HealthDataWriting

    /// Facade that serves authorization and delete method calls.
    private let healthDataOperations: any HealthDataOperating

    /// Creates a router with the concrete collaborators used by the plugin edge.
    init(
        healthDataReader: any HealthDataReading,
        healthDataWriter: any HealthDataWriting,
        healthDataOperations: any HealthDataOperating
    ) {
        self.healthDataReader = healthDataReader
        self.healthDataWriter = healthDataWriter
        self.healthDataOperations = healthDataOperations
    }

    /// Dispatches a Flutter method call to the matching service operation.
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkIfHealthDataAvailable":
            healthDataOperations.checkIfHealthDataAvailable(call: call, result: result)
        case "requestAuthorization":
            handle(
                result: result,
                errorCode: "REQUEST_AUTH_ERROR",
                messagePrefix: "Error requesting authorization"
            ) {
                try healthDataOperations.requestAuthorization(call: call, result: result)
            }
        case "getData":
            healthDataReader.getData(call: call, result: result)
        case "getDataByUUID":
            healthDataReader.getDataByUUID(call: call, result: result)
        case "getIntervalData":
            healthDataReader.getIntervalData(call: call, result: result)
        case "getTotalStepsInInterval":
            healthDataReader.getTotalStepsInInterval(call: call, result: result)
        case "writeData":
            handle(result: result, errorCode: "WRITE_ERROR", messagePrefix: "Error writing data") {
                try healthDataWriter.writeData(call: call, result: result)
            }
        case "writeAudiogram":
            handle(
                result: result,
                errorCode: "WRITE_ERROR",
                messagePrefix: "Error writing audiogram"
            ) {
                try healthDataWriter.writeAudiogram(call: call, result: result)
            }
        case "writeBloodPressure":
            handle(
                result: result,
                errorCode: "WRITE_ERROR",
                messagePrefix: "Error writing blood pressure"
            ) {
                healthDataWriter.writeBloodPressure(call: call, result: result)
            }
        case "writeMeal":
            handle(result: result, errorCode: "WRITE_ERROR", messagePrefix: "Error writing meal") {
                healthDataWriter.writeMeal(call: call, result: result)
            }
        case "writeInsulinDelivery":
            handle(
                result: result,
                errorCode: "WRITE_ERROR",
                messagePrefix: "Error writing insulin delivery"
            ) {
                healthDataWriter.writeInsulinDelivery(call: call, result: result)
            }
        case "writeWorkoutData":
            handle(
                result: result,
                errorCode: "WRITE_ERROR",
                messagePrefix: "Error writing workout"
            ) {
                healthDataWriter.writeWorkoutData(call: call, result: result)
            }
        case "startWorkoutRoute":
            healthDataWriter.startWorkoutRoute(call: call, result: result)
        case "insertWorkoutRouteData":
            healthDataWriter.insertWorkoutRouteData(call: call, result: result)
        case "finishWorkoutRoute":
            healthDataWriter.finishWorkoutRoute(call: call, result: result)
        case "discardWorkoutRoute":
            healthDataWriter.discardWorkoutRoute(call: call, result: result)
        case "writeMenstruationFlow":
            handle(
                result: result,
                errorCode: "WRITE_ERROR",
                messagePrefix: "Error writing menstruation flow"
            ) {
                try healthDataWriter.writeMenstruationFlow(call: call, result: result)
            }
        case "hasPermissions":
            handle(
                result: result,
                errorCode: "PERMISSION_ERROR",
                messagePrefix: "Error checking permissions"
            ) {
                try healthDataOperations.hasPermissions(call: call, result: result)
            }
        case "delete":
            healthDataOperations.delete(call: call, result: result)
        case "deleteByUUID":
            handle(
                result: result,
                errorCode: "DELETE_ERROR",
                messagePrefix: "Error deleting data by UUID"
            ) {
                try healthDataOperations.deleteByUUID(call: call, result: result)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Wraps synchronous throwing operations and bridges failures back to Flutter.
    private func handle(
        result: @escaping FlutterResult,
        errorCode: String,
        messagePrefix: String,
        operation: () throws -> Void
    ) {
        do {
            try operation()
        } catch {
            result(
                FlutterError(
                    code: errorCode,
                    message: "\(messagePrefix): \(error.localizedDescription)",
                    details: nil
                )
            )
        }
    }
}
