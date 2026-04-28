#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Writes workout route sessions and route samples.
final class WorkoutRouteWriter {
    /// Shared write dependencies and registries.
    private let context: HealthWriteContext

    /// In-memory manager for active route builders.
    private let sessionManager: WorkoutRouteSessionManager

    /// Creates a workout route writer backed by `context`.
    init(context: HealthWriteContext, sessionManager: WorkoutRouteSessionManager) {
        self.context = context
        self.sessionManager = sessionManager
    }

    /// Starts a route builder session and returns its identifier.
    func start(result: @escaping FlutterResult) {
        guard ensureAvailability(result: result) else { return }
        result(sessionManager.start(healthStore: context.healthStore))
    }

    /// Inserts route points into the builder identified by `request`.
    func insert(_ request: WorkoutRouteInsertRequest, result: @escaping FlutterResult) {
        guard ensureAvailability(result: result) else { return }
        guard let builder = sessionManager.builder(for: request.builderId) else {
            result(routeError(message: "No active workout route builder for identifier \(request.builderId)"))
            return
        }
        guard !request.locations.isEmpty else {
            result(
                HealthWriteResultHandler.flutterError(
                    code: "ARGUMENT_ERROR",
                    message: "Locations array cannot be empty for route insertion"
                )
            )
            return
        }

        builder.insertRouteData(request.locations) { success, error in
            DispatchQueue.main.async {
                if let error {
                    result(self.routeError(message: "Error inserting workout route data: \(error.localizedDescription)"))
                } else {
                    result(success)
                }
            }
        }
    }

    /// Finishes the route builder identified by `request`.
    func finish(_ request: WorkoutRouteFinishRequest, result: @escaping FlutterResult) {
        guard ensureAvailability(result: result) else { return }
        guard let builder = sessionManager.builder(for: request.builderId) else {
            result(routeError(message: "No active workout route builder for identifier \(request.builderId)"))
            return
        }

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: HKQuery.predicateForObject(with: request.workoutUUID),
            limit: 1,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    result(self.routeError(message: "Error fetching workout for route: \(error.localizedDescription)"))
                }
                return
            }

            guard let workout = samples?.first as? HKWorkout else {
                DispatchQueue.main.async {
                    result(self.routeError(message: "Workout with UUID \(request.workoutUUIDString) not found"))
                }
                return
            }

            var metadata = request.metadata ?? [:]
            metadata["workout_uuid"] = request.workoutUUIDString

            builder.finishRoute(with: workout, metadata: metadata) { route, error in
                DispatchQueue.main.async {
                    _ = self.sessionManager.removeBuilder(for: request.builderId)
                    if let error {
                        result(self.routeError(message: "Error finishing workout route: \(error.localizedDescription)"))
                    } else if let route {
                        result([
                            "uuid": route.uuid.uuidString,
                            "startDate": Int(route.startDate.timeIntervalSince1970 * 1000),
                            "endDate": Int(route.endDate.timeIntervalSince1970 * 1000),
                        ])
                    } else {
                        result(self.routeError(message: "Workout route builder returned no route"))
                    }
                }
            }
        }

        context.healthStore.execute(query)
    }

    /// Discards the route builder identified by `request`.
    func discard(_ request: WorkoutRouteDiscardRequest, result: @escaping FlutterResult) {
        guard ensureAvailability(result: result) else { return }
        guard let builder = sessionManager.removeBuilder(for: request.builderId) else {
            result(false)
            return
        }
        builder.discard()
        result(true)
    }

    /// Returns whether workout routes are available on the current OS version.
    private func ensureAvailability(result: @escaping FlutterResult) -> Bool {
        guard #available(iOS 11.0, *) else {
            result(
                HealthWriteResultHandler.flutterError(
                    code: "UNSUPPORTED_FEATURE",
                    message: "Workout routes are only available on iOS 11.0 and above."
                )
            )
            return false
        }
        return true
    }

    /// Returns a route-specific Flutter error carrying `message`.
    private func routeError(message: String) -> FlutterError {
        HealthWriteResultHandler.flutterError(code: "ROUTE_ERROR", message: message)
    }
}
