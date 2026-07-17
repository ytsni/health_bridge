import Foundation
import HealthKit
import XCTest

@testable import HealthBridgeWorkoutCore

final class HealthWorkoutMetadataTests: XCTestCase {
    private let workoutID = "018f8d7e-1111-7111-8111-111111111111"
    private let energyID = "018f8d7e-2222-7222-8222-222222222222"
    private let startEpochMilliseconds: Int64 = 1_735_700_400_000
    private let endEpochMilliseconds: Int64 = 1_735_704_000_000
    private let start = Date(timeIntervalSince1970: 1_735_700_400)
    private let end = Date(timeIntervalSince1970: 1_735_704_000)

    func testManualMetadataIsTypeSpecificAndUserEntered() throws {
        let workoutMetadata = try HealthWorkoutMetadata.make(
            clientRecordId: workoutID,
            clientRecordVersion: 0,
            provenance: .manualEntry
        )
        let energyMetadata = try HealthWorkoutMetadata.make(
            clientRecordId: energyID,
            clientRecordVersion: 0,
            provenance: .manualEntry
        )

        assertMetadata(
            workoutMetadata,
            clientRecordId: workoutID,
            wasUserEntered: true
        )
        assertMetadata(
            energyMetadata,
            clientRecordId: energyID,
            wasUserEntered: true
        )
        XCTAssertNotEqual(
            workoutMetadata[HKMetadataKeyExternalUUID] as? String,
            energyMetadata[HKMetadataKeyExternalUUID] as? String
        )
    }

    func testActivelyRecordedMetadataIsNotUserEnteredEvenAfterRecovery() throws {
        let recoveredLiveWorkoutMetadata = try HealthWorkoutMetadata.make(
            clientRecordId: workoutID,
            clientRecordVersion: 0,
            provenance: .activelyRecorded
        )
        let recoveredLiveEnergyMetadata = try HealthWorkoutMetadata.make(
            clientRecordId: energyID,
            clientRecordVersion: 0,
            provenance: .activelyRecorded
        )

        assertMetadata(
            recoveredLiveWorkoutMetadata,
            clientRecordId: workoutID,
            wasUserEntered: false
        )
        assertMetadata(
            recoveredLiveEnergyMetadata,
            clientRecordId: energyID,
            wasUserEntered: false
        )
    }

    func testMetadataRejectsMalformedClientRecordIds() {
        for invalidID in [
            "",
            "not-a-uuid",
            " 018f8d7e-1111-7111-8111-111111111111 ",
            "018f8d7e-1111-7111-8111-11111111111",
        ] {
            XCTAssertThrowsError(
                try HealthWorkoutMetadata.make(
                    clientRecordId: invalidID,
                    clientRecordVersion: 0,
                    provenance: .activelyRecorded
                )
            ) { error in
                XCTAssertEqual(
                    error as? HealthWorkoutMetadataError,
                    .invalidClientRecordId
                )
            }
        }
    }

    func testMetadataRejectsEveryNonzeroClientRecordVersion() {
        for invalidVersion in [-1, 1, Int.max] {
            XCTAssertThrowsError(
                try HealthWorkoutMetadata.make(
                    clientRecordId: workoutID,
                    clientRecordVersion: invalidVersion,
                    provenance: .activelyRecorded
                )
            ) { error in
                XCTAssertEqual(
                    error as? HealthWorkoutMetadataError,
                    .invalidClientRecordVersion
                )
            }
        }
    }

    func testWriteRequestAcceptsExactlyTheTwoEnergyShapes() throws {
        let noEnergy = try makeRequest()
        XCTAssertNil(noEnergy.energyClientRecordId)
        XCTAssertNil(noEnergy.activeEnergyKcal)

        let withEnergy = try makeRequest(
            energyClientRecordId: energyID,
            activeEnergyKcal: 314.25
        )
        XCTAssertEqual(withEnergy.energyClientRecordId, energyID)
        XCTAssertEqual(withEnergy.activeEnergyKcal, 314.25)
    }

    func testWriteRequestPreservesExtremeEpochMillisecondsWithoutNarrowing() throws {
        for (startEpochMilliseconds, endEpochMilliseconds) in [
            (Int64.min, Int64.min + 2),
            (Int64.max - 2, Int64.max),
            (Int64.min, Int64.max),
        ] {
            let request = try makeRequest(
                startEpochMilliseconds: startEpochMilliseconds,
                endEpochMilliseconds: endEpochMilliseconds
            )

            XCTAssertEqual(
                request.startEpochMilliseconds,
                startEpochMilliseconds
            )
            XCTAssertEqual(request.endEpochMilliseconds, endEpochMilliseconds)
            XCTAssertEqual(
                request.start,
                Date(
                    timeIntervalSince1970: Double(startEpochMilliseconds) / 1_000
                )
            )
            XCTAssertEqual(
                request.end,
                Date(
                    timeIntervalSince1970: Double(endEpochMilliseconds) / 1_000
                )
            )
        }
    }

    func testWriteRequestRejectsMismatchedEnergyAndIdentifier() {
        assertModelError(.invalidEnergyPair) {
            _ = try makeRequest(
                energyClientRecordId: energyID,
                activeEnergyKcal: nil
            )
        }
        assertModelError(.invalidEnergyPair) {
            _ = try makeRequest(
                energyClientRecordId: nil,
                activeEnergyKcal: 314.25
            )
        }
    }

    func testWriteRequestRejectsMalformedIdentifiersAndVersion() {
        assertModelError(.invalidWorkoutClientRecordId) {
            _ = try makeRequest(workoutClientRecordId: "not-a-uuid")
        }
        assertModelError(.invalidEnergyClientRecordId) {
            _ = try makeRequest(
                energyClientRecordId: "not-a-uuid",
                activeEnergyKcal: 314.25
            )
        }
        assertModelError(.invalidClientRecordVersion) {
            _ = try makeRequest(clientRecordVersion: 1)
        }
    }

    func testWriteRequestRejectsOtherLockedInvalidShapes() {
        assertModelError(.invalidDateRange) {
            _ = try makeRequest(
                endEpochMilliseconds: startEpochMilliseconds
            )
        }
        assertModelError(.invalidDateRange) {
            _ = try makeRequest(
                startEpochMilliseconds: Int64.max,
                endEpochMilliseconds: Int64.min
            )
        }
        assertModelError(.invalidStartZoneOffset) {
            _ = try makeRequest(startZoneOffsetSeconds: -64_801)
        }
        assertModelError(.invalidEndZoneOffset) {
            _ = try makeRequest(endZoneOffsetSeconds: 64_801)
        }
        assertModelError(.invalidActiveEnergy) {
            _ = try makeRequest(
                energyClientRecordId: energyID,
                activeEnergyKcal: .infinity
            )
        }
        assertModelError(.invalidActiveEnergy) {
            _ = try makeRequest(
                energyClientRecordId: energyID,
                activeEnergyKcal: 0
            )
        }
        assertModelError(.invalidActivityType) {
            _ = try makeRequest(activityType: "   ")
        }
        assertModelError(.invalidTitle) {
            _ = try makeRequest(title: "\n\t")
        }
    }

    func testLookupRequestRequiresFrozenIdentityAndIncreasingRange() throws {
        let request = try WorkoutLookupRequest(
            workoutClientRecordId: workoutID,
            energyClientRecordId: nil,
            start: start,
            end: end
        )
        XCTAssertEqual(request.workoutClientRecordId, workoutID)
        XCTAssertNil(request.energyClientRecordId)

        XCTAssertThrowsError(
            try WorkoutLookupRequest(
                workoutClientRecordId: "not-a-uuid",
                energyClientRecordId: nil,
                start: start,
                end: end
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkoutModelError,
                .invalidWorkoutClientRecordId
            )
        }
        XCTAssertThrowsError(
            try WorkoutLookupRequest(
                workoutClientRecordId: workoutID,
                energyClientRecordId: energyID,
                start: start,
                end: start
            )
        ) { error in
            XCTAssertEqual(error as? WorkoutModelError, .invalidDateRange)
        }
    }

    func testWireEnumsHaveTheExactLockedRawValues() {
        XCTAssertEqual(
            HealthRecordingProvenance.allCases.map(\.rawValue),
            ["activelyRecorded", "manualEntry"]
        )
        XCTAssertEqual(
            HealthRecordingDevice.allCases.map(\.rawValue),
            ["phone", "watch"]
        )
        XCTAssertEqual(
            WorkoutWriteStatus.allCases.map(\.rawValue),
            [
                "written",
                "alreadyPresent",
                "writtenWithoutEnergy",
                "blockedWorkoutPermission",
                "verificationRequired",
                "inconsistentNativeState",
                "transientFailure",
                "invalidInput",
                "unavailable",
            ]
        )
        XCTAssertEqual(
            EnergyWriteStatus.allCases.map(\.rawValue),
            [
                "notExpected",
                "written",
                "alreadyPresent",
                "omittedPermission",
                "absent",
                "notSubmitted",
                "verificationRequired",
            ]
        )
        XCTAssertEqual(
            SubmissionCertainty.allCases.map(\.rawValue),
            ["notSubmitted", "mayHaveSubmitted", "submitted"]
        )
        XCTAssertEqual(
            RecordLookupStatus.allCases.map(\.rawValue),
            ["present", "absent", "unavailable", "notExpected"]
        )
        XCTAssertEqual(
            WorkoutLookupStatus.allCases.map(\.rawValue),
            ["present", "workoutOnly", "absent", "unavailable", "inconsistent"]
        )
        XCTAssertEqual(
            AuthorizationState.allCases.map(\.rawValue),
            [
                "authorized",
                "denied",
                "notDetermined",
                "requestedOrUnknown",
                "unavailable",
                "unsupported",
            ]
        )
    }

    func testCoreValueTypesAreSendableEquatableAndStructurallyImmutable() throws {
        assertSendableAndEquatable(HealthRecordingProvenance.self)
        assertSendableAndEquatable(HealthRecordingDevice.self)
        assertSendableAndEquatable(WorkoutWriteStatus.self)
        assertSendableAndEquatable(EnergyWriteStatus.self)
        assertSendableAndEquatable(SubmissionCertainty.self)
        assertSendableAndEquatable(RecordLookupStatus.self)
        assertSendableAndEquatable(WorkoutLookupStatus.self)
        assertSendableAndEquatable(AuthorizationState.self)
        assertSendableAndEquatable(WorkoutWriteRequest.self)
        assertSendableAndEquatable(WorkoutLookupRequest.self)
        assertSendableAndEquatable(WorkoutWriteResult.self)
        assertSendableAndEquatable(RecordLookup.self)
        assertSendableAndEquatable(WorkoutLookupResult.self)
        assertSendableAndEquatable(HealthTypeAuthorization.self)
        assertSendableAndEquatable(HealthAuthorizationSnapshot.self)

        let request = try makeRequest()
        XCTAssertEqual(request, request)
        let first = try WorkoutWriteResult(
            status: .writtenWithoutEnergy,
            workoutRecordId: "native-workout",
            energyRecordId: nil,
            energyStatus: .omittedPermission,
            retryable: false,
            submissionCertainty: .submitted,
            platformCode: nil
        )
        let second = try WorkoutWriteResult(
            status: .writtenWithoutEnergy,
            workoutRecordId: "native-workout",
            energyRecordId: nil,
            energyStatus: .omittedPermission,
            retryable: false,
            submissionCertainty: .submitted,
            platformCode: nil
        )
        XCTAssertEqual(first, second)
    }

    func testWriteResultAcceptsExactlyTheLockedStatusEnergyMatrix() throws {
        var acceptedPairs = 0

        for status in WorkoutWriteStatus.allCases {
            for energyStatus in EnergyWriteStatus.allCases {
                let shape = canonicalWriteShape(
                    status: status,
                    energyStatus: energyStatus
                )
                if isValidWritePair(status: status, energyStatus: energyStatus) {
                    _ = try makeWriteResult(
                        status: status,
                        energyStatus: energyStatus,
                        shape: shape
                    )
                    acceptedPairs += 1
                } else {
                    XCTAssertThrowsError(
                        try makeWriteResult(
                            status: status,
                            energyStatus: energyStatus,
                            shape: shape
                        ),
                        "Unexpected valid pair: \(status.rawValue)/\(energyStatus.rawValue)"
                    )
                }
            }
        }

        XCTAssertEqual(acceptedPairs, 18)
    }

    func testEveryValidWritePairRejectsIdentifierAndCertaintyFlips() throws {
        var exercisedPairs = 0

        for status in WorkoutWriteStatus.allCases {
            for energyStatus in EnergyWriteStatus.allCases
            where isValidWritePair(status: status, energyStatus: energyStatus) {
                let shape = canonicalWriteShape(
                    status: status,
                    energyStatus: energyStatus
                )
                _ = try makeWriteResult(
                    status: status,
                    energyStatus: energyStatus,
                    shape: shape
                )

                XCTAssertThrowsError(
                    try makeWriteResult(
                        status: status,
                        energyStatus: energyStatus,
                        shape: shape.with(
                            workoutRecordId: flippedIdentifier(
                                shape.workoutRecordId,
                                presentValue: "native-workout"
                            )
                        )
                    ),
                    "Workout ID flip escaped for \(status.rawValue)/\(energyStatus.rawValue)"
                )
                XCTAssertThrowsError(
                    try makeWriteResult(
                        status: status,
                        energyStatus: energyStatus,
                        shape: shape.with(
                            energyRecordId: flippedIdentifier(
                                shape.energyRecordId,
                                presentValue: "native-energy"
                            )
                        )
                    ),
                    "Energy ID flip escaped for \(status.rawValue)/\(energyStatus.rawValue)"
                )
                for certainty in SubmissionCertainty.allCases
                where certainty != shape.submissionCertainty {
                    XCTAssertThrowsError(
                        try makeWriteResult(
                            status: status,
                            energyStatus: energyStatus,
                            shape: shape.with(submissionCertainty: certainty)
                        ),
                        "Certainty flip escaped for \(status.rawValue)/\(energyStatus.rawValue)"
                    )
                }
                exercisedPairs += 1
            }
        }

        XCTAssertEqual(exercisedPairs, 18)
    }

    func testWriteResultRejectsBlankOptionalStrings() {
        let writtenShape = canonicalWriteShape(
            status: .written,
            energyStatus: .written
        )
        XCTAssertThrowsError(
            try makeWriteResult(
                status: .written,
                energyStatus: .written,
                shape: writtenShape.with(workoutRecordId: " \n ")
            )
        )
        XCTAssertThrowsError(
            try makeWriteResult(
                status: .written,
                energyStatus: .written,
                shape: writtenShape.with(energyRecordId: "\t")
            )
        )
        XCTAssertThrowsError(
            try makeWriteResult(
                status: .written,
                energyStatus: .written,
                shape: writtenShape,
                platformCode: "   "
            )
        )
    }

    func testRecordLookupRequiresAUniqueNonblankPresentIdentifier() throws {
        for status in RecordLookupStatus.allCases {
            let validRecordID = status == .present ? "native-id" : nil
            _ = try RecordLookup(status: status, recordId: validRecordID)

            XCTAssertThrowsError(
                try RecordLookup(
                    status: status,
                    recordId: validRecordID == nil ? "native-id" : nil
                ),
                "Identifier presence escaped for \(status.rawValue)"
            )
        }

        XCTAssertThrowsError(
            try RecordLookup(status: .present, recordId: "\n")
        )
    }

    func testWorkoutLookupExhaustsComponentDerivationAndRejectsMismatches() throws {
        var legalCombinations = 0

        for workoutStatus in RecordLookupStatus.allCases {
            for energyStatus in RecordLookupStatus.allCases {
                guard
                    let expected = expectedLookupStatus(
                        workout: workoutStatus,
                        energy: energyStatus
                    )
                else {
                    XCTAssertThrowsError(
                        try makeLookupResult(
                            workoutStatus: workoutStatus,
                            energyStatus: energyStatus,
                            derivedStatus: .unavailable
                        )
                    )
                    continue
                }

                _ = try makeLookupResult(
                    workoutStatus: workoutStatus,
                    energyStatus: energyStatus,
                    derivedStatus: expected
                )
                for wrongStatus in WorkoutLookupStatus.allCases
                where wrongStatus != expected {
                    XCTAssertThrowsError(
                        try makeLookupResult(
                            workoutStatus: workoutStatus,
                            energyStatus: energyStatus,
                            derivedStatus: wrongStatus
                        ),
                        "Aggregate mismatch escaped for \(workoutStatus.rawValue)/\(energyStatus.rawValue)"
                    )
                }
                legalCombinations += 1
            }
        }

        XCTAssertEqual(legalCombinations, 12)
        XCTAssertThrowsError(
            try makeLookupResult(
                workoutStatus: .present,
                energyStatus: .notExpected,
                derivedStatus: .workoutOnly,
                platformCode: "\t"
            )
        )
    }

    func testAuthorizationModelsValidateCanonicalImmutableSnapshots() throws {
        let workout = try HealthTypeAuthorization(
            type: "WORKOUT",
            read: .requestedOrUnknown,
            write: .authorized
        )
        let energy = try HealthTypeAuthorization(
            type: "ACTIVE_ENERGY_BURNED",
            read: .requestedOrUnknown,
            write: .denied
        )
        var source = [workout, energy]
        let first = try HealthAuthorizationSnapshot(
            available: true,
            types: source,
            platformCode: "available"
        )
        source.removeAll()
        let second = try HealthAuthorizationSnapshot(
            available: true,
            types: [energy, workout],
            platformCode: "available"
        )

        XCTAssertEqual(
            first.types.map(\.type),
            ["ACTIVE_ENERGY_BURNED", "WORKOUT"]
        )
        XCTAssertEqual(first.types.count, 2)
        XCTAssertEqual(first, second)
    }

    func testAuthorizationModelsRejectEveryImpossibleAvailabilityShape() throws {
        XCTAssertThrowsError(
            try HealthTypeAuthorization(
                type: " \n ",
                read: .authorized,
                write: .authorized
            )
        )

        let workout = try HealthTypeAuthorization(
            type: "WORKOUT",
            read: .authorized,
            write: .authorized
        )
        let readUnavailable = try HealthTypeAuthorization(
            type: "WORKOUT",
            read: .unavailable,
            write: .authorized
        )
        let writeUnavailable = try HealthTypeAuthorization(
            type: "WORKOUT",
            read: .authorized,
            write: .unavailable
        )
        let allUnavailable = try HealthTypeAuthorization(
            type: "WORKOUT",
            read: .unavailable,
            write: .unavailable
        )

        XCTAssertThrowsError(
            try HealthAuthorizationSnapshot(
                available: true,
                types: [],
                platformCode: nil
            )
        )
        XCTAssertThrowsError(
            try HealthAuthorizationSnapshot(
                available: true,
                types: [workout, workout],
                platformCode: nil
            )
        )
        XCTAssertThrowsError(
            try HealthAuthorizationSnapshot(
                available: true,
                types: [workout],
                platformCode: " "
            )
        )
        XCTAssertThrowsError(
            try HealthAuthorizationSnapshot(
                available: true,
                types: [readUnavailable],
                platformCode: nil
            )
        )
        XCTAssertThrowsError(
            try HealthAuthorizationSnapshot(
                available: true,
                types: [writeUnavailable],
                platformCode: nil
            )
        )
        XCTAssertThrowsError(
            try HealthAuthorizationSnapshot(
                available: false,
                types: [readUnavailable],
                platformCode: nil
            )
        )
        XCTAssertThrowsError(
            try HealthAuthorizationSnapshot(
                available: false,
                types: [writeUnavailable],
                platformCode: nil
            )
        )
        _ = try HealthAuthorizationSnapshot(
            available: false,
            types: [allUnavailable],
            platformCode: nil
        )
    }

    func testIOSActivityParityAcceptsExactlyTheDartContract() throws {
        XCTAssertEqual(allWorkoutActivityTypes.count, 99)
        XCTAssertEqual(Set(allWorkoutActivityTypes).count, 99)
        XCTAssertEqual(unsupportedIOSActivityTypes.count, 18)

        var accepted: Set<String> = []
        var rejected: Set<String> = []
        for activityType in allWorkoutActivityTypes {
            if unsupportedIOSActivityTypes.contains(activityType) {
                XCTAssertThrowsError(
                    try makeRequest(activityType: activityType),
                    "iOS accepted Dart-rejected activity \(activityType)"
                )
                rejected.insert(activityType)
            } else {
                _ = try makeRequest(activityType: activityType)
                accepted.insert(activityType)
            }
        }

        XCTAssertEqual(accepted.count, 81)
        XCTAssertEqual(rejected, unsupportedIOSActivityTypes)
        XCTAssertThrowsError(try makeRequest(activityType: "NOT_A_WORKOUT"))
        XCTAssertThrowsError(
            try makeRequest(activityType: "traditional_strength_training")
        )
    }

    private struct WriteShape {
        let workoutRecordId: String?
        let energyRecordId: String?
        let submissionCertainty: SubmissionCertainty

        func with(
            workoutRecordId: String?? = nil,
            energyRecordId: String?? = nil,
            submissionCertainty: SubmissionCertainty? = nil
        ) -> WriteShape {
            WriteShape(
                workoutRecordId: workoutRecordId ?? self.workoutRecordId,
                energyRecordId: energyRecordId ?? self.energyRecordId,
                submissionCertainty: submissionCertainty ?? self.submissionCertainty
            )
        }
    }

    private func canonicalWriteShape(
        status: WorkoutWriteStatus,
        energyStatus: EnergyWriteStatus
    ) -> WriteShape {
        let workoutRecordId: String? =
            switch status {
            case .written, .alreadyPresent, .writtenWithoutEnergy:
                "native-workout"
            case .blockedWorkoutPermission, .verificationRequired,
                .inconsistentNativeState, .transientFailure, .invalidInput,
                .unavailable:
                nil
            }
        let energyRecordId: String? =
            switch energyStatus {
            case .written, .alreadyPresent:
                "native-energy"
            case .notExpected, .omittedPermission, .absent, .notSubmitted,
                .verificationRequired:
                nil
            }
        let submissionCertainty: SubmissionCertainty =
            switch status {
            case .written, .alreadyPresent, .writtenWithoutEnergy,
                .inconsistentNativeState:
                .submitted
            case .verificationRequired:
                .mayHaveSubmitted
            case .blockedWorkoutPermission, .transientFailure, .invalidInput,
                .unavailable:
                .notSubmitted
            }
        return WriteShape(
            workoutRecordId: workoutRecordId,
            energyRecordId: energyRecordId,
            submissionCertainty: submissionCertainty
        )
    }

    private func isValidWritePair(
        status: WorkoutWriteStatus,
        energyStatus: EnergyWriteStatus
    ) -> Bool {
        switch status {
        case .written:
            energyStatus == .notExpected || energyStatus == .written
        case .alreadyPresent:
            energyStatus == .notExpected || energyStatus == .alreadyPresent
                || energyStatus == .absent
        case .writtenWithoutEnergy:
            energyStatus == .omittedPermission
        case .blockedWorkoutPermission, .transientFailure, .invalidInput,
            .unavailable:
            energyStatus == .notExpected || energyStatus == .notSubmitted
        case .verificationRequired:
            energyStatus == .notExpected || energyStatus == .omittedPermission
                || energyStatus == .verificationRequired
        case .inconsistentNativeState:
            energyStatus == .alreadyPresent
        }
    }

    private func makeWriteResult(
        status: WorkoutWriteStatus,
        energyStatus: EnergyWriteStatus,
        shape: WriteShape,
        platformCode: String? = nil
    ) throws -> WorkoutWriteResult {
        try WorkoutWriteResult(
            status: status,
            workoutRecordId: shape.workoutRecordId,
            energyRecordId: shape.energyRecordId,
            energyStatus: energyStatus,
            retryable: false,
            submissionCertainty: shape.submissionCertainty,
            platformCode: platformCode
        )
    }

    private func flippedIdentifier(
        _ value: String?,
        presentValue: String
    ) -> String? {
        value == nil ? presentValue : nil
    }

    private func expectedLookupStatus(
        workout: RecordLookupStatus,
        energy: RecordLookupStatus
    ) -> WorkoutLookupStatus? {
        guard workout != .notExpected else {
            return nil
        }
        if workout == .unavailable || energy == .unavailable {
            return .unavailable
        }
        switch (workout, energy) {
        case (.absent, .present):
            return .inconsistent
        case (.absent, .absent), (.absent, .notExpected):
            return .absent
        case (.present, .present):
            return .present
        case (.present, .absent), (.present, .notExpected):
            return .workoutOnly
        case (.notExpected, _), (_, .unavailable), (.unavailable, _):
            return nil
        }
    }

    private func makeLookupResult(
        workoutStatus: RecordLookupStatus,
        energyStatus: RecordLookupStatus,
        derivedStatus: WorkoutLookupStatus,
        platformCode: String? = nil
    ) throws -> WorkoutLookupResult {
        let workout = try RecordLookup(
            status: workoutStatus,
            recordId: workoutStatus == .present ? "native-workout" : nil
        )
        let energy = try RecordLookup(
            status: energyStatus,
            recordId: energyStatus == .present ? "native-energy" : nil
        )
        return try WorkoutLookupResult(
            workout: workout,
            energy: energy,
            derivedStatus: derivedStatus,
            platformCode: platformCode
        )
    }

    private func assertMetadata(
        _ metadata: [String: Any],
        clientRecordId: String,
        wasUserEntered: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            metadata[HKMetadataKeySyncIdentifier] as? String,
            clientRecordId,
            file: file,
            line: line
        )
        XCTAssertEqual(
            metadata[HKMetadataKeySyncVersion] as? Int,
            0,
            file: file,
            line: line
        )
        XCTAssertEqual(
            metadata[HKMetadataKeyWasUserEntered] as? Bool,
            wasUserEntered,
            file: file,
            line: line
        )
        XCTAssertEqual(
            metadata[HKMetadataKeyExternalUUID] as? String,
            clientRecordId,
            file: file,
            line: line
        )
        XCTAssertNil(
            metadata[HKMetadataKeyExternalUUID] as? UUID,
            file: file,
            line: line
        )
    }

    private func makeRequest(
        workoutClientRecordId: String? = nil,
        energyClientRecordId: String? = nil,
        clientRecordVersion: Int = 0,
        activityType: String = "TRADITIONAL_STRENGTH_TRAINING",
        startEpochMilliseconds: Int64? = nil,
        endEpochMilliseconds: Int64? = nil,
        startZoneOffsetSeconds: Int = -18_000,
        endZoneOffsetSeconds: Int = -14_400,
        activeEnergyKcal: Double? = nil,
        title: String = "Strength Training"
    ) throws -> WorkoutWriteRequest {
        try WorkoutWriteRequest(
            workoutClientRecordId: workoutClientRecordId ?? workoutID,
            energyClientRecordId: energyClientRecordId,
            clientRecordVersion: clientRecordVersion,
            activityType: activityType,
            startEpochMilliseconds: startEpochMilliseconds
                ?? self.startEpochMilliseconds,
            endEpochMilliseconds: endEpochMilliseconds
                ?? self.endEpochMilliseconds,
            startZoneOffsetSeconds: startZoneOffsetSeconds,
            endZoneOffsetSeconds: endZoneOffsetSeconds,
            activeEnergyKcal: activeEnergyKcal,
            title: title,
            recordingProvenance: .activelyRecorded,
            recordingDevice: .phone
        )
    }

    private func assertModelError(
        _ expectedError: WorkoutModelError,
        _ operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? WorkoutModelError,
                expectedError,
                file: file,
                line: line
            )
        }
    }

    private func assertSendableAndEquatable<T: Sendable & Equatable>(
        _: T.Type
    ) {}
}

private let unsupportedIOSActivityTypes: Set<String> = [
    "BIKING_STATIONARY",
    "CALISTHENICS",
    "DANCING",
    "FRISBEE_DISC",
    "GUIDED_BREATHING",
    "ICE_SKATING",
    "PARAGLIDING",
    "ROCK_CLIMBING",
    "ROWING_MACHINE",
    "RUNNING_TREADMILL",
    "SCUBA_DIVING",
    "SKIING",
    "SNOWSHOEING",
    "STAIR_CLIMBING_MACHINE",
    "STRENGTH_TRAINING",
    "WALKING_TREADMILL",
    "WEIGHTLIFTING",
    "WHEELCHAIR",
]

private let allWorkoutActivityTypes = [
    "AMERICAN_FOOTBALL",
    "ARCHERY",
    "AUSTRALIAN_FOOTBALL",
    "BADMINTON",
    "BASEBALL",
    "BASKETBALL",
    "BIKING",
    "BOXING",
    "CARDIO_DANCE",
    "CRICKET",
    "CROSS_COUNTRY_SKIING",
    "CURLING",
    "DOWNHILL_SKIING",
    "ELLIPTICAL",
    "FENCING",
    "GOLF",
    "GYMNASTICS",
    "HANDBALL",
    "HIGH_INTENSITY_INTERVAL_TRAINING",
    "HIKING",
    "HOCKEY",
    "JUMP_ROPE",
    "KICKBOXING",
    "MARTIAL_ARTS",
    "PILATES",
    "RACQUETBALL",
    "ROWING",
    "RUGBY",
    "RUNNING",
    "SAILING",
    "SKATING",
    "SNOWBOARDING",
    "SOCCER",
    "SOFTBALL",
    "SQUASH",
    "STAIR_CLIMBING",
    "SWIMMING",
    "TABLE_TENNIS",
    "TENNIS",
    "VOLLEYBALL",
    "WALKING",
    "WATER_POLO",
    "YOGA",
    "BARRE",
    "BOWLING",
    "CLIMBING",
    "COOLDOWN",
    "CORE_TRAINING",
    "CROSS_TRAINING",
    "DISC_SPORTS",
    "EQUESTRIAN_SPORTS",
    "FISHING",
    "FITNESS_GAMING",
    "FLEXIBILITY",
    "FUNCTIONAL_STRENGTH_TRAINING",
    "HAND_CYCLING",
    "HUNTING",
    "LACROSSE",
    "MIND_AND_BODY",
    "MIXED_CARDIO",
    "PADDLE_SPORTS",
    "PICKLEBALL",
    "PLAY",
    "PREPARATION_AND_RECOVERY",
    "SNOW_SPORTS",
    "SOCIAL_DANCE",
    "STAIRS",
    "STEP_TRAINING",
    "SURFING",
    "TAI_CHI",
    "TRACK_AND_FIELD",
    "TRADITIONAL_STRENGTH_TRAINING",
    "WATER_FITNESS",
    "WATER_SPORTS",
    "WHEELCHAIR_RUN_PACE",
    "WHEELCHAIR_WALK_PACE",
    "WRESTLING",
    "UNDERWATER_DIVING",
    "BIKING_STATIONARY",
    "CALISTHENICS",
    "DANCING",
    "FRISBEE_DISC",
    "GUIDED_BREATHING",
    "ICE_SKATING",
    "PARAGLIDING",
    "ROCK_CLIMBING",
    "ROWING_MACHINE",
    "RUNNING_TREADMILL",
    "SCUBA_DIVING",
    "SKIING",
    "SNOWSHOEING",
    "STAIR_CLIMBING_MACHINE",
    "STRENGTH_TRAINING",
    "SWIMMING_OPEN_WATER",
    "SWIMMING_POOL",
    "WALKING_TREADMILL",
    "WEIGHTLIFTING",
    "WHEELCHAIR",
    "OTHER",
]
