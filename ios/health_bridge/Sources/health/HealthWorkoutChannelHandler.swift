import CoreFoundation
import Flutter
import Foundation

#if canImport(HealthBridgeWorkoutCore)
    import HealthBridgeWorkoutCore
#endif

protocol HealthWorkoutOperationsProtocol: Sendable {
    func write(
        _ request: WorkoutWriteRequest,
        completion: @escaping @Sendable (WorkoutWriteResult) -> Void
    )

    func lookup(
        _ request: WorkoutLookupRequest,
        completion: @escaping @Sendable (WorkoutLookupResult) -> Void
    )

    func authorizationSnapshot(for requestedTypes: [String]) throws
        -> HealthAuthorizationSnapshot
}

extension HealthWorkoutOperations: HealthWorkoutOperationsProtocol {}

final class HealthWorkoutChannelHandler {
    private let operations: (any HealthWorkoutOperationsProtocol)?

    init(operations: (any HealthWorkoutOperationsProtocol)?) {
        self.operations = operations
    }

    func write(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let once = FlutterResultOnce(result)
        let energyExpected = WorkoutChannelArguments.hasRequestedEnergy(call.arguments)

        let request: WorkoutWriteRequest
        do {
            request = try WorkoutChannelArguments.writeRequest(from: call.arguments)
        } catch {
            once.call(
                WorkoutChannelResult.writeFailure(
                    status: .invalidInput,
                    energyExpected: energyExpected,
                    retryable: false,
                    platformCode: PlatformCode.invalidInput
                )
            )
            return
        }

        guard let operations else {
            once.call(
                WorkoutChannelResult.writeFailure(
                    status: .unavailable,
                    energyExpected: request.energyClientRecordId != nil,
                    retryable: true,
                    platformCode: PlatformCode.coreInitializationFailed
                )
            )
            return
        }

        operations.write(request) { writeResult in
            once.call(WorkoutChannelResult.encode(writeResult))
        }
    }

    func lookup(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let once = FlutterResultOnce(result)
        let energyExpected = WorkoutChannelArguments.hasRequestedEnergy(call.arguments)

        let request: WorkoutLookupRequest
        do {
            request = try WorkoutChannelArguments.lookupRequest(from: call.arguments)
        } catch {
            once.call(
                WorkoutChannelResult.lookupFailure(
                    energyExpected: energyExpected,
                    platformCode: PlatformCode.invalidInput
                )
            )
            return
        }

        guard let operations else {
            once.call(
                WorkoutChannelResult.lookupFailure(
                    energyExpected: request.energyClientRecordId != nil,
                    platformCode: PlatformCode.coreInitializationFailed
                )
            )
            return
        }

        operations.lookup(request) { lookupResult in
            once.call(WorkoutChannelResult.encode(lookupResult))
        }
    }

    func authorizationSnapshot(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let once = FlutterResultOnce(result)
        let requestedTypes: [String]
        do {
            requestedTypes = try WorkoutChannelArguments.authorizationTypes(
                from: call.arguments
            )
        } catch {
            once.call(
                FlutterError(
                    code: PlatformCode.invalidInput,
                    message: "Invalid authorization snapshot arguments",
                    details: nil
                )
            )
            return
        }

        guard let operations else {
            once.call(
                WorkoutChannelResult.authorizationFailure(
                    requestedTypes: requestedTypes,
                    platformCode: PlatformCode.coreInitializationFailed
                )
            )
            return
        }

        do {
            let snapshot = try operations.authorizationSnapshot(for: requestedTypes)
            guard WorkoutChannelResult.matches(snapshot, requestedTypes: requestedTypes) else {
                once.call(
                    WorkoutChannelResult.authorizationFailure(
                        requestedTypes: requestedTypes,
                        platformCode: PlatformCode.unexpectedFailure
                    )
                )
                return
            }
            once.call(WorkoutChannelResult.encode(snapshot))
        } catch {
            once.call(
                WorkoutChannelResult.authorizationFailure(
                    requestedTypes: requestedTypes,
                    platformCode: PlatformCode.unexpectedFailure
                )
            )
        }
    }
}

private final class FlutterResultOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let result: FlutterResult

    init(_ result: @escaping FlutterResult) {
        self.result = result
    }

    func call(_ value: Any?) {
        let shouldComplete = lock.withLock { () -> Bool in
            guard !completed else { return false }
            completed = true
            return true
        }
        guard shouldComplete else { return }

        let boxedValue = UncheckedSendableValue(value)
        DispatchQueue.main.async { [self, boxedValue] in
            result(boxedValue.value)
        }
    }
}

private struct UncheckedSendableValue: @unchecked Sendable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }
}

private enum WorkoutChannelInputError: Error {
    case invalidArguments
}

private enum WorkoutChannelArguments {
    private static let largestExactlyRepresentableIntegerInDouble: Int64 =
        9_007_199_254_740_991

    static func writeRequest(from arguments: Any?) throws -> WorkoutWriteRequest {
        let dictionary = try strictDictionary(arguments)
        guard
            let recordingProvenance = HealthRecordingProvenance(
                rawValue: try requiredString(dictionary, key: "recordingProvenance")
            ),
            let recordingDevice = HealthRecordingDevice(
                rawValue: try requiredString(dictionary, key: "recordingDevice")
            )
        else {
            throw WorkoutChannelInputError.invalidArguments
        }

        return try WorkoutWriteRequest(
            workoutClientRecordId: try requiredString(
                dictionary,
                key: "workoutClientRecordId"
            ),
            energyClientRecordId: try optionalString(
                dictionary,
                key: "energyClientRecordId"
            ),
            clientRecordVersion: try requiredInt(dictionary, key: "clientRecordVersion"),
            activityType: try requiredString(dictionary, key: "activityType"),
            startEpochMilliseconds: try requiredInt64(dictionary, key: "startTime"),
            endEpochMilliseconds: try requiredInt64(dictionary, key: "endTime"),
            startZoneOffsetSeconds: try requiredInt(
                dictionary,
                key: "startZoneOffsetSeconds"
            ),
            endZoneOffsetSeconds: try requiredInt(
                dictionary,
                key: "endZoneOffsetSeconds"
            ),
            activeEnergyKcal: try optionalDouble(dictionary, key: "activeEnergyKcal"),
            title: try requiredString(dictionary, key: "title"),
            recordingProvenance: recordingProvenance,
            recordingDevice: recordingDevice
        )
    }

    static func lookupRequest(from arguments: Any?) throws -> WorkoutLookupRequest {
        let dictionary = try strictDictionary(arguments)
        let startMilliseconds = try requiredInt64(dictionary, key: "startTime")
        let endMilliseconds = try requiredInt64(dictionary, key: "endTime")
        return try WorkoutLookupRequest(
            workoutClientRecordId: try requiredString(
                dictionary,
                key: "workoutClientRecordId"
            ),
            energyClientRecordId: try optionalString(
                dictionary,
                key: "energyClientRecordId"
            ),
            start: try exactDate(milliseconds: startMilliseconds),
            end: try exactDate(milliseconds: endMilliseconds)
        )
    }

    static func authorizationTypes(from arguments: Any?) throws -> [String] {
        let dictionary = try strictDictionary(arguments)
        guard let values = dictionary["types"] as? NSArray, values.count > 0 else {
            throw WorkoutChannelInputError.invalidArguments
        }

        var types: [String] = []
        types.reserveCapacity(values.count)
        for value in values {
            guard let type = value as? String,
                !type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw WorkoutChannelInputError.invalidArguments
            }
            types.append(type)
        }
        guard Set(types).count == types.count else {
            throw WorkoutChannelInputError.invalidArguments
        }
        return types
    }

    static func hasRequestedEnergy(_ arguments: Any?) -> Bool {
        guard let dictionary = arguments as? NSDictionary else { return false }
        return isPresent(dictionary["energyClientRecordId"])
            || isPresent(dictionary["activeEnergyKcal"])
    }

    private static func strictDictionary(_ value: Any?) throws -> NSDictionary {
        guard let dictionary = value as? NSDictionary,
            dictionary.allKeys.allSatisfy({ $0 is String })
        else {
            throw WorkoutChannelInputError.invalidArguments
        }
        return dictionary
    }

    private static func requiredString(
        _ dictionary: NSDictionary,
        key: String
    ) throws -> String {
        guard let value = dictionary[key] as? String else {
            throw WorkoutChannelInputError.invalidArguments
        }
        return value
    }

    private static func optionalString(
        _ dictionary: NSDictionary,
        key: String
    ) throws -> String? {
        guard let value = dictionary[key], !(value is NSNull) else { return nil }
        guard let string = value as? String else {
            throw WorkoutChannelInputError.invalidArguments
        }
        return string
    }

    private static func requiredInt(
        _ dictionary: NSDictionary,
        key: String
    ) throws -> Int {
        let value = try requiredInt64(dictionary, key: key)
        guard let exact = Int(exactly: value) else {
            throw WorkoutChannelInputError.invalidArguments
        }
        return exact
    }

    private static func requiredInt64(
        _ dictionary: NSDictionary,
        key: String
    ) throws -> Int64 {
        guard let number = dictionary[key] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            throw WorkoutChannelInputError.invalidArguments
        }

        switch String(cString: number.objCType) {
        case "c", "s", "i", "l", "q":
            return number.int64Value
        case "C", "S", "I", "L", "Q":
            let unsignedValue = number.uint64Value
            guard unsignedValue <= UInt64(Int64.max) else {
                throw WorkoutChannelInputError.invalidArguments
            }
            return Int64(unsignedValue)
        default:
            throw WorkoutChannelInputError.invalidArguments
        }
    }

    private static func optionalDouble(
        _ dictionary: NSDictionary,
        key: String
    ) throws -> Double? {
        guard let value = dictionary[key], !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            throw WorkoutChannelInputError.invalidArguments
        }
        return number.doubleValue
    }

    private static func exactDate(milliseconds: Int64) throws -> Date {
        guard milliseconds >= -largestExactlyRepresentableIntegerInDouble,
            milliseconds <= largestExactlyRepresentableIntegerInDouble
        else {
            throw WorkoutChannelInputError.invalidArguments
        }
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        let recoveredMilliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        guard recoveredMilliseconds == Double(milliseconds) else {
            throw WorkoutChannelInputError.invalidArguments
        }
        return date
    }

    private static func isPresent(_ value: Any?) -> Bool {
        value != nil && !(value is NSNull)
    }
}

private enum WorkoutChannelResult {
    static func encode(_ result: WorkoutWriteResult) -> [String: Any] {
        [
            "status": result.status.rawValue,
            "workoutRecordId": result.workoutRecordId ?? NSNull(),
            "energyRecordId": result.energyRecordId ?? NSNull(),
            "energyStatus": result.energyStatus.rawValue,
            "retryable": result.retryable,
            "submissionCertainty": result.submissionCertainty.rawValue,
            "platformCode": result.platformCode ?? NSNull(),
        ]
    }

    static func encode(_ result: WorkoutLookupResult) -> [String: Any] {
        [
            "workout": encode(result.workout),
            "energy": encode(result.energy),
            "derivedStatus": result.derivedStatus.rawValue,
            "platformCode": result.platformCode ?? NSNull(),
        ]
    }

    static func encode(_ snapshot: HealthAuthorizationSnapshot) -> [String: Any] {
        [
            "available": snapshot.available,
            "types": snapshot.types.map { authorization in
                [
                    "type": authorization.type,
                    "read": authorization.read.rawValue,
                    "write": authorization.write.rawValue,
                ]
            },
            "platformCode": snapshot.platformCode ?? NSNull(),
        ]
    }

    static func writeFailure(
        status: WorkoutWriteStatus,
        energyExpected: Bool,
        retryable: Bool,
        platformCode: String
    ) -> [String: Any] {
        [
            "status": status.rawValue,
            "workoutRecordId": NSNull(),
            "energyRecordId": NSNull(),
            "energyStatus": energyExpected
                ? EnergyWriteStatus.notSubmitted.rawValue
                : EnergyWriteStatus.notExpected.rawValue,
            "retryable": retryable,
            "submissionCertainty": SubmissionCertainty.notSubmitted.rawValue,
            "platformCode": platformCode,
        ]
    }

    static func lookupFailure(
        energyExpected: Bool,
        platformCode: String
    ) -> [String: Any] {
        [
            "workout": component(status: .unavailable),
            "energy": component(status: energyExpected ? .unavailable : .notExpected),
            "derivedStatus": WorkoutLookupStatus.unavailable.rawValue,
            "platformCode": platformCode,
        ]
    }

    static func authorizationFailure(
        requestedTypes: [String],
        platformCode: String
    ) -> [String: Any] {
        [
            "available": false,
            "types": requestedTypes.sorted().map { type in
                [
                    "type": type,
                    "read": AuthorizationState.unavailable.rawValue,
                    "write": AuthorizationState.unavailable.rawValue,
                ]
            },
            "platformCode": platformCode,
        ]
    }

    static func matches(
        _ snapshot: HealthAuthorizationSnapshot,
        requestedTypes: [String]
    ) -> Bool {
        snapshot.types.count == requestedTypes.count
            && Set(snapshot.types.map(\.type)) == Set(requestedTypes)
    }

    private static func encode(_ result: RecordLookup) -> [String: Any] {
        component(status: result.status, recordId: result.recordId)
    }

    private static func component(
        status: RecordLookupStatus,
        recordId: String? = nil
    ) -> [String: Any] {
        [
            "status": status.rawValue,
            "recordId": recordId ?? NSNull(),
        ]
    }
}

private enum PlatformCode {
    static let invalidInput = "invalidInput"
    static let coreInitializationFailed = "coreInitializationFailed"
    static let unexpectedFailure = "unexpectedFailure"
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
