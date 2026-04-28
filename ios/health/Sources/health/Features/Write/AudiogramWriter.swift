#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Writes audiogram samples.
final class AudiogramWriter {
    /// Shared write dependencies and registries.
    private let context: HealthWriteContext

    /// Creates an audiogram writer backed by `context`.
    init(context: HealthWriteContext) {
        self.context = context
    }

    /// Writes the audiogram described by `request`.
    func write(_ request: AudiogramWriteRequest, result: @escaping FlutterResult) throws {
        let sensitivityPoints = try zip(
            request.frequencies,
            zip(request.leftEarSensitivities, request.rightEarSensitivities)
        ).map { frequencyValue, ears in
            try HKAudiogramSensitivityPoint(
                frequency: HKQuantity(unit: .hertz(), doubleValue: frequencyValue),
                leftEarSensitivity: HKQuantity(unit: .decibelHearingLevel(), doubleValue: ears.0),
                rightEarSensitivity: HKQuantity(unit: .decibelHearingLevel(), doubleValue: ears.1)
            )
        }

        let metadata = buildMetadata(from: request.metadata)
        let sample = HKAudiogramSample(
            sensitivityPoints: sensitivityPoints,
            start: request.startDate,
            end: request.endDate,
            metadata: metadata
        )

        HealthWriteResultHandler.save(
            sample,
            in: context.healthStore,
            failureCode: "WRITE_AUDIOGRAM_FAILED",
            errorMessage: { "Error saving audiogram sample: \($0.localizedDescription)" },
            failureMessage: "HealthKit save returned false for audiogram sample.",
            successPayload: .bool,
            result: result
        )
    }

    /// Returns HealthKit metadata derived from Flutter audiogram metadata.
    private func buildMetadata(from metadata: [String: Any]?) -> [String: Any]? {
        guard let metadata else { return nil }
        guard
            let deviceName = metadata["HKDeviceName"] as? String,
            let externalUUID = metadata["HKExternalUUID"] as? String
        else {
            return nil
        }

        return [
            HKMetadataKeyDeviceName: deviceName,
            HKMetadataKeyExternalUUID: externalUUID,
        ]
    }
}
