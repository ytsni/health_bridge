import Foundation

public final class HealthWorkoutOperations: @unchecked Sendable {
    private let store: HealthWorkoutStore
    private let metadataFactory: HealthWorkoutMetadataFactory
    private let invariantLookupFailureWithEnergy: WorkoutLookupResult
    private let invariantLookupFailureWithoutEnergy: WorkoutLookupResult
    private let invariantFailureWithEnergy: WorkoutWriteResult
    private let invariantFailureWithoutEnergy: WorkoutWriteResult

    public convenience init(store: HealthWorkoutStore) throws {
        try self.init(
            store: store,
            metadataFactory: { clientRecordID, clientRecordVersion, provenance in
                try HealthWorkoutMetadata.make(
                    clientRecordId: clientRecordID,
                    clientRecordVersion: clientRecordVersion,
                    provenance: provenance
                )
            }
        )
    }

    init(
        store: HealthWorkoutStore,
        metadataFactory: @escaping HealthWorkoutMetadataFactory
    ) throws {
        self.store = store
        self.metadataFactory = metadataFactory
        invariantLookupFailureWithEnergy = try WorkoutLookupResult(
            workout: RecordLookup(status: .unavailable),
            energy: RecordLookup(status: .unavailable),
            derivedStatus: .unavailable,
            platformCode: PlatformCode.internalResultValidationFailed.rawValue
        )
        invariantLookupFailureWithoutEnergy = try WorkoutLookupResult(
            workout: RecordLookup(status: .unavailable),
            energy: RecordLookup(status: .notExpected),
            derivedStatus: .unavailable,
            platformCode: PlatformCode.internalResultValidationFailed.rawValue
        )
        invariantFailureWithEnergy = try WorkoutWriteResult(
            status: .unavailable,
            workoutRecordId: nil,
            energyRecordId: nil,
            energyStatus: .notSubmitted,
            retryable: true,
            submissionCertainty: .notSubmitted,
            platformCode: PlatformCode.internalResultValidationFailed.rawValue
        )
        invariantFailureWithoutEnergy = try WorkoutWriteResult(
            status: .unavailable,
            workoutRecordId: nil,
            energyRecordId: nil,
            energyStatus: .notExpected,
            retryable: true,
            submissionCertainty: .notSubmitted,
            platformCode: PlatformCode.internalResultValidationFailed.rawValue
        )
    }

    public func write(
        _ request: WorkoutWriteRequest,
        completion: @escaping @Sendable (WorkoutWriteResult) -> Void
    ) {
        let gate = WriteCompletionGate(completion: completion)
        let energyExpected = request.energyClientRecordId != nil

        if energyExpected,
            Self.isEnergyIntervalTooShort(
                startEpochMilliseconds: request.startEpochMilliseconds,
                endEpochMilliseconds: request.endEpochMilliseconds
            )
        {
            complete(
                gate,
                energyExpected: true,
                status: .invalidInput,
                energyStatus: .notSubmitted,
                retryable: false,
                certainty: .notSubmitted,
                code: .energyIntervalTooShort
            )
            return
        }

        guard
            Self.hasRepresentableHealthKitDates(
                request,
                energyExpected: energyExpected
            )
        else {
            complete(
                gate,
                energyExpected: energyExpected,
                status: .invalidInput,
                energyStatus: energyExpected ? .notSubmitted : .notExpected,
                retryable: false,
                certainty: .notSubmitted,
                code: .healthKitDateIntervalUnrepresentable
            )
            return
        }

        let lookupRequest: WorkoutLookupRequest
        do {
            lookupRequest = try WorkoutLookupRequest(
                workoutClientRecordId: request.workoutClientRecordId,
                energyClientRecordId: request.energyClientRecordId,
                start: request.start,
                end: request.end
            )
        } catch {
            complete(
                gate,
                energyExpected: energyExpected,
                status: .invalidInput,
                energyStatus: energyExpected ? .notSubmitted : .notExpected,
                retryable: false,
                certainty: .notSubmitted,
                code: .healthKitDateIntervalUnrepresentable
            )
            return
        }

        lookup(lookupRequest) { [self] result in
            handleWritePreflight(result, request: request, gate: gate)
        }
    }

    public func lookup(
        _ request: WorkoutLookupRequest,
        completion: @escaping @Sendable (WorkoutLookupResult) -> Void
    ) {
        let energyExpected = request.energyClientRecordId != nil
        let gate = LookupCompletionGate(completion: completion)

        lookupComponent(
            .workout,
            clientRecordID: request.workoutClientRecordId,
            start: request.start,
            end: request.end,
            gate: gate
        ) { [self] workout in
            guard let energyClientRecordID = request.energyClientRecordId else {
                completeLookup(
                    gate,
                    workout: workout,
                    energy: .notExpected,
                    energyExpected: false
                )
                return
            }

            lookupComponent(
                .activeEnergy,
                clientRecordID: energyClientRecordID,
                start: request.start,
                end: request.end,
                gate: gate
            ) { [self] energy in
                completeLookup(
                    gate,
                    workout: workout,
                    energy: energy,
                    energyExpected: energyExpected
                )
            }
        }
    }

    public func authorizationSnapshot(
        for requestedTypes: [String]
    ) throws -> HealthAuthorizationSnapshot {
        guard store.isHealthDataAvailable else {
            return try HealthAuthorizationSnapshot(
                available: false,
                types: try requestedTypes.map {
                    try HealthTypeAuthorization(
                        type: $0,
                        read: .unavailable,
                        write: .unavailable
                    )
                },
                platformCode: PlatformCode.healthDataUnavailable.rawValue
            )
        }

        let types = try requestedTypes.map { type -> HealthTypeAuthorization in
            guard let writeAuthorization = store.writeAuthorization(for: type) else {
                return try HealthTypeAuthorization(
                    type: type,
                    read: .unsupported,
                    write: .unsupported
                )
            }
            return try HealthTypeAuthorization(
                type: type,
                read: .requestedOrUnknown,
                write: Self.authorizationState(writeAuthorization)
            )
        }
        return try HealthAuthorizationSnapshot(
            available: true,
            types: types
        )
    }

    private func handleWritePreflight(
        _ result: WorkoutLookupResult,
        request: WorkoutWriteRequest,
        gate: WriteCompletionGate
    ) {
        let energyExpected = request.energyClientRecordId != nil
        switch result.derivedStatus {
        case .present:
            complete(
                gate,
                energyExpected: true,
                status: .alreadyPresent,
                workoutRecordID: result.workout.recordId,
                energyRecordID: result.energy.recordId,
                energyStatus: .alreadyPresent,
                retryable: false,
                certainty: .submitted
            )
        case .workoutOnly:
            complete(
                gate,
                energyExpected: energyExpected,
                status: .alreadyPresent,
                workoutRecordID: result.workout.recordId,
                energyStatus: energyExpected ? .absent : .notExpected,
                retryable: false,
                certainty: .submitted
            )
        case .absent:
            writeAbsentRequest(request, gate: gate)
        case .unavailable:
            complete(
                gate,
                energyExpected: energyExpected,
                status: .unavailable,
                energyStatus: energyExpected ? .notSubmitted : .notExpected,
                retryable: true,
                certainty: .notSubmitted,
                code: result.platformCode.flatMap(PlatformCode.init(rawValue:))
                    ?? .healthKitLookupFailed
            )
        case .inconsistent:
            complete(
                gate,
                energyExpected: true,
                status: .inconsistentNativeState,
                energyRecordID: result.energy.recordId,
                energyStatus: .alreadyPresent,
                retryable: false,
                certainty: .submitted
            )
        }
    }

    private func writeAbsentRequest(
        _ request: WorkoutWriteRequest,
        gate: WriteCompletionGate
    ) {
        let energyExpected = request.energyClientRecordId != nil

        guard store.writeAuthorization(for: .workout) == .authorized else {
            completeWorkoutPermissionBlock(gate, energyExpected: energyExpected)
            return
        }

        let includeEnergy =
            energyExpected
            && store.writeAuthorization(for: .activeEnergy) == .authorized

        let workoutMetadata: MetadataPayload
        let energyMetadata: MetadataPayload?
        do {
            workoutMetadata = MetadataPayload(
                try metadataFactory(
                    request.workoutClientRecordId,
                    request.clientRecordVersion,
                    request.recordingProvenance
                )
            )
            if includeEnergy, let energyClientRecordId = request.energyClientRecordId {
                energyMetadata = MetadataPayload(
                    try metadataFactory(
                        energyClientRecordId,
                        request.clientRecordVersion,
                        request.recordingProvenance
                    )
                )
            } else {
                energyMetadata = nil
            }
        } catch {
            complete(
                gate,
                energyExpected: energyExpected,
                status: .invalidInput,
                energyStatus: energyExpected ? .notSubmitted : .notExpected,
                retryable: false,
                certainty: .notSubmitted,
                code: .invalidMetadata
            )
            return
        }

        attempt(
            request,
            includeEnergy: includeEnergy,
            isFallback: false,
            workoutMetadata: workoutMetadata,
            energyMetadata: energyMetadata,
            gate: gate
        )
    }

    private func lookupComponent(
        _ component: WorkoutComponent,
        clientRecordID: String,
        start: Date,
        end: Date,
        gate: LookupCompletionGate,
        completion: @escaping @Sendable (ComponentLookupOutcome) -> Void
    ) {
        guard let token = gate.beginStage() else { return }
        store.lookup(
            component: component,
            clientRecordId: clientRecordID,
            start: start,
            end: end
        ) { result in
            guard gate.accept(token) else { return }
            completion(Self.componentOutcome(result, clientRecordID: clientRecordID))
        }
    }

    private func completeLookup(
        _ gate: LookupCompletionGate,
        workout: ComponentLookupOutcome,
        energy: ComponentLookupOutcome,
        energyExpected: Bool
    ) {
        let result: WorkoutLookupResult
        do {
            let workoutLookup = try RecordLookup(
                status: workout.status,
                recordId: workout.recordID
            )
            let energyLookup = try RecordLookup(
                status: energy.status,
                recordId: energy.recordID
            )
            result = try WorkoutLookupResult(
                workout: workoutLookup,
                energy: energyLookup,
                derivedStatus: Self.derivedLookupStatus(
                    workout: workout.status,
                    energy: energy.status
                ),
                platformCode: workout.code?.rawValue ?? energy.code?.rawValue
            )
        } catch {
            result =
                energyExpected
                ? invariantLookupFailureWithEnergy
                : invariantLookupFailureWithoutEnergy
        }
        gate.complete(result)
    }

    private static func componentOutcome(
        _ result: Result<[StoredRecordIdentity], HealthWorkoutLookupError>,
        clientRecordID: String
    ) -> ComponentLookupOutcome {
        switch result {
        case .success(let identities):
            let exactMatches = identities.filter {
                $0.isFromCurrentSource
                    && $0.syncIdentifier == clientRecordID
                    && $0.externalIdentifier == clientRecordID
            }
            switch exactMatches.count {
            case 0:
                return .absent
            case 1:
                return .present(exactMatches[0].recordID.uuidString)
            default:
                return .unavailable(.multipleMatchingRecords)
            }
        case .failure(let error):
            return .unavailable(platformCode(for: error))
        }
    }

    private static func platformCode(
        for error: HealthWorkoutLookupError
    ) -> PlatformCode {
        switch error {
        case .healthDataUnavailable:
            return .healthDataUnavailable
        case .typeUnavailable:
            return .healthKitTypeUnavailable
        case .protectedDataUnavailable:
            return .healthKitProtectedDataUnavailable
        case .queryFailed:
            return .healthKitLookupFailed
        }
    }

    private static func derivedLookupStatus(
        workout: RecordLookupStatus,
        energy: RecordLookupStatus
    ) -> WorkoutLookupStatus {
        if workout == .unavailable || energy == .unavailable {
            return .unavailable
        }
        return switch (workout, energy) {
        case (.absent, .present):
            .inconsistent
        case (.absent, .absent), (.absent, .notExpected):
            .absent
        case (.present, .present):
            .present
        case (.present, .absent), (.present, .notExpected):
            .workoutOnly
        case (.notExpected, _), (_, .unavailable), (.unavailable, _):
            .unavailable
        }
    }

    private static func authorizationState(
        _ authorization: WriteAuthorization
    ) -> AuthorizationState {
        switch authorization {
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        }
    }

    private func attempt(
        _ request: WorkoutWriteRequest,
        includeEnergy: Bool,
        isFallback: Bool,
        workoutMetadata: MetadataPayload,
        energyMetadata: MetadataPayload?,
        gate: WriteCompletionGate
    ) {
        let energyExpected = request.energyClientRecordId != nil
        let builder: HealthWorkoutBuilder
        do {
            builder = try store.makeBuilder(for: request)
        } catch let error as HealthWorkoutStoreError {
            complete(
                gate,
                energyExpected: energyExpected,
                status: .unavailable,
                energyStatus: energyExpected ? .notSubmitted : .notExpected,
                retryable: true,
                certainty: .notSubmitted,
                code: platformCode(for: error)
            )
            return
        } catch {
            complete(
                gate,
                energyExpected: energyExpected,
                status: .unavailable,
                energyStatus: energyExpected ? .notSubmitted : .notExpected,
                retryable: true,
                certainty: .notSubmitted,
                code: .builderUnavailable
            )
            return
        }

        guard let token = gate.beginStage() else { return }
        builder.begin(at: request.start) { [self] success, error in
            guard gate.accept(token) else { return }
            guard success, error == nil else {
                builder.discard()
                if Self.isWorkoutAuthorizationFailure(error) {
                    completeWorkoutPermissionBlock(
                        gate,
                        energyExpected: energyExpected
                    )
                } else {
                    completeTransientFailure(
                        gate,
                        energyExpected: energyExpected,
                        code: .beginCollectionFailed
                    )
                }
                return
            }
            addWorkoutMetadata(
                request,
                builder: builder,
                includeEnergy: includeEnergy,
                isFallback: isFallback,
                workoutMetadata: workoutMetadata,
                energyMetadata: energyMetadata,
                gate: gate
            )
        }
    }

    private func addWorkoutMetadata(
        _ request: WorkoutWriteRequest,
        builder: HealthWorkoutBuilder,
        includeEnergy: Bool,
        isFallback: Bool,
        workoutMetadata: MetadataPayload,
        energyMetadata: MetadataPayload?,
        gate: WriteCompletionGate
    ) {
        let energyExpected = request.energyClientRecordId != nil
        guard let token = gate.beginStage() else { return }
        builder.addWorkoutMetadata(workoutMetadata.values) { [self] success, error in
            guard gate.accept(token) else { return }
            guard success, error == nil else {
                builder.discard()
                if Self.isWorkoutAuthorizationFailure(error) {
                    completeWorkoutPermissionBlock(
                        gate,
                        energyExpected: energyExpected
                    )
                } else {
                    completeTransientFailure(
                        gate,
                        energyExpected: energyExpected,
                        code: .workoutMetadataFailed
                    )
                }
                return
            }

            if includeEnergy {
                guard store.writeAuthorization(for: .activeEnergy) == .authorized else {
                    fallbackToWorkoutOnly(
                        request,
                        failedBuilder: builder,
                        isFallback: isFallback,
                        workoutMetadata: workoutMetadata,
                        gate: gate
                    )
                    return
                }
                addEnergy(
                    request,
                    builder: builder,
                    isFallback: isFallback,
                    workoutMetadata: workoutMetadata,
                    energyMetadata: energyMetadata,
                    gate: gate
                )
            } else {
                endCollection(
                    request,
                    builder: builder,
                    includedEnergy: false,
                    sampleAccepted: false,
                    gate: gate
                )
            }
        }
    }

    private func addEnergy(
        _ request: WorkoutWriteRequest,
        builder: HealthWorkoutBuilder,
        isFallback: Bool,
        workoutMetadata: MetadataPayload,
        energyMetadata: MetadataPayload?,
        gate: WriteCompletionGate
    ) {
        guard
            let kilocalories = request.activeEnergyKcal,
            let energyMetadata
        else {
            builder.discard()
            complete(
                gate,
                energyExpected: true,
                status: .invalidInput,
                energyStatus: .notSubmitted,
                retryable: false,
                certainty: .notSubmitted,
                code: .invalidMetadata
            )
            return
        }

        guard let token = gate.beginStage() else { return }
        builder.addEnergy(
            kilocalories: kilocalories,
            start: request.start.addingTimeInterval(Self.energyStartOffset),
            end: request.end,
            metadata: energyMetadata.values
        ) { [self] success, error in
            guard gate.accept(token) else { return }

            if success {
                guard error == nil else {
                    // A true success bit means the sample may already be in the
                    // database even if the callback also carries an error.
                    builder.discard()
                    completeVerificationRequired(
                        gate,
                        energyExpected: true,
                        includedEnergy: true,
                        code: .energySampleAmbiguous
                    )
                    return
                }
                endCollection(
                    request,
                    builder: builder,
                    includedEnergy: true,
                    sampleAccepted: true,
                    gate: gate
                )
                return
            }

            let energyAuthorizationWasLost =
                Self.isEnergyAuthorizationFailure(error)
                || store.writeAuthorization(for: .activeEnergy) != .authorized
            if energyAuthorizationWasLost {
                fallbackToWorkoutOnly(
                    request,
                    failedBuilder: builder,
                    isFallback: isFallback,
                    workoutMetadata: workoutMetadata,
                    gate: gate
                )
            } else {
                builder.discard()
                completeTransientFailure(
                    gate,
                    energyExpected: true,
                    code: .energySampleFailed
                )
            }
        }
    }

    private func fallbackToWorkoutOnly(
        _ request: WorkoutWriteRequest,
        failedBuilder: HealthWorkoutBuilder,
        isFallback: Bool,
        workoutMetadata: MetadataPayload,
        gate: WriteCompletionGate
    ) {
        failedBuilder.discard()
        guard !isFallback else {
            completeTransientFailure(
                gate,
                energyExpected: true,
                code: .energyAuthorizationRetryFailed
            )
            return
        }
        guard store.writeAuthorization(for: .workout) == .authorized else {
            completeWorkoutPermissionBlock(gate, energyExpected: true)
            return
        }

        attempt(
            request,
            includeEnergy: false,
            isFallback: true,
            workoutMetadata: workoutMetadata,
            energyMetadata: nil,
            gate: gate
        )
    }

    private func endCollection(
        _ request: WorkoutWriteRequest,
        builder: HealthWorkoutBuilder,
        includedEnergy: Bool,
        sampleAccepted: Bool,
        gate: WriteCompletionGate
    ) {
        let energyExpected = request.energyClientRecordId != nil
        guard let token = gate.beginStage() else { return }
        builder.end(at: request.end) { [self] success, error in
            guard gate.accept(token) else { return }
            guard success, error == nil else {
                builder.discard()
                if sampleAccepted {
                    completeVerificationRequired(
                        gate,
                        energyExpected: energyExpected,
                        includedEnergy: includedEnergy,
                        code: .endCollectionFailed
                    )
                } else if Self.isWorkoutAuthorizationFailure(error) {
                    completeWorkoutPermissionBlock(
                        gate,
                        energyExpected: energyExpected
                    )
                } else {
                    completeTransientFailure(
                        gate,
                        energyExpected: energyExpected,
                        code: .endCollectionFailed
                    )
                }
                return
            }
            finish(
                request,
                builder: builder,
                includedEnergy: includedEnergy,
                gate: gate
            )
        }
    }

    private func finish(
        _ request: WorkoutWriteRequest,
        builder: HealthWorkoutBuilder,
        includedEnergy: Bool,
        gate: WriteCompletionGate
    ) {
        let energyExpected = request.energyClientRecordId != nil
        guard let token = gate.beginStage() else { return }
        builder.finish { [self] stored, error in
            guard gate.accept(token) else { return }
            guard let stored else {
                completeVerificationRequired(
                    gate,
                    energyExpected: energyExpected,
                    includedEnergy: includedEnergy,
                    code: error == nil
                        ? .finishWorkoutUnavailable
                        : .finishWorkoutFailed
                )
                return
            }

            guard includedEnergy == (stored.energyRecordID != nil) else {
                completeVerificationRequired(
                    gate,
                    energyExpected: energyExpected,
                    includedEnergy: includedEnergy,
                    code: .finishResultMismatch
                )
                return
            }

            if energyExpected, !includedEnergy {
                complete(
                    gate,
                    energyExpected: true,
                    status: .writtenWithoutEnergy,
                    workoutRecordID: stored.workoutRecordID.uuidString,
                    energyStatus: .omittedPermission,
                    retryable: false,
                    certainty: .submitted
                )
            } else {
                complete(
                    gate,
                    energyExpected: energyExpected,
                    status: .written,
                    workoutRecordID: stored.workoutRecordID.uuidString,
                    energyRecordID: stored.energyRecordID?.uuidString,
                    energyStatus: includedEnergy ? .written : .notExpected,
                    retryable: false,
                    certainty: .submitted
                )
            }
        }
    }

    private func completeWorkoutPermissionBlock(
        _ gate: WriteCompletionGate,
        energyExpected: Bool
    ) {
        complete(
            gate,
            energyExpected: energyExpected,
            status: .blockedWorkoutPermission,
            energyStatus: energyExpected ? .notSubmitted : .notExpected,
            retryable: false,
            certainty: .notSubmitted,
            code: .workoutPermissionMissing
        )
    }

    private func completeTransientFailure(
        _ gate: WriteCompletionGate,
        energyExpected: Bool,
        code: PlatformCode
    ) {
        complete(
            gate,
            energyExpected: energyExpected,
            status: .transientFailure,
            energyStatus: energyExpected ? .notSubmitted : .notExpected,
            retryable: true,
            certainty: .notSubmitted,
            code: code
        )
    }

    private func completeVerificationRequired(
        _ gate: WriteCompletionGate,
        energyExpected: Bool,
        includedEnergy: Bool,
        code: PlatformCode
    ) {
        let energyStatus: EnergyWriteStatus
        if includedEnergy {
            energyStatus = .verificationRequired
        } else if energyExpected {
            energyStatus = .omittedPermission
        } else {
            energyStatus = .notExpected
        }
        complete(
            gate,
            energyExpected: energyExpected,
            status: .verificationRequired,
            energyStatus: energyStatus,
            retryable: false,
            certainty: .mayHaveSubmitted,
            code: code
        )
    }

    private func complete(
        _ gate: WriteCompletionGate,
        energyExpected: Bool,
        status: WorkoutWriteStatus,
        workoutRecordID: String? = nil,
        energyRecordID: String? = nil,
        energyStatus: EnergyWriteStatus,
        retryable: Bool,
        certainty: SubmissionCertainty,
        code: PlatformCode? = nil
    ) {
        let result: WorkoutWriteResult
        do {
            result = try WorkoutWriteResult(
                status: status,
                workoutRecordId: workoutRecordID,
                energyRecordId: energyRecordID,
                energyStatus: energyStatus,
                retryable: retryable,
                submissionCertainty: certainty,
                platformCode: code?.rawValue
            )
        } catch {
            result =
                energyExpected
                ? invariantFailureWithEnergy
                : invariantFailureWithoutEnergy
        }
        gate.complete(result)
    }

    private func platformCode(
        for error: HealthWorkoutStoreError
    ) -> PlatformCode {
        switch error {
        case .activityUnavailable:
            return .activityUnavailable
        case .builderUnavailable:
            return .builderUnavailable
        }
    }

    private static func isWorkoutAuthorizationFailure(
        _ error: HealthWorkoutBuilderError?
    ) -> Bool {
        switch error {
        case .authorizationDenied(.workout),
            .authorizationNotDetermined(.workout):
            return true
        case .authorizationDenied(.activeEnergy),
            .authorizationNotDetermined(.activeEnergy),
            .operationFailed, nil:
            return false
        }
    }

    private static func isEnergyAuthorizationFailure(
        _ error: HealthWorkoutBuilderError?
    ) -> Bool {
        switch error {
        case .authorizationDenied(.activeEnergy),
            .authorizationNotDetermined(.activeEnergy):
            return true
        case .authorizationDenied(.workout),
            .authorizationNotDetermined(.workout),
            .operationFailed, nil:
            return false
        }
    }

    private static func isEnergyIntervalTooShort(
        startEpochMilliseconds: Int64,
        endEpochMilliseconds: Int64
    ) -> Bool {
        let (durationMilliseconds, overflow) =
            endEpochMilliseconds.subtractingReportingOverflow(
                startEpochMilliseconds
            )
        if overflow {
            // WorkoutWriteRequest guarantees end > start, so overflow here is
            // necessarily a positive interval larger than Int64.max milliseconds.
            return false
        }
        return durationMilliseconds <= 1
    }

    private static func hasRepresentableHealthKitDates(
        _ request: WorkoutWriteRequest,
        energyExpected: Bool
    ) -> Bool {
        let start = request.start
        let end = request.end
        guard start < end else { return false }
        guard energyExpected else { return true }

        let energyStart = start.addingTimeInterval(energyStartOffset)
        return start < energyStart && energyStart < end
    }

    private static let energyStartOffset = 0.001
}

typealias HealthWorkoutMetadataFactory =
    @Sendable (
        _ clientRecordID: String,
        _ clientRecordVersion: Int,
        _ provenance: HealthRecordingProvenance
    ) throws -> [String: Any]

private struct MetadataPayload: @unchecked Sendable {
    let values: [String: Any]

    init(_ values: [String: Any]) {
        self.values = values
    }
}

private struct ComponentLookupOutcome: Sendable {
    let status: RecordLookupStatus
    let recordID: String?
    let code: PlatformCode?

    static let absent = ComponentLookupOutcome(
        status: .absent,
        recordID: nil,
        code: nil
    )

    static let notExpected = ComponentLookupOutcome(
        status: .notExpected,
        recordID: nil,
        code: nil
    )

    static func present(_ recordID: String) -> ComponentLookupOutcome {
        ComponentLookupOutcome(
            status: .present,
            recordID: recordID,
            code: nil
        )
    }

    static func unavailable(_ code: PlatformCode) -> ComponentLookupOutcome {
        ComponentLookupOutcome(
            status: .unavailable,
            recordID: nil,
            code: code
        )
    }
}

private enum PlatformCode: String, Sendable {
    case activityUnavailable
    case beginCollectionFailed
    case builderUnavailable
    case endCollectionFailed
    case energyAuthorizationRetryFailed
    case energyIntervalTooShort
    case energySampleAmbiguous
    case energySampleFailed
    case finishResultMismatch
    case finishWorkoutFailed
    case finishWorkoutUnavailable
    case healthDataUnavailable
    case healthKitDateIntervalUnrepresentable
    case healthKitLookupFailed
    case healthKitProtectedDataUnavailable
    case healthKitTypeUnavailable
    case internalResultValidationFailed
    case invalidMetadata
    case multipleMatchingRecords
    case workoutMetadataFailed
    case workoutPermissionMissing
}

private final class LookupCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private let completion: @Sendable (WorkoutLookupResult) -> Void
    private var completed = false
    private var nextToken: UInt64 = 0
    private var activeToken: UInt64?

    init(completion: @escaping @Sendable (WorkoutLookupResult) -> Void) {
        self.completion = completion
    }

    func beginStage() -> UInt64? {
        lock.withLock {
            guard !completed else { return nil }
            nextToken &+= 1
            activeToken = nextToken
            return nextToken
        }
    }

    func accept(_ token: UInt64) -> Bool {
        lock.withLock {
            guard !completed, activeToken == token else { return false }
            activeToken = nil
            return true
        }
    }

    func complete(_ result: WorkoutLookupResult) {
        let shouldComplete = lock.withLock {
            guard !completed else { return false }
            completed = true
            activeToken = nil
            return true
        }
        if shouldComplete {
            completion(result)
        }
    }
}

private final class WriteCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private let completion: @Sendable (WorkoutWriteResult) -> Void
    private var completed = false
    private var nextToken: UInt64 = 0
    private var activeToken: UInt64?

    init(completion: @escaping @Sendable (WorkoutWriteResult) -> Void) {
        self.completion = completion
    }

    func beginStage() -> UInt64? {
        lock.withLock {
            guard !completed else { return nil }
            nextToken &+= 1
            activeToken = nextToken
            return nextToken
        }
    }

    func accept(_ token: UInt64) -> Bool {
        lock.withLock {
            guard !completed, activeToken == token else { return false }
            activeToken = nil
            return true
        }
    }

    func complete(_ result: WorkoutWriteResult) {
        let shouldComplete = lock.withLock {
            guard !completed else { return false }
            completed = true
            activeToken = nil
            return true
        }
        if shouldComplete {
            completion(result)
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
