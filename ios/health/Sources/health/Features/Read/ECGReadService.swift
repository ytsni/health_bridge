import Foundation
import HealthKit

/// Reads electrocardiogram samples and expands their measurements.
public final class ECGReadService: ECGReading {
    /// Store abstraction used to execute ECG queries.
    private let store: HealthStoreProxying

    /// Creates an ECG reader backed by `store`.
    public init(store: HealthStoreProxying) {
        self.store = store
    }

    /// Reads ECG payloads from `samples`.
    public func read(
        samples: [HKSample],
        singleResult: Bool,
        completion: @escaping (Result<Any?, Error>) -> Void
    ) {
        guard #available(iOS 14.0, *) else {
            completion(.success(singleResult ? nil : []))
            return
        }
        guard let electrocardiograms = samples as? [HKElectrocardiogram], !electrocardiograms.isEmpty else {
            completion(.success(singleResult ? nil : []))
            return
        }

        fetchMeasurements(for: electrocardiograms) { dictionaries in
            completion(.success(singleResult ? dictionaries.first : dictionaries))
        }
    }

    @available(iOS 14.0, *)
    /// Reads voltage measurements for each electrocardiogram in `samples`.
    private func fetchMeasurements(
        for samples: [HKElectrocardiogram],
        completion: @escaping ([[String: Any]]) -> Void
    ) {
        let group = DispatchGroup()
        let lock = NSLock()
        var payloads = [[String: Any]]()

        for sample in samples {
            group.enter()
            var voltageValues = [[String: Any]]()

            let query = HKElectrocardiogramQuery(sample) { _, result in
                switch result {
                case let .measurement(measurement):
                    if let voltage = measurement.quantity(for: .appleWatchSimilarToLeadI)?
                        .doubleValue(for: HKUnit.volt())
                    {
                        voltageValues.append([
                            "voltage": voltage,
                            "timeSinceSampleStart": measurement.timeSinceSampleStart,
                        ])
                    }
                case .done:
                    lock.lock()
                    payloads.append(self.payload(for: sample, voltageValues: voltageValues))
                    lock.unlock()
                    group.leave()
                case .error:
                    group.leave()
                @unknown default:
                    group.leave()
                }
            }

            store.execute(query)
        }

        group.notify(queue: .main) {
            completion(payloads)
        }
    }

    @available(iOS 14.0, *)
    /// Returns the serialized payload for `sample`.
    private func payload(for sample: HKElectrocardiogram, voltageValues: [[String: Any]]) -> [String: Any] {
        [
            "uuid": "\(sample.uuid)",
            "voltageValues": voltageValues,
            "averageHeartRate": sample.averageHeartRate?.doubleValue(
                for: HKUnit.count().unitDivided(by: HKUnit.minute())
            ) as Any,
            "samplingFrequency": sample.samplingFrequency?.doubleValue(for: HKUnit.hertz()) as Any,
            "classification": sample.classification.rawValue,
            "date_from": Int(sample.startDate.timeIntervalSince1970 * 1000),
            "date_to": Int(sample.endDate.timeIntervalSince1970 * 1000),
            "source_id": sample.sourceRevision.source.bundleIdentifier,
            "source_name": sample.sourceRevision.source.name,
        ]
    }
}
