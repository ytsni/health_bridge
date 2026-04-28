import HealthKit

/// Represents the effective authorization state derived from a HealthKit query.
public enum PermissionEvaluation: Equatable {
    case granted
    case denied
    case unknown
}

/// Encapsulates the plugin's coarse-grained permission interpretation rules.
public struct PermissionService {
    /// Creates a permission service.
    public init() {}

    /// Evaluates the authorization state for a HealthKit type and requested access mode.
    ///
    /// HealthKit does not expose a reliable read-status API, so read access resolves to `unknown`.
    public func evaluate(type: HKObjectType, access: HealthAuthorizationAccess, store: HealthStoreProxying) -> PermissionEvaluation {
        switch access {
        case .read, .readWrite:
            .unknown
        case .write:
            store.authorizationStatus(for: type) == .sharingAuthorized ? .granted : .denied
        }
    }
}
