import CoreLocation
import Foundation

/// Typed payload that appends locations to an in-flight workout route.
struct WorkoutRouteInsertRequest {
    /// The identifier of the active route builder.
    let builderId: String

    /// The route locations to append.
    let locations: [CLLocation]
}

/// Typed payload that finishes an in-flight workout route.
struct WorkoutRouteFinishRequest {
    /// The identifier of the active route builder.
    let builderId: String

    /// The workout UUID associated with the finished route.
    let workoutUUID: UUID

    /// The workout UUID preserved as a string for payload metadata.
    let workoutUUIDString: String

    /// Optional metadata stored on the finished route.
    let metadata: [String: Any]?
}

/// Typed payload that discards an in-flight workout route.
struct WorkoutRouteDiscardRequest {
    /// The identifier of the active route builder.
    let builderId: String
}
