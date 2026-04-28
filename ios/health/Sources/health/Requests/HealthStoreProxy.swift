import HealthKit

/// Minimal wrapper around `HKHealthStore` used by services that read, write, or
/// inspect authorization state.
public protocol HealthStoreProxying: AnyObject {
    /// Executes a HealthKit query.
    func execute(_ query: HKQuery)
    /// Requests HealthKit authorization for the supplied share and read types.
    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>,
        completion: @escaping (Bool, Error?) -> Void
    )
    /// Returns the current authorization status for a HealthKit object type.
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    /// Deletes the supplied objects from HealthKit.
    func delete(_ objects: [HKObject], completion: @escaping (Bool, Error?) -> Void)
    /// Reads the user's date of birth from HealthKit.
    func dateOfBirth() throws -> Date?
    /// Reads the user's biological sex from HealthKit.
    func biologicalSex() throws -> HKBiologicalSex
    /// Reads the user's blood type from HealthKit.
    func bloodType() throws -> HKBloodType
}

/// Live adapter that forwards requests to an `HKHealthStore`.
public final class LiveHealthStoreProxy: HealthStoreProxying {
    /// The live HealthKit store.
    private let store: HKHealthStore

    /// Creates a proxy backed by the supplied HealthKit store.
    public init(store: HKHealthStore) {
        self.store = store
    }

    /// Executes `query`.
    public func execute(_ query: HKQuery) {
        store.execute(query)
    }

    /// Requests HealthKit authorization for `typesToShare` and `typesToRead`.
    public func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        store.requestAuthorization(toShare: typesToShare, read: typesToRead, completion: completion)
    }

    /// Returns the authorization status for `type`.
    public func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        store.authorizationStatus(for: type)
    }

    /// Deletes `objects` from HealthKit.
    public func delete(_ objects: [HKObject], completion: @escaping (Bool, Error?) -> Void) {
        store.delete(objects, withCompletion: completion)
    }

    /// Returns the user's date of birth.
    public func dateOfBirth() throws -> Date? {
        try store.dateOfBirthComponents().date
    }

    /// Returns the user's biological sex.
    public func biologicalSex() throws -> HKBiologicalSex {
        try store.biologicalSex().biologicalSex
    }

    /// Returns the user's blood type.
    public func bloodType() throws -> HKBloodType {
        try store.bloodType().bloodType
    }
}
