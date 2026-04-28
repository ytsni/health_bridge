import CoreLocation
import Foundation
import HealthKit

/// Reads `HKWorkoutRoute` samples and converts their route points into Flutter payloads.
public final class WorkoutRouteReadService: WorkoutRouteReading {
    /// Store abstraction used to execute workout route queries.
    private let store: HealthStoreProxying

    /// Creates a route reader backed by the supplied store proxy.
    public init(store: HealthStoreProxying) {
        self.store = store
    }

    /// Reads each route sample, expands its location points, and returns either
    /// one payload or a full list depending on the caller's mode.
    public func read(
        samples: [HKSample],
        includeManualEntries: Bool,
        singleResult: Bool,
        completion: @escaping (Result<Any?, Error>) -> Void
    ) {
        guard let routes = samples as? [HKWorkoutRoute], !routes.isEmpty else {
            completion(.success(singleResult ? nil : []))
            return
        }

        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "com.carp.health.workoutroute")
        var routePayloads = [[String: Any]]()
        var capturedError: Error?

        for route in routes where includeManualEntries || route.metadata?[HKMetadataKeyWasUserEntered] as? Bool != true {
            group.enter()
            var locations = [CLLocation]()
            let query = HKWorkoutRouteQuery(route: route) { [weak self] _, points, done, error in
                if let error {
                    syncQueue.async {
                        capturedError = capturedError ?? error
                        if done { group.leave() }
                    }
                    return
                }

                if let points {
                    locations.append(contentsOf: points)
                }

                guard done, let self else { return }
                syncQueue.async {
                    routePayloads.append(self.routePayload(for: route, locations: locations))
                    group.leave()
                }
            }
            store.execute(query)
        }

        group.notify(queue: .main) {
            if let capturedError {
                completion(.failure(capturedError))
            } else {
                completion(.success(singleResult ? routePayloads.first : routePayloads))
            }
        }
    }

    /// Builds the serialized payload for a single workout route sample.
    private func routePayload(for route: HKWorkoutRoute, locations: [CLLocation]) -> [String: Any] {
        let routePoints = locations.map(locationPayload)
        let startTime = routePoints.first?["timestamp"] as? Int ?? Int(route.startDate.timeIntervalSince1970 * 1000)
        let endTime = routePoints.last?["timestamp"] as? Int ?? Int(route.endDate.timeIntervalSince1970 * 1000)

        var metadata = HealthUtilities.sanitizeMetadata(route.metadata)
        metadata["route_point_count"] = routePoints.count

        var payload: [String: Any] = [
            "uuid": "\(route.uuid)",
            "route": routePoints,
            "date_from": startTime,
            "date_to": endTime,
            "source_id": route.sourceRevision.source.bundleIdentifier,
            "source_name": route.sourceRevision.source.name,
            "recording_method": SamplePayloadBuilder.recordingMethod(for: route.metadata),
            "metadata": metadata,
        ]

        if let workoutUUID = metadata["workout_uuid"] as? String {
            payload["workout_uuid"] = workoutUUID
        }

        return payload
    }

    /// Converts a `CLLocation` into the shape used by the Flutter side of the plugin.
    private func locationPayload(for location: CLLocation) -> [String: Any] {
        var payload: [String: Any?] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "timestamp": Int(location.timestamp.timeIntervalSince1970 * 1000),
        ]

        if location.horizontalAccuracy >= 0 { payload["horizontalAccuracy"] = location.horizontalAccuracy }
        if location.verticalAccuracy >= 0 {
            payload["verticalAccuracy"] = location.verticalAccuracy
            payload["altitude"] = location.altitude
        }
        if location.speed >= 0 { payload["speed"] = location.speed }
        if #available(iOS 13.4, *), location.speedAccuracy >= 0 { payload["speedAccuracy"] = location.speedAccuracy }
        if location.course >= 0, location.course <= 360 { payload["course"] = location.course }
        if #available(iOS 13.4, *), location.courseAccuracy >= 0 { payload["courseAccuracy"] = location.courseAccuracy }

        return payload.compactMapValues { $0 }
    }
}
