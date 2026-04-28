import HealthKit

/// In-memory store of active workout route builders.
final class WorkoutRouteSessionManager {
    /// Route builders keyed by generated session identifier.
    private var builders: [String: HKWorkoutRouteBuilder] = [:]

    /// Synchronization queue for builder access.
    private let queue = DispatchQueue(label: "com.carp.health.workoutRouteBuilders")

    /// Creates a route builder and returns its identifier.
    func start(healthStore: HKHealthStore) -> String {
        let identifier = UUID().uuidString
        let builder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        queue.sync {
            self.builders[identifier] = builder
        }
        return identifier
    }

    /// Returns the route builder identified by `identifier`.
    func builder(for identifier: String) -> HKWorkoutRouteBuilder? {
        var builder: HKWorkoutRouteBuilder?
        queue.sync {
            builder = builders[identifier]
        }
        return builder
    }

    /// Removes and returns the route builder identified by `identifier`.
    func removeBuilder(for identifier: String) -> HKWorkoutRouteBuilder? {
        var builder: HKWorkoutRouteBuilder?
        queue.sync {
            builder = builders.removeValue(forKey: identifier)
        }
        return builder
    }
}
