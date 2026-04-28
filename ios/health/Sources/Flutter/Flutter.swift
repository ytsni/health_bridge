import Foundation

/// Marker protocol for Flutter binary messengers.
public protocol FlutterBinaryMessenger {}

/// Completion closure used by Flutter method handlers.
public typealias FlutterResult = (Any?) -> Void

/// Flutter plugin interface used for registration.
public protocol FlutterPlugin: AnyObject {
    /// Registers `self` with `registrar`.
    static func register(with registrar: FlutterPluginRegistrar)
}

/// Flutter registrar interface used by plugin setup code.
public protocol FlutterPluginRegistrar {
    /// Returns the messenger used by registered channels.
    func messenger() -> FlutterBinaryMessenger

    /// Registers `delegate` to handle calls received on `channel`.
    func addMethodCallDelegate(_ delegate: AnyObject, channel: FlutterMethodChannel)
}

/// Flutter method channel identified by name and messenger.
public final class FlutterMethodChannel {
    /// The channel name.
    public let name: String

    /// The messenger that carries channel traffic.
    public let binaryMessenger: FlutterBinaryMessenger

    /// Creates a method channel backed by `binaryMessenger`.
    public init(name: String, binaryMessenger: FlutterBinaryMessenger) {
        self.name = name
        self.binaryMessenger = binaryMessenger
    }
}

/// Flutter method call identified by name and arguments.
public final class FlutterMethodCall {
    /// The invoked method name.
    public let method: String

    /// The raw method arguments.
    public let arguments: Any?

    /// Creates a method call carrying `method` and `arguments`.
    public init(method: String, arguments: Any?) {
        self.method = method
        self.arguments = arguments
    }
}

/// Flutter error payload returned through a method channel.
public final class FlutterError: NSObject, Error {
    /// The Flutter error code.
    public let code: String

    /// The Flutter error message.
    public let message: String?

    /// The Flutter error details payload.
    public let details: Any?

    /// Creates a Flutter error carrying `code`, `message`, and `details`.
    public init(code: String, message: String?, details: Any?) {
        self.code = code
        self.message = message
        self.details = details
    }
}

/// Sentinel returned when a Flutter method has no native implementation.
public let FlutterMethodNotImplemented = NSObject()
