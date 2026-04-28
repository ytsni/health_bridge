/// Plugin keys and enum values shared across native HealthKit flows.
enum HealthConstants {
    /// Recording method values mirrored from the Dart plugin surface.
    enum RecordingMethod: Int {
        case unknown = 0
        case active = 1
        case automatic = 2
        case manual = 3
    }
}

/// Plugin error carrying a Flutter-facing message.
struct PluginError: Error {
    /// The message returned to Flutter.
    let message: String
}
