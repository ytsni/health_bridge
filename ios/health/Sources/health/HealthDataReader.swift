#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Facade that bridges Flutter read method calls into typed read services.
final class HealthDataReader: HealthDataReading {
    /// Service that reads sample-shaped payloads.
    private let sampleReadService: SampleReadService

    /// Service that reads aggregate statistics payloads.
    private let intervalReadService: IntervalReadService

    /// Creates the read facade and wires the shared store-backed services.
    init(
        healthStore: HKHealthStore,
        catalog: any HealthCatalogProviding
    ) {
        let store = LiveHealthStoreProxy(store: healthStore)
        let characteristicService = CharacteristicReadService(store: store)
        let routeService = WorkoutRouteReadService(store: store)
        let ecgService = ECGReadService(store: store)

        sampleReadService = SampleReadService(
            store: store,
            dataTypesDict: catalog.dataTypesDict,
            unitDict: catalog.unitDict,
            workoutActivityCoder: catalog,
            characteristicService: characteristicService,
            workoutRouteService: routeService,
            ecgService: ecgService
        )
        intervalReadService = IntervalReadService(
            store: store,
            dataQuantityTypesDict: catalog.dataQuantityTypesDict,
            unitDict: catalog.unitDict
        )
    }

    /// Reads sample data and returns either an array payload or a single value,
    /// depending on the request.
    func getData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let request = try SampleReadRequest.list(arguments: call.arguments as? NSDictionary)
            sampleReadService.read(request) { readerResult in
                self.respond(readerResult, result: result, defaultCode: "HEALTH_ERROR")
            }
        } catch {
            respond(.failure(error), result: result, defaultCode: "ARGUMENT_ERROR")
        }
    }

    /// Reads a single sample by UUID.
    func getDataByUUID(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let request = try SampleReadRequest.single(arguments: call.arguments as? NSDictionary)
            sampleReadService.read(request) { readerResult in
                self.respond(readerResult, result: result, defaultCode: "HEALTH_ERROR")
            }
        } catch {
            respond(.failure(error), result: result, defaultCode: "HEALTH_ERROR")
        }
    }

    /// Reads interval-based statistics for quantity samples.
    func getIntervalData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let request = try IntervalReadRequest.parse(arguments: call.arguments as? NSDictionary)
            intervalReadService.readInterval(request) { readResult in
                self.respond(readResult.map { $0 as Any? }, result: result, defaultCode: "STATISTICS_ERROR")
            }
        } catch {
            respond(.failure(error), result: result, defaultCode: "STATISTICS_ERROR")
        }
    }

    /// Reads a total step count across the requested interval.
    func getTotalStepsInInterval(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let request = TotalStepsRequest.parse(arguments: call.arguments as? NSDictionary)
        intervalReadService.readTotalSteps(request) { readResult in
            self.respond(readResult.map { $0 as Any? }, result: result, defaultCode: "STEPS_ERROR")
        }
    }

    /// Delivers `outcome` to Flutter on the main queue.
    private func respond(
        _ outcome: Result<Any?, Error>,
        result: @escaping FlutterResult,
        defaultCode: String
    ) {
        // Flutter result callbacks must be delivered on the main queue.
        DispatchQueue.main.async {
            switch outcome {
            case let .success(value):
                result(value)
            case let .failure(error):
                result(self.flutterError(from: error, defaultCode: defaultCode))
            }
        }
    }

    /// Maps domain and argument errors into Flutter-friendly error codes.
    private func flutterError(from error: Error, defaultCode: String) -> FlutterError {
        let message = (error as? PluginError)?.message ?? error.localizedDescription
        let code: String

        if message.hasPrefix("Missing required dataTypeKey") {
            code = "ARGUMENT_ERROR"
        } else if message.hasPrefix("Invalid dataTypeKey") {
            code = "INVALID_TYPE"
        } else {
            code = defaultCode
        }

        return FlutterError(code: code, message: message, details: nil)
    }
}
