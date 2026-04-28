import Foundation
import HealthKit

/// Reads characteristic values that are exposed through direct `HKHealthStore`
/// accessors instead of sample queries.
public final class CharacteristicReadService: CharacteristicReading {
    /// Store abstraction used to read characteristics.
    private let store: HealthStoreProxying

    /// Creates a characteristic reader backed by the supplied store proxy.
    public init(store: HealthStoreProxying) {
        self.store = store
    }

    /// Returns a payload for supported characteristic keys, or `nil` when the
    /// request should be handled by sample-based readers.
    public func read(for request: SampleReadRequest) -> Result<[[String: Any]]?, Error> {
        let value: Any?

        do {
            switch request.dataTypeKey {
            case HealthConstants.BIRTH_DATE:
                value = try store.dateOfBirth()?.timeIntervalSince1970
            case HealthConstants.GENDER:
                value = try store.biologicalSex().rawValue
            case HealthConstants.BLOOD_TYPE:
                value = try store.bloodType().rawValue
            default:
                return .success(nil)
            }
        } catch {
            return .failure(error)
        }

        return .success([[
            "value": value,
            "date_from": request.dateRange.map { Int($0.startDate.timeIntervalSince1970 * 1000) } ?? 0,
            "date_to": request.dateRange.map { Int($0.endDate.timeIntervalSince1970 * 1000) } ?? 0,
            "source_id": "com.apple.Health",
            "source_name": "Health",
            "recording_method": HealthConstants.RecordingMethod.manual.rawValue,
        ].compactMapValues { $0 }])
    }
}
