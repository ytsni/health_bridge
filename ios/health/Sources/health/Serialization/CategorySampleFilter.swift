/// Filters category sample values for aliased plugin keys.
enum CategorySampleFilter {
    /// Returns whether `sampleValue` belongs to `dataTypeKey`.
    static func includes(_ sampleValue: Int, for dataTypeKey: String) -> Bool {
        switch dataTypeKey {
        case HealthConstants.SLEEP_IN_BED:
            sampleValue == 0
        case HealthConstants.SLEEP_ASLEEP:
            sampleValue == 1
        case HealthConstants.SLEEP_AWAKE:
            sampleValue == 2
        case HealthConstants.SLEEP_LIGHT:
            sampleValue == 3
        case HealthConstants.SLEEP_DEEP:
            sampleValue == 4
        case HealthConstants.SLEEP_REM:
            sampleValue == 5
        case HealthConstants.HEADACHE_UNSPECIFIED:
            sampleValue == 0
        case HealthConstants.HEADACHE_NOT_PRESENT:
            sampleValue == 1
        case HealthConstants.HEADACHE_MILD:
            sampleValue == 2
        case HealthConstants.HEADACHE_MODERATE:
            sampleValue == 3
        case HealthConstants.HEADACHE_SEVERE:
            sampleValue == 4
        default:
            true
        }
    }
}
