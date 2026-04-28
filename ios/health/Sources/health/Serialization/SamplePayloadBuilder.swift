import HealthKit

/// Shared helpers for building Flutter sample payload dictionaries.
enum SamplePayloadBuilder {
    /// Returns the base payload shared by serialized samples.
    static func basePayload(for sample: HKSample) -> [String: Any] {
        [
            "uuid": "\(sample.uuid)",
            "date_from": Int(sample.startDate.timeIntervalSince1970 * 1000),
            "date_to": Int(sample.endDate.timeIntervalSince1970 * 1000),
            "source_id": sample.sourceRevision.source.bundleIdentifier,
            "source_name": sample.sourceRevision.source.name,
            "recording_method": recordingMethod(for: sample.metadata),
        ]
    }

    /// Returns the plugin recording method derived from `metadata`.
    static func recordingMethod(for metadata: [String: Any]?) -> Int {
        (metadata?[HKMetadataKeyWasUserEntered] as? Bool == true)
            ? HealthConstants.RecordingMethod.manual.rawValue
            : HealthConstants.RecordingMethod.automatic.rawValue
    }
}
