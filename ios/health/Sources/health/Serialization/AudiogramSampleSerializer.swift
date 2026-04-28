import HealthKit

/// Serializes `HKAudiogramSample` values.
struct AudiogramSampleSerializer: SampleSerializer {
    /// Returns whether `sample` is an audiogram sample.
    func canSerialize(_ sample: HKSample) -> Bool {
        sample is HKAudiogramSample
    }

    /// Returns the Flutter payload for `sample`.
    func serialize(_ sample: HKSample, context _: SampleSerializationContext) -> [String: Any]? {
        guard let sample = sample as? HKAudiogramSample else { return nil }

        var frequencies = [Double]()
        var leftEarSensitivities = [Double]()
        var rightEarSensitivities = [Double]()

        for point in sample.sensitivityPoints {
            frequencies.append(point.frequency.doubleValue(for: HKUnit.hertz()))
            leftEarSensitivities.append(
                point.leftEarSensitivity?.doubleValue(for: HKUnit.decibelHearingLevel()) ?? 0
            )
            rightEarSensitivities.append(
                point.rightEarSensitivity?.doubleValue(for: HKUnit.decibelHearingLevel()) ?? 0
            )
        }

        var payload = SamplePayloadBuilder.basePayload(for: sample)
        payload["frequencies"] = frequencies
        payload["leftEarSensitivities"] = leftEarSensitivities
        payload["rightEarSensitivities"] = rightEarSensitivities
        return payload
    }
}
