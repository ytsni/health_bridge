#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif

/// Read-specific methods exposed to the Flutter plugin router.
protocol HealthDataReading: AnyObject {
    func getData(call: FlutterMethodCall, result: @escaping FlutterResult)
    func getDataByUUID(call: FlutterMethodCall, result: @escaping FlutterResult)
    func getIntervalData(call: FlutterMethodCall, result: @escaping FlutterResult)
    func getTotalStepsInInterval(call: FlutterMethodCall, result: @escaping FlutterResult)
}

/// Write-specific methods exposed to the Flutter plugin router.
protocol HealthDataWriting: AnyObject {
    func writeData(call: FlutterMethodCall, result: @escaping FlutterResult) throws
    func writeAudiogram(call: FlutterMethodCall, result: @escaping FlutterResult) throws
    func writeBloodPressure(call: FlutterMethodCall, result: @escaping FlutterResult)
    func writeMeal(call: FlutterMethodCall, result: @escaping FlutterResult)
    func writeInsulinDelivery(call: FlutterMethodCall, result: @escaping FlutterResult)
    func writeMenstruationFlow(call: FlutterMethodCall, result: @escaping FlutterResult) throws
    func writeWorkoutData(call: FlutterMethodCall, result: @escaping FlutterResult)
    func startWorkoutRoute(call: FlutterMethodCall, result: @escaping FlutterResult)
    func insertWorkoutRouteData(call: FlutterMethodCall, result: @escaping FlutterResult)
    func finishWorkoutRoute(call: FlutterMethodCall, result: @escaping FlutterResult)
    func discardWorkoutRoute(call: FlutterMethodCall, result: @escaping FlutterResult)
}

/// Authorization and deletion methods exposed to the Flutter plugin router.
protocol HealthDataOperating: AnyObject {
    func checkIfHealthDataAvailable(call: FlutterMethodCall, result: @escaping FlutterResult)
    func hasPermissions(call: FlutterMethodCall, result: @escaping FlutterResult) throws
    func requestAuthorization(call: FlutterMethodCall, result: @escaping FlutterResult) throws
    func delete(call: FlutterMethodCall, result: @escaping FlutterResult)
    func deleteByUUID(call: FlutterMethodCall, result: @escaping FlutterResult) throws
}
