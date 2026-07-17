package cachet.plugins.health

import androidx.health.connect.client.records.ExerciseSessionRecord
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthWorkoutModelsTest {
    @Test
    fun parseWriteRequest_preservesFrozenFields() {
        val request = WorkoutWriteRequest.fromMap(validWriteArguments())

        assertEquals(WORKOUT_CLIENT_ID, request.workoutClientRecordId)
        assertEquals(ENERGY_CLIENT_ID, request.energyClientRecordId)
        assertEquals(0L, request.clientRecordVersion)
        assertEquals("STRENGTH_TRAINING", request.activityType)
        assertEquals(WORKOUT_START, request.startTime)
        assertEquals(WORKOUT_END, request.endTime)
        assertEquals(-18_000, request.startZoneOffsetSeconds)
        assertEquals(-14_400, request.endZoneOffsetSeconds)
        assertEquals(123.5, request.activeEnergyKcal)
        assertEquals("Plates Workout", request.title)
        assertEquals(RecordingProvenance.ACTIVELY_RECORDED, request.recordingProvenance)
        assertEquals(RecordingDevice.PHONE, request.recordingDevice)
    }

    @Test
    fun parseLookupRequest_preservesFrozenIdentityAndRange() {
        val request = WorkoutLookupRequest.fromMap(validLookupArguments())

        assertEquals(WORKOUT_CLIENT_ID, request.workoutClientRecordId)
        assertEquals(ENERGY_CLIENT_ID, request.energyClientRecordId)
        assertEquals(WORKOUT_START, request.startTime)
        assertEquals(WORKOUT_END, request.endTime)
    }

    @Test
    fun parseRequests_rejectMissingBlankMalformedAndWrongTypeIds() {
        val invalidWriteArguments =
            listOf(
                validWriteArguments() - "workoutClientRecordId",
                validWriteArguments() + ("workoutClientRecordId" to "   "),
                validWriteArguments() + ("workoutClientRecordId" to "not-a-uuid"),
                validWriteArguments() + ("workoutClientRecordId" to 7),
                validWriteArguments() + ("energyClientRecordId" to "not-a-uuid"),
                validWriteArguments() + ("energyClientRecordId" to 7),
            )

        invalidWriteArguments.forEach { arguments ->
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(arguments)
            }
        }

        val invalidLookupArguments =
            listOf(
                validLookupArguments() - "workoutClientRecordId",
                validLookupArguments() + ("workoutClientRecordId" to " "),
                validLookupArguments() + ("workoutClientRecordId" to "not-a-uuid"),
                validLookupArguments() + ("energyClientRecordId" to "not-a-uuid"),
            )

        invalidLookupArguments.forEach { arguments ->
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutLookupRequest.fromMap(arguments)
            }
        }
    }

    @Test
    fun parseWriteRequest_requiresIntegerVersionZero() {
        listOf<Any?>(1, -1, 0L + 1L, 0.0, "0", null).forEach { version ->
            val arguments = validWriteArguments().toMutableMap()
            if (version == null) {
                arguments.remove("clientRecordVersion")
            } else {
                arguments["clientRecordVersion"] = version
            }

            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(arguments)
            }
        }
    }

    @Test
    fun parseRequests_requireStrictlyIncreasingInstants() {
        val invalidRanges =
            listOf(
                WORKOUT_START.toEpochMilli() to WORKOUT_START.toEpochMilli(),
                WORKOUT_END.toEpochMilli() to WORKOUT_START.toEpochMilli(),
            )

        invalidRanges.forEach { (start, end) ->
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(
                    validWriteArguments() + ("startTime" to start) + ("endTime" to end)
                )
            }
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutLookupRequest.fromMap(
                    validLookupArguments() + ("startTime" to start) + ("endTime" to end)
                )
            }
        }
    }

    @Test
    fun parseRequests_rejectMissingOrWrongTypeTimes() {
        listOf(
                validWriteArguments() - "startTime",
                validWriteArguments() + ("startTime" to "2026-03-08T06:55:00Z"),
                validWriteArguments() + ("endTime" to 1.5),
            )
            .forEach { arguments ->
                assertThrows(WorkoutPayloadException::class.java) {
                    WorkoutWriteRequest.fromMap(arguments)
                }
            }

        listOf(
                validLookupArguments() - "endTime",
                validLookupArguments() + ("startTime" to 1.5),
            )
            .forEach { arguments ->
                assertThrows(WorkoutPayloadException::class.java) {
                    WorkoutLookupRequest.fromMap(arguments)
                }
            }
    }

    @Test
    fun parseWriteRequest_requiresEnergyAndEnergyIdTogether() {
        val energyWithoutId = validWriteArguments().toMutableMap().apply { remove("energyClientRecordId") }
        val idWithoutEnergy = validWriteArguments().toMutableMap().apply { remove("activeEnergyKcal") }

        assertThrows(WorkoutPayloadException::class.java) {
            WorkoutWriteRequest.fromMap(energyWithoutId)
        }
        assertThrows(WorkoutPayloadException::class.java) {
            WorkoutWriteRequest.fromMap(idWithoutEnergy)
        }

        val withoutEnergy =
            validWriteArguments().toMutableMap().apply {
                remove("energyClientRecordId")
                remove("activeEnergyKcal")
            }
        val request = WorkoutWriteRequest.fromMap(withoutEnergy)
        assertEquals(null, request.energyClientRecordId)
        assertEquals(null, request.activeEnergyKcal)
    }

    @Test
    fun parseWriteRequest_rejectsNonfiniteAndNonpositiveEnergy() {
        listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY).forEach { energy ->
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(validWriteArguments() + ("activeEnergyKcal" to energy))
            }
        }

        assertThrows(WorkoutPayloadException::class.java) {
            WorkoutWriteRequest.fromMap(validWriteArguments() + ("activeEnergyKcal" to "123.5"))
        }
    }

    @Test
    fun parseWriteRequest_acceptsBothZoneOffsetBoundaries() {
        listOf(-64_800, 64_800).forEach { offset ->
            val request =
                WorkoutWriteRequest.fromMap(
                    validWriteArguments() +
                        ("startZoneOffsetSeconds" to offset) +
                        ("endZoneOffsetSeconds" to offset)
                )
            assertEquals(offset, request.startZoneOffsetSeconds)
            assertEquals(offset, request.endZoneOffsetSeconds)
        }
    }

    @Test
    fun parseWriteRequest_rejectsInvalidOrWrongTypeOffsets() {
        listOf(-64_801, 64_801).forEach { offset ->
            listOf("startZoneOffsetSeconds", "endZoneOffsetSeconds").forEach { field ->
                assertThrows(WorkoutPayloadException::class.java) {
                    WorkoutWriteRequest.fromMap(validWriteArguments() + (field to offset))
                }
            }
        }

        listOf<Any?>(1.5, "0", null).forEach { offset ->
            val arguments = validWriteArguments().toMutableMap()
            if (offset == null) {
                arguments.remove("startZoneOffsetSeconds")
            } else {
                arguments["startZoneOffsetSeconds"] = offset
            }
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(arguments)
            }
        }
    }

    @Test
    fun parseWriteRequest_rejectsBlankOrWrongTypeTitle() {
        listOf<Any?>("", "  ", 7, null).forEach { title ->
            val arguments = validWriteArguments().toMutableMap()
            if (title == null) {
                arguments.remove("title")
            } else {
                arguments["title"] = title
            }
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(arguments)
            }
        }
    }

    @Test
    fun parseWriteRequest_rejectsUnknownProvenanceAndDevice() {
        listOf<Any?>("automatic", "ACTIVELY_RECORDED", 2, null).forEach { provenance ->
            val arguments = validWriteArguments().toMutableMap()
            if (provenance == null) {
                arguments.remove("recordingProvenance")
            } else {
                arguments["recordingProvenance"] = provenance
            }
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(arguments)
            }
        }

        listOf<Any?>("tablet", "PHONE", 1, null).forEach { device ->
            val arguments = validWriteArguments().toMutableMap()
            if (device == null) {
                arguments.remove("recordingDevice")
            } else {
                arguments["recordingDevice"] = device
            }
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(arguments)
            }
        }
    }

    @Test
    fun parseWriteRequest_rejectsUnsupportedOrWrongTypeActivity() {
        listOf<Any?>("BARRE", "strength_training", 7, null).forEach { activity ->
            val arguments = validWriteArguments().toMutableMap()
            if (activity == null) {
                arguments.remove("activityType")
            } else {
                arguments["activityType"] = activity
            }
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(arguments)
            }
        }
    }

    @Test
    fun workoutTypeMap_matchesTheExactDartAndroidSupportSet() {
        assertEquals(ANDROID_SUPPORTED_WORKOUT_TYPES, HealthConstants.workoutTypeMap.keys)
        assertEquals(
            ExerciseSessionRecord.EXERCISE_TYPE_ICE_HOCKEY,
            HealthConstants.workoutTypeMap["HOCKEY"],
        )
        assertEquals(
            ExerciseSessionRecord.EXERCISE_TYPE_SOCCER,
            HealthConstants.workoutTypeMap["SOCCER"],
        )
        assertEquals(
            ExerciseSessionRecord.EXERCISE_TYPE_WALKING,
            HealthConstants.workoutTypeMap["WALKING_TREADMILL"],
        )
        assertEquals(
            "WALKING",
            HealthConstants.workoutTypeReverseMap[ExerciseSessionRecord.EXERCISE_TYPE_WALKING],
        )
        assertFalse(HealthConstants.workoutTypeMap.containsKey("ARCHERY"))
        assertFalse(HealthConstants.workoutTypeMap.containsKey("CURLING"))
    }

    @Test
    fun parseRequests_rejectNonMapArguments() {
        listOf<Any?>(null, true, 1, "arguments", emptyList<Any?>()).forEach { value ->
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutWriteRequest.fromMap(value)
            }
            assertThrows(WorkoutPayloadException::class.java) {
                WorkoutLookupRequest.fromMap(value)
            }
        }
    }

    @Test
    fun writeResult_acceptsOnlyTheDartStatusEnergyMatrix() {
        WorkoutWriteStatus.entries.forEach { status ->
            EnergyWriteStatus.entries.forEach { energyStatus ->
                val pair = status to energyStatus
                if (pair in ALLOWED_WRITE_STATUS_PAIRS) {
                    val payload = validWritePayload(status, energyStatus)
                    assertEquals(status.wireName, payload.toMap()["status"])
                    assertEquals(energyStatus.wireName, payload.toMap()["energyStatus"])
                } else {
                    assertThrows(IllegalArgumentException::class.java) {
                        validWritePayload(status, energyStatus)
                    }
                }
            }
        }
    }

    @Test
    fun writeResult_rejectsEveryWrongIdPresenceAndCertaintyForEveryValidPair() {
        ALLOWED_WRITE_STATUS_PAIRS.forEach { (status, energyStatus) ->
            val valid = validWritePayload(status, energyStatus)

            assertThrows(IllegalArgumentException::class.java) {
                valid.copy(
                    workoutRecordId =
                        if (valid.workoutRecordId == null) "unexpected-workout" else null,
                )
            }
            assertThrows(IllegalArgumentException::class.java) {
                valid.copy(
                    energyRecordId =
                        if (valid.energyRecordId == null) "unexpected-energy" else null,
                )
            }
            SubmissionCertainty.entries
                .filterNot { it == valid.submissionCertainty }
                .forEach { wrongCertainty ->
                    assertThrows(IllegalArgumentException::class.java) {
                        valid.copy(submissionCertainty = wrongCertainty)
                    }
                }
        }

        assertThrows(IllegalArgumentException::class.java) {
            validWritePayload(WorkoutWriteStatus.UNAVAILABLE, EnergyWriteStatus.NOT_SUBMITTED)
                .copy(platformCode = " ")
        }
    }

    @Test
    fun writeResult_toMapUsesExplicitWireNamesAndAllFields() {
        val payload =
            WorkoutWriteResultPayload(
                status = WorkoutWriteStatus.WRITTEN,
                workoutRecordId = "native-workout",
                energyRecordId = "native-energy",
                energyStatus = EnergyWriteStatus.WRITTEN,
                retryable = false,
                submissionCertainty = SubmissionCertainty.SUBMITTED,
                platformCode = "insertComplete",
            )

        assertEquals(
            mapOf(
                "status" to "written",
                "workoutRecordId" to "native-workout",
                "energyRecordId" to "native-energy",
                "energyStatus" to "written",
                "retryable" to false,
                "submissionCertainty" to "submitted",
                "platformCode" to "insertComplete",
            ),
            payload.toMap(),
        )
    }

    @Test
    fun writeResult_invalidInputFactoryPreservesEnergyExpectation() {
        val full = WorkoutWriteResultPayload.invalidInput(energyExpected = true)
        val workoutOnly = WorkoutWriteResultPayload.invalidInput(energyExpected = false)

        assertEquals(WorkoutWriteStatus.INVALID_INPUT, full.status)
        assertEquals(EnergyWriteStatus.NOT_SUBMITTED, full.energyStatus)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, full.submissionCertainty)
        assertFalse(full.retryable)
        assertEquals("invalidInput", full.platformCode)

        assertEquals(WorkoutWriteStatus.INVALID_INPUT, workoutOnly.status)
        assertEquals(EnergyWriteStatus.NOT_EXPECTED, workoutOnly.energyStatus)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, workoutOnly.submissionCertainty)
        assertFalse(workoutOnly.retryable)
        assertEquals("invalidInput", workoutOnly.platformCode)
    }

    @Test
    fun componentLookup_requiresAnIdOnlyWhenPresent() {
        val present = ComponentLookupPayload(ComponentLookupStatus.PRESENT, "native-id")
        assertEquals(mapOf("status" to "present", "recordId" to "native-id"), present.toMap())

        listOf(
                ComponentLookupStatus.ABSENT,
                ComponentLookupStatus.UNAVAILABLE,
                ComponentLookupStatus.NOT_EXPECTED,
            )
            .forEach { status ->
                assertEquals(mapOf("status" to status.wireName, "recordId" to null), ComponentLookupPayload(status).toMap())
                assertThrows(IllegalArgumentException::class.java) {
                    ComponentLookupPayload(status, "forbidden-id")
                }
            }

        assertThrows(IllegalArgumentException::class.java) {
            ComponentLookupPayload(ComponentLookupStatus.PRESENT)
        }
        assertThrows(IllegalArgumentException::class.java) {
            ComponentLookupPayload(ComponentLookupStatus.PRESENT, " ")
        }
    }

    @Test
    fun lookupResult_acceptsOnlyTheExhaustiveDerivedStatus() {
        val workoutStatuses =
            listOf(
                ComponentLookupStatus.PRESENT,
                ComponentLookupStatus.ABSENT,
                ComponentLookupStatus.UNAVAILABLE,
            )

        workoutStatuses.forEach { workoutStatus ->
            ComponentLookupStatus.entries.forEach { energyStatus ->
                val workout = component(workoutStatus, "workout")
                val energy = component(energyStatus, "energy")
                val expected = expectedDerivedStatus(workoutStatus, energyStatus)

                val payload = WorkoutLookupResultPayload(workout, energy, expected)
                assertEquals(expected.wireName, payload.toMap()["derivedStatus"])

                WorkoutLookupStatus.entries.filter { it != expected }.forEach { wrong ->
                    assertThrows(IllegalArgumentException::class.java) {
                        WorkoutLookupResultPayload(workout, energy, wrong)
                    }
                }
            }
        }

        assertThrows(IllegalArgumentException::class.java) {
            WorkoutLookupResultPayload(
                ComponentLookupPayload(ComponentLookupStatus.NOT_EXPECTED),
                ComponentLookupPayload(ComponentLookupStatus.NOT_EXPECTED),
                WorkoutLookupStatus.ABSENT,
            )
        }
    }

    @Test
    fun lookupResult_toMapEncodesIndependentComponents() {
        val payload =
            WorkoutLookupResultPayload(
                workout = ComponentLookupPayload(ComponentLookupStatus.PRESENT, "native-workout"),
                energy = ComponentLookupPayload(ComponentLookupStatus.ABSENT),
                derivedStatus = WorkoutLookupStatus.WORKOUT_ONLY,
                platformCode = "lookupComplete",
            )

        assertEquals(
            mapOf(
                "workout" to mapOf("status" to "present", "recordId" to "native-workout"),
                "energy" to mapOf("status" to "absent", "recordId" to null),
                "derivedStatus" to "workoutOnly",
                "platformCode" to "lookupComplete",
            ),
            payload.toMap(),
        )
    }

    @Test
    fun authorizationSnapshot_enforcesAvailabilityCoherenceAndUniqueNonemptyTypes() {
        val supported =
            TypeAuthorizationPayload(
                type = HealthConstants.WORKOUT,
                read = AuthorizationState.AUTHORIZED,
                write = AuthorizationState.DENIED,
            )
        val snapshot = AuthorizationSnapshotPayload(available = true, types = listOf(supported))

        assertTrue(snapshot.available)
        assertEquals(
            mapOf(
                "available" to true,
                "types" to
                    listOf(
                        mapOf(
                            "type" to HealthConstants.WORKOUT,
                            "read" to "authorized",
                            "write" to "denied",
                        )
                    ),
                "platformCode" to null,
            ),
            snapshot.toMap(),
        )

        assertThrows(IllegalArgumentException::class.java) {
            AuthorizationSnapshotPayload(available = true, types = emptyList())
        }
        assertThrows(IllegalArgumentException::class.java) {
            AuthorizationSnapshotPayload(available = true, types = listOf(supported, supported))
        }
        assertThrows(IllegalArgumentException::class.java) {
            AuthorizationSnapshotPayload(
                available = true,
                types = listOf(supported.copy(read = AuthorizationState.UNAVAILABLE)),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            AuthorizationSnapshotPayload(available = false, types = listOf(supported))
        }

        val unavailable = AuthorizationSnapshotPayload.unavailable(listOf(HealthConstants.WORKOUT), "sdkUnavailable")
        assertFalse(unavailable.available)
        assertEquals("unavailable", unavailable.types.single().read.wireName)
        assertEquals("unavailable", unavailable.types.single().write.wireName)
    }

    private fun component(status: ComponentLookupStatus, id: String): ComponentLookupPayload =
        if (status == ComponentLookupStatus.PRESENT) ComponentLookupPayload(status, id)
        else ComponentLookupPayload(status)

    private fun expectedDerivedStatus(
        workout: ComponentLookupStatus,
        energy: ComponentLookupStatus,
    ): WorkoutLookupStatus =
        when {
            workout == ComponentLookupStatus.UNAVAILABLE || energy == ComponentLookupStatus.UNAVAILABLE ->
                WorkoutLookupStatus.UNAVAILABLE
            workout == ComponentLookupStatus.ABSENT && energy == ComponentLookupStatus.PRESENT ->
                WorkoutLookupStatus.INCONSISTENT
            workout == ComponentLookupStatus.ABSENT -> WorkoutLookupStatus.ABSENT
            workout == ComponentLookupStatus.PRESENT && energy == ComponentLookupStatus.PRESENT ->
                WorkoutLookupStatus.PRESENT
            else -> WorkoutLookupStatus.WORKOUT_ONLY
        }
}

private const val WORKOUT_CLIENT_ID = "018f8d7e-1111-7111-8111-111111111111"
private const val ENERGY_CLIENT_ID = "018f8d7e-2222-7222-8222-222222222222"
private val WORKOUT_START: Instant = Instant.parse("2026-03-08T06:55:00Z")
private val WORKOUT_END: Instant = Instant.parse("2026-03-08T07:25:00Z")

private val ALLOWED_WRITE_STATUS_PAIRS =
    setOf(
        WorkoutWriteStatus.WRITTEN to EnergyWriteStatus.WRITTEN,
        WorkoutWriteStatus.WRITTEN to EnergyWriteStatus.NOT_EXPECTED,
        WorkoutWriteStatus.ALREADY_PRESENT to EnergyWriteStatus.ALREADY_PRESENT,
        WorkoutWriteStatus.ALREADY_PRESENT to EnergyWriteStatus.ABSENT,
        WorkoutWriteStatus.ALREADY_PRESENT to EnergyWriteStatus.NOT_EXPECTED,
        WorkoutWriteStatus.WRITTEN_WITHOUT_ENERGY to EnergyWriteStatus.OMITTED_PERMISSION,
        WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION to EnergyWriteStatus.NOT_SUBMITTED,
        WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION to EnergyWriteStatus.NOT_EXPECTED,
        WorkoutWriteStatus.VERIFICATION_REQUIRED to EnergyWriteStatus.VERIFICATION_REQUIRED,
        WorkoutWriteStatus.VERIFICATION_REQUIRED to EnergyWriteStatus.OMITTED_PERMISSION,
        WorkoutWriteStatus.VERIFICATION_REQUIRED to EnergyWriteStatus.NOT_EXPECTED,
        WorkoutWriteStatus.INCONSISTENT_NATIVE_STATE to EnergyWriteStatus.ALREADY_PRESENT,
        WorkoutWriteStatus.TRANSIENT_FAILURE to EnergyWriteStatus.NOT_SUBMITTED,
        WorkoutWriteStatus.TRANSIENT_FAILURE to EnergyWriteStatus.NOT_EXPECTED,
        WorkoutWriteStatus.INVALID_INPUT to EnergyWriteStatus.NOT_SUBMITTED,
        WorkoutWriteStatus.INVALID_INPUT to EnergyWriteStatus.NOT_EXPECTED,
        WorkoutWriteStatus.UNAVAILABLE to EnergyWriteStatus.NOT_SUBMITTED,
        WorkoutWriteStatus.UNAVAILABLE to EnergyWriteStatus.NOT_EXPECTED,
    )

private val ANDROID_SUPPORTED_WORKOUT_TYPES =
    setOf(
        "AMERICAN_FOOTBALL",
        "AUSTRALIAN_FOOTBALL",
        "BADMINTON",
        "BASEBALL",
        "BASKETBALL",
        "BIKING",
        "BIKING_STATIONARY",
        "BOXING",
        "CALISTHENICS",
        "CARDIO_DANCE",
        "CRICKET",
        "CROSS_COUNTRY_SKIING",
        "DANCING",
        "DOWNHILL_SKIING",
        "ELLIPTICAL",
        "FENCING",
        "FRISBEE_DISC",
        "GOLF",
        "GUIDED_BREATHING",
        "GYMNASTICS",
        "HANDBALL",
        "HIGH_INTENSITY_INTERVAL_TRAINING",
        "HIKING",
        "HOCKEY",
        "ICE_SKATING",
        "MARTIAL_ARTS",
        "OTHER",
        "PARAGLIDING",
        "PILATES",
        "RACQUETBALL",
        "ROCK_CLIMBING",
        "ROWING",
        "ROWING_MACHINE",
        "RUGBY",
        "RUNNING",
        "RUNNING_TREADMILL",
        "SAILING",
        "SCUBA_DIVING",
        "SKATING",
        "SKIING",
        "SNOWBOARDING",
        "SNOWSHOEING",
        "SOCCER",
        "SOCIAL_DANCE",
        "SOFTBALL",
        "SQUASH",
        "STAIR_CLIMBING",
        "STAIR_CLIMBING_MACHINE",
        "STRENGTH_TRAINING",
        "SURFING",
        "SWIMMING_OPEN_WATER",
        "SWIMMING_POOL",
        "TABLE_TENNIS",
        "TENNIS",
        "VOLLEYBALL",
        "WALKING",
        "WALKING_TREADMILL",
        "WATER_POLO",
        "WEIGHTLIFTING",
        "WHEELCHAIR",
        "WHEELCHAIR_RUN_PACE",
        "WHEELCHAIR_WALK_PACE",
        "YOGA",
    )

private fun validWriteArguments(): Map<String, Any?> =
    mapOf(
        "workoutClientRecordId" to WORKOUT_CLIENT_ID,
        "energyClientRecordId" to ENERGY_CLIENT_ID,
        "clientRecordVersion" to 0,
        "activityType" to "STRENGTH_TRAINING",
        "startTime" to WORKOUT_START.toEpochMilli(),
        "endTime" to WORKOUT_END.toEpochMilli(),
        "startZoneOffsetSeconds" to -18_000,
        "endZoneOffsetSeconds" to -14_400,
        "activeEnergyKcal" to 123.5,
        "title" to "Plates Workout",
        "recordingProvenance" to "activelyRecorded",
        "recordingDevice" to "phone",
    )

private fun validLookupArguments(): Map<String, Any?> =
    mapOf(
        "workoutClientRecordId" to WORKOUT_CLIENT_ID,
        "energyClientRecordId" to ENERGY_CLIENT_ID,
        "startTime" to WORKOUT_START.toEpochMilli(),
        "endTime" to WORKOUT_END.toEpochMilli(),
    )

private fun validWritePayload(
    status: WorkoutWriteStatus,
    energyStatus: EnergyWriteStatus,
): WorkoutWriteResultPayload {
    val workoutRecordId =
        when (status) {
            WorkoutWriteStatus.WRITTEN,
            WorkoutWriteStatus.ALREADY_PRESENT,
            WorkoutWriteStatus.WRITTEN_WITHOUT_ENERGY -> "native-workout"
            WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION,
            WorkoutWriteStatus.VERIFICATION_REQUIRED,
            WorkoutWriteStatus.INCONSISTENT_NATIVE_STATE,
            WorkoutWriteStatus.TRANSIENT_FAILURE,
            WorkoutWriteStatus.INVALID_INPUT,
            WorkoutWriteStatus.UNAVAILABLE -> null
        }
    val energyRecordId =
        when (energyStatus) {
            EnergyWriteStatus.WRITTEN,
            EnergyWriteStatus.ALREADY_PRESENT -> "native-energy"
            EnergyWriteStatus.NOT_EXPECTED,
            EnergyWriteStatus.OMITTED_PERMISSION,
            EnergyWriteStatus.ABSENT,
            EnergyWriteStatus.NOT_SUBMITTED,
            EnergyWriteStatus.VERIFICATION_REQUIRED -> null
        }
    val certainty =
        when (status) {
            WorkoutWriteStatus.WRITTEN,
            WorkoutWriteStatus.ALREADY_PRESENT,
            WorkoutWriteStatus.WRITTEN_WITHOUT_ENERGY,
            WorkoutWriteStatus.INCONSISTENT_NATIVE_STATE -> SubmissionCertainty.SUBMITTED
            WorkoutWriteStatus.VERIFICATION_REQUIRED -> SubmissionCertainty.MAY_HAVE_SUBMITTED
            WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION,
            WorkoutWriteStatus.TRANSIENT_FAILURE,
            WorkoutWriteStatus.INVALID_INPUT,
            WorkoutWriteStatus.UNAVAILABLE -> SubmissionCertainty.NOT_SUBMITTED
        }

    return WorkoutWriteResultPayload(
        status = status,
        workoutRecordId = workoutRecordId,
        energyRecordId = energyRecordId,
        energyStatus = energyStatus,
        retryable = false,
        submissionCertainty = certainty,
    )
}
