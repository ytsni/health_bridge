import CoreFoundation
import Flutter
import Foundation
import HealthKit

/// Executes the narrow, source-scoped HealthKit query used for body-mass
/// reconciliation. Keeping the query behind this protocol makes the identity
/// predicate testable without asking HealthKit for general history.
protocol HealthBodyMassQueryExecuting: Sendable {
    func execute(
        quantityType: HKQuantityType,
        predicate: NSPredicate,
        completion: @escaping @Sendable (Result<[HKQuantitySample], Error>) -> Void
    )
}

final class HealthKitBodyMassQueryExecutor: HealthBodyMassQueryExecuting, @unchecked Sendable {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    func execute(
        quantityType: HKQuantityType,
        predicate: NSPredicate,
        completion: @escaping @Sendable (Result<[HKQuantitySample], Error>) -> Void
    ) {
        // A sync identifier should be unique for this source. Two results are
        // enough to detect corrupted duplicate identity without opening a
        // general history query.
        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: predicate,
            limit: 2,
            sortDescriptors: nil
        ) { _, samples, error in
            if let error {
                completion(.failure(HealthBodyMassLookupQueryError.from(error)))
                return
            }

            completion(.success((samples ?? []).compactMap { $0 as? HKQuantitySample }))
        }
        healthStore.execute(query)
    }
}

enum HealthBodyMassLookupQueryError: Error {
    case queryFailed
    case privacyRestricted
    case protectedDataUnavailable

    static func from(_ error: Error) -> HealthBodyMassLookupQueryError {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain else { return .queryFailed }

        switch HKError.Code(rawValue: nsError.code) {
        case .errorAuthorizationDenied,
            .errorAuthorizationNotDetermined,
            .errorRequiredAuthorizationDenied,
            .errorHealthDataRestricted:
            return .privacyRestricted
        case .errorDatabaseInaccessible:
            return .protectedDataUnavailable
        default:
            return .queryFailed
        }
    }
}

enum HealthBodyMassLookupStatus: String {
    case present
    case absent
    case unavailable
}

struct HealthBodyMassLookupRequest: Sendable {
    let clientRecordId: String
    let measuredAt: Date
}

struct HealthBodyMassLookupResult: Sendable {
    let status: HealthBodyMassLookupStatus
    let recordId: String?
    let platformCode: String?

    static func present(recordId: String) -> HealthBodyMassLookupResult {
        HealthBodyMassLookupResult(
            status: .present,
            recordId: recordId,
            platformCode: nil
        )
    }

    static let absent = HealthBodyMassLookupResult(
        status: .absent,
        recordId: nil,
        platformCode: nil
    )

    static func unavailable(_ platformCode: String) -> HealthBodyMassLookupResult {
        HealthBodyMassLookupResult(
            status: .unavailable,
            recordId: nil,
            platformCode: platformCode
        )
    }
}

protocol HealthBodyMassLookupOperationsProtocol: Sendable {
    func lookup(
        _ request: HealthBodyMassLookupRequest,
        completion: @escaping @Sendable (HealthBodyMassLookupResult) -> Void
    )
}

final class HealthBodyMassLookupOperations: HealthBodyMassLookupOperationsProtocol, @unchecked Sendable {
    private let executor: any HealthBodyMassQueryExecuting

    init(executor: any HealthBodyMassQueryExecuting) {
        self.executor = executor
    }

    func lookup(
        _ request: HealthBodyMassLookupRequest,
        completion: @escaping @Sendable (HealthBodyMassLookupResult) -> Void
    ) {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            completion(.unavailable("bodyMassTypeUnavailable"))
            return
        }

        // The sync identifier, scoped to this app's current HealthKit source,
        // is the record identity. `measuredAt` is still validated at the
        // channel boundary so both platforms receive the same identity pair.
        let predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                HKQuery.predicateForObjects(from: HKSource.default()),
                HKQuery.predicateForObjects(
                    withMetadataKey: HKMetadataKeySyncIdentifier,
                    allowedValues: [request.clientRecordId]
                ),
            ]
        )
        executor.execute(
            quantityType: quantityType,
            predicate: predicate
        ) { response in
            switch response {
            case let .success(samples):
                switch samples.count {
                case 0:
                    completion(.absent)
                case 1:
                    completion(.present(recordId: samples[0].uuid.uuidString))
                default:
                    completion(.unavailable("multipleMatchingRecords"))
                }
            case let .failure(error):
                completion(Self.unavailableResult(for: error))
            }
        }
    }

    private static func unavailableResult(for error: Error) -> HealthBodyMassLookupResult {
        let queryError = (error as? HealthBodyMassLookupQueryError)
            ?? HealthBodyMassLookupQueryError.from(error)
        switch queryError {
        case .queryFailed:
            return .unavailable("healthKitLookupFailed")
        case .privacyRestricted:
            return .unavailable("healthKitPrivacyUnavailable")
        case .protectedDataUnavailable:
            return .unavailable("healthKitProtectedDataUnavailable")
        }
    }
}

final class HealthBodyMassChannelHandler {
    private let operations: (any HealthBodyMassLookupOperationsProtocol)?

    init(operations: (any HealthBodyMassLookupOperationsProtocol)?) {
        self.operations = operations
    }

    func lookup(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let once = HealthBodyMassResultOnce(result)
        let request: HealthBodyMassLookupRequest
        do {
            request = try HealthBodyMassChannelArguments.request(from: call.arguments)
        } catch {
            once.call(HealthBodyMassChannelResult.unavailable("invalidInput"))
            return
        }

        guard let operations else {
            once.call(HealthBodyMassChannelResult.unavailable("coreInitializationFailed"))
            return
        }

        operations.lookup(request) { lookupResult in
            once.call(HealthBodyMassChannelResult.encode(lookupResult))
        }
    }
}

private enum HealthBodyMassChannelArguments {
    private static let requiredKeys: Set<String> = ["clientRecordId", "measuredAt"]
    private static let largestExactlyRepresentableIntegerInDouble: Int64 =
        9_007_199_254_740_991

    static func request(from value: Any?) throws -> HealthBodyMassLookupRequest {
        guard let dictionary = value as? NSDictionary,
            dictionary.allKeys.allSatisfy({ $0 is String }),
            Set(dictionary.allKeys.compactMap { $0 as? String }) == requiredKeys,
            let clientRecordId = dictionary["clientRecordId"] as? String,
            !clientRecordId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw HealthBodyMassChannelInputError.invalidArguments
        }

        return HealthBodyMassLookupRequest(
            clientRecordId: clientRecordId.trimmingCharacters(in: .whitespacesAndNewlines),
            measuredAt: try exactDate(milliseconds: try requiredInt64(dictionary, key: "measuredAt"))
        )
    }

    private static func requiredInt64(
        _ dictionary: NSDictionary,
        key: String
    ) throws -> Int64 {
        guard let number = dictionary[key] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            throw HealthBodyMassChannelInputError.invalidArguments
        }

        switch String(cString: number.objCType) {
        case "c", "s", "i", "l", "q":
            return number.int64Value
        case "C", "S", "I", "L", "Q":
            let unsignedValue = number.uint64Value
            guard unsignedValue <= UInt64(Int64.max) else {
                throw HealthBodyMassChannelInputError.invalidArguments
            }
            return Int64(unsignedValue)
        default:
            throw HealthBodyMassChannelInputError.invalidArguments
        }
    }

    private static func exactDate(milliseconds: Int64) throws -> Date {
        guard milliseconds >= -largestExactlyRepresentableIntegerInDouble,
            milliseconds <= largestExactlyRepresentableIntegerInDouble
        else {
            throw HealthBodyMassChannelInputError.invalidArguments
        }
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        let recoveredMilliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        guard recoveredMilliseconds == Double(milliseconds) else {
            throw HealthBodyMassChannelInputError.invalidArguments
        }
        return date
    }
}

private enum HealthBodyMassChannelInputError: Error {
    case invalidArguments
}

private enum HealthBodyMassChannelResult {
    static func encode(_ result: HealthBodyMassLookupResult) -> [String: Any] {
        [
            "status": result.status.rawValue,
            "recordId": result.recordId ?? NSNull(),
            "platformCode": result.platformCode ?? NSNull(),
        ]
    }

    static func unavailable(_ platformCode: String) -> [String: Any] {
        encode(.unavailable(platformCode))
    }
}

private final class HealthBodyMassResultOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let result: FlutterResult

    init(_ result: @escaping FlutterResult) {
        self.result = result
    }

    func call(_ value: Any?) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        let boxedValue = HealthBodyMassUncheckedSendableValue(value)
        DispatchQueue.main.async { [self, boxedValue] in
            result(boxedValue.value)
        }
    }
}

private struct HealthBodyMassUncheckedSendableValue: @unchecked Sendable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }
}
