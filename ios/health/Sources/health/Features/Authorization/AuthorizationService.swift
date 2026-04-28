import Foundation
import HealthKit

/// Coordinates permission checks and authorization requests against HealthKit.
public final class AuthorizationService {
    /// Store abstraction used for HealthKit authorization calls.
    private let store: HealthStoreProxying

    /// Sample types keyed by plugin data type.
    private let dataTypesDict: [String: HKSampleType]

    /// Characteristic types keyed by plugin data type.
    private let characteristicsTypesDict: [String: HKCharacteristicType]

    /// Nutrition keys expanded from the umbrella nutrition permission.
    private let nutritionList: [String]

    /// Service that interprets HealthKit authorization state.
    private let permissionService: PermissionService

    /// Creates an authorization service with catalog lookups and a store abstraction.
    public init(
        store: HealthStoreProxying,
        dataTypesDict: [String: HKSampleType],
        characteristicsTypesDict: [String: HKCharacteristicType],
        nutritionList: [String],
        permissionService: PermissionService = .init()
    ) {
        self.store = store
        self.dataTypesDict = dataTypesDict
        self.characteristicsTypesDict = characteristicsTypesDict
        self.nutritionList = nutritionList
        self.permissionService = permissionService
    }

    /// Returns whether HealthKit is available on the current device.
    public func checkIfHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Evaluates the current authorization state for each requested permission.
    ///
    /// Returns `nil` when HealthKit cannot confirm the requested read access status.
    public func hasPermissions(_ request: PermissionCheckRequest) -> Bool? {
        for permission in expandNutrition(request.permissions) {
            if let sampleType = dataTypesDict[permission.dataTypeKey] {
                switch permissionService.evaluate(type: sampleType, access: permission.access, store: store) {
                case .granted:
                    break
                case .denied:
                    return false
                case .unknown:
                    return nil
                }
                continue
            }

            if let characteristicType = characteristicsTypesDict[permission.dataTypeKey] {
                if permission.access == .write {
                    return false
                }
                switch permissionService.evaluate(type: characteristicType, access: permission.access, store: store) {
                case .granted:
                    break
                case .denied:
                    return false
                case .unknown:
                    return nil
                }
                continue
            }

            print("Warning: Health data type '\(permission.dataTypeKey)' not found in data dictionaries")
            return false
        }

        return true
    }

    /// Requests the HealthKit read/write scopes described by the request.
    public func requestAuthorization(
        _ request: AuthorizationRequest,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        do {
            let (typesToRead, typesToWrite) = try buildAuthorizationSets(for: request.permissions)
            store.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(success))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    /// Maps typed permission requests into HealthKit read and write sets.
    private func buildAuthorizationSets(
        for permissions: [PermissionRequest]
    ) throws -> (Set<HKObjectType>, Set<HKSampleType>) {
        var typesToRead = Set<HKObjectType>()
        var typesToWrite = Set<HKSampleType>()

        for permission in expandNutrition(permissions) {
            if let sampleType = dataTypesDict[permission.dataTypeKey] {
                switch permission.access {
                case .read:
                    typesToRead.insert(sampleType)
                case .write:
                    typesToWrite.insert(sampleType)
                case .readWrite:
                    typesToRead.insert(sampleType)
                    typesToWrite.insert(sampleType)
                }
            }

            if let characteristicType = characteristicsTypesDict[permission.dataTypeKey] {
                if permission.access == .write {
                    throw PluginError(
                        message: "Cannot request write permission for characteristic type \(characteristicType)"
                    )
                }
                typesToRead.insert(characteristicType)
            }

            if dataTypesDict[permission.dataTypeKey] == nil,
               characteristicsTypesDict[permission.dataTypeKey] == nil
            {
                print("Warning: Health data type '\(permission.dataTypeKey)' not found in data dictionaries")
            }
        }

        return (typesToRead, typesToWrite)
    }

    /// Expands the synthetic nutrition permission into all concrete nutrition sample types.
    private func expandNutrition(_ permissions: [PermissionRequest]) -> [PermissionRequest] {
        permissions.flatMap { permission in
            guard permission.dataTypeKey == HealthConstants.NUTRITION else { return [permission] }
            return nutritionList.map { PermissionRequest(dataTypeKey: $0, access: permission.access) }
        }
    }
}
