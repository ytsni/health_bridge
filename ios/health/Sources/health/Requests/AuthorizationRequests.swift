import Foundation

/// Access modes mirrored from the Flutter permission payload.
public enum HealthAuthorizationAccess: Int, Equatable {
    case read = 0
    case write = 1
    case readWrite = 2

    /// Falls back to read-write when the raw Dart value is missing or unknown.
    init(rawPermission value: Int) {
        self = HealthAuthorizationAccess(rawValue: value) ?? .readWrite
    }
}

/// A single permission request for one plugin data type key.
public struct PermissionRequest: Equatable {
    /// The plugin data type key.
    let dataTypeKey: String

    /// The requested access mode.
    let access: HealthAuthorizationAccess
}

/// Typed authorization payload decoded from `requestAuthorization` arguments.
public struct AuthorizationRequest: Equatable {
    /// The requested permissions keyed by plugin data type.
    let permissions: [PermissionRequest]

    /// Decodes paired `types` and `permissions` arrays from Flutter.
    public static func parse(arguments: NSDictionary?) throws -> AuthorizationRequest {
        guard let arguments,
              let types = arguments["types"] as? [String],
              let permissions = arguments["permissions"] as? [Int],
              types.count == permissions.count
        else {
            throw PluginError(message: "Invalid Arguments!")
        }

        return AuthorizationRequest(
            permissions: zip(types, permissions).map { PermissionRequest(
                dataTypeKey: $0.0,
                access: .init(rawPermission: $0.1)
            ) }
        )
    }
}

/// Shares the authorization request shape with permission status checks.
public typealias PermissionCheckRequest = AuthorizationRequest
