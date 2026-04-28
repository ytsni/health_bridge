#if SWIFT_PACKAGE
import FlutterShim
#elseif canImport(Flutter)
import Flutter
#elseif canImport(FlutterShim)
import FlutterShim
#endif
import HealthKit

/// Main plugin class that coordinates health data operations.
public final class HealthPlugin: NSObject, FlutterPlugin {
    /// The HealthKit store shared across plugin services.
    let healthStore: HKHealthStore

    /// The immutable catalog shared across plugin services.
    let catalog: any HealthCatalogProviding

    /// Optional injected reader used by tests or alternate compositions.
    private let configuredHealthDataReader: (any HealthDataReading)?

    /// Optional injected writer used by tests or alternate compositions.
    private let configuredHealthDataWriter: (any HealthDataWriting)?

    /// Optional injected operations facade used by tests or alternate compositions.
    private let configuredHealthDataOperations: (any HealthDataOperating)?

    /// Lazily composes read-only HealthKit operations for Flutter method calls.
    private lazy var healthDataReader: any HealthDataReading = configuredHealthDataReader
        ?? HealthDataReader(healthStore: healthStore, catalog: catalog)

    /// Lazily composes write-only HealthKit operations for Flutter method calls.
    private lazy var healthDataWriter: any HealthDataWriting = configuredHealthDataWriter
        ?? HealthDataWriter(healthStore: healthStore, catalog: catalog)

    /// Lazily composes authorization and deletion operations for Flutter method calls.
    private lazy var healthDataOperations: any HealthDataOperating = configuredHealthDataOperations
        ?? HealthDataOperations(healthStore: healthStore, catalog: catalog)

    /// Centralizes Flutter method dispatch away from the plugin registration edge.
    private lazy var methodRouter: HealthMethodRouter = .init(
        healthDataReader: healthDataReader,
        healthDataWriter: healthDataWriter,
        healthDataOperations: healthDataOperations
    )

    /// Creates a plugin instance backed by a fresh `HKHealthStore` and the current catalog snapshot.
    public override convenience init() {
        self.init(healthStore: HKHealthStore(), catalog: HealthCatalog.current())
    }

    /// Creates a plugin with explicit collaborators for tests or alternate hosts.
    init(
        healthStore: HKHealthStore,
        catalog: any HealthCatalogProviding,
        healthDataReader: (any HealthDataReading)? = nil,
        healthDataWriter: (any HealthDataWriting)? = nil,
        healthDataOperations: (any HealthDataOperating)? = nil
    ) {
        self.healthStore = healthStore
        self.catalog = catalog
        configuredHealthDataReader = healthDataReader
        configuredHealthDataWriter = healthDataWriter
        configuredHealthDataOperations = healthDataOperations
        super.init()
    }

    /// Registers the plugin method channel with Flutter.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_health",
            binaryMessenger: registrar.messenger()
        )
        let instance = HealthPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    /// Forwards Flutter method calls to the router after plugin registration has been completed.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        methodRouter.handle(call, result: result)
    }
}
