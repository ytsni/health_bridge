#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Facade for authorization and delete flows triggered from Flutter.
final class HealthDataOperations: HealthDataOperating {
    /// Service that handles HealthKit availability and authorization.
    private let authorizationService: AuthorizationService

    /// Service that deletes HealthKit samples.
    private let deleteService: DeleteService

    /// Creates the operation facade and wires the smaller feature services.
    init(
        healthStore: HKHealthStore,
        catalog: any HealthCataloging
    ) {
        let store = LiveHealthStoreProxy(store: healthStore)
        authorizationService = AuthorizationService(
            store: store,
            dataTypesDict: catalog.dataTypesDict,
            characteristicsTypesDict: catalog.characteristicsTypesDict,
            nutritionList: catalog.nutritionList
        )
        deleteService = DeleteService(
            store: store,
            dataTypesDict: catalog.dataTypesDict,
            characteristicsTypesDict: catalog.characteristicsTypesDict
        )
    }

    /// Reports whether HealthKit is available on the current device.
    func checkIfHealthDataAvailable(call _: FlutterMethodCall, result: @escaping FlutterResult) {
        result(authorizationService.checkIfHealthDataAvailable())
    }

    /// Checks read or write permissions for the requested HealthKit types.
    func hasPermissions(call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        let request = try PermissionCheckRequest.parse(arguments: call.arguments as? NSDictionary)
        DispatchQueue.main.async {
            result(self.authorizationService.hasPermissions(request))
        }
    }

    /// Requests HealthKit authorization for the supplied read and write sets.
    func requestAuthorization(call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        let request = try AuthorizationRequest.parse(arguments: call.arguments as? NSDictionary)
        authorizationService.requestAuthorization(request) { authResult in
            DispatchQueue.main.async {
                switch authResult {
                case let .success(success):
                    result(success)
                case let .failure(error):
                    result(self.flutterError(code: "REQUEST_AUTH_ERROR", error: error))
                }
            }
        }
    }

    /// Deletes samples matching the supplied type and date range.
    func delete(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let request = try DeleteRequest.parse(arguments: call.arguments as? NSDictionary)
            deleteService.delete(request) { deleteResult in
                self.respond(deleteResult, result: result)
            }
        } catch {
            DispatchQueue.main.async {
                result(self.flutterError(code: "DELETE_ERROR", error: error))
            }
        }
    }

    /// Deletes a single HealthKit object by UUID.
    func deleteByUUID(call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        let request = try DeleteByUUIDRequest.parse(arguments: call.arguments as? NSDictionary)
        deleteService.deleteByUUID(request) { deleteResult in
            self.respond(deleteResult, result: result)
        }
    }

    /// Converts delete completions into Flutter result values.
    private func respond(_ deleteResult: Result<Bool, Error>, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            switch deleteResult {
            case let .success(success):
                result(success)
            case let .failure(error):
                result(self.flutterError(code: "DELETE_ERROR", error: error))
            }
        }
    }

    /// Normalizes errors into the format expected by the Flutter method channel.
    private func flutterError(code: String, error: Error) -> FlutterError {
        FlutterError(
            code: code,
            message: (error as? PluginError)?.message ?? error.localizedDescription,
            details: nil
        )
    }
}
