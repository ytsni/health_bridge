package cachet.plugins.health

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HealthPluginWorkoutRoutingTest {
    @Test
    fun writeWorkoutData_unavailableReturnsStructuredResultWithoutInitializedHelpers() {
        val result = RoutingResult()

        HealthPlugin().onMethodCall(MethodCall("writeWorkoutData", validWriteArguments()), result)

        assertEquals(1, result.successes.size)
        assertEquals("unavailable", result.successMap()["status"])
        assertEquals("notSubmitted", result.successMap()["energyStatus"])
        assertEquals("notSubmitted", result.successMap()["submissionCertainty"])
        assertEquals("healthConnectUnavailable", result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun writeWorkoutData_unavailableWithoutEnergyReportsNotExpected() {
        val result = RoutingResult()

        HealthPlugin().onMethodCall(
            MethodCall("writeWorkoutData", validWriteArguments(includeEnergy = false)),
            result,
        )

        assertEquals("unavailable", result.successMap()["status"])
        assertEquals("notExpected", result.successMap()["energyStatus"])
        assertEquals("notSubmitted", result.successMap()["submissionCertainty"])
        assertEquals("healthConnectUnavailable", result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun writeWorkoutData_availableRoutesOnlyThroughDedicatedMethodHandler() = runTest {
        val operations = RoutingOperations()
        val plugin = HealthPlugin()
        setField(plugin, "healthConnectAvailable", true)
        setField(plugin, "workoutMethodHandler", HealthWorkoutMethodHandler(this, operations))
        val result = RoutingResult()

        plugin.onMethodCall(MethodCall("writeWorkoutData", validWriteArguments()), result)
        advanceUntilIdle()

        assertEquals(1, operations.writeCalls)
        assertEquals(WORKOUT_CLIENT_ID, operations.lastRequest?.workoutClientRecordId)
        assertEquals(1, result.successes.size)
        assertEquals("written", result.successMap()["status"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun lookupWorkoutData_unavailableReturnsStructuredExpectedComponents() {
        val result = RoutingResult()

        HealthPlugin().onMethodCall(MethodCall("lookupWorkoutData", validLookupArguments()), result)

        assertEquals("unavailable", result.componentMap("workout")["status"])
        assertEquals("unavailable", result.componentMap("energy")["status"])
        assertEquals("unavailable", result.successMap()["derivedStatus"])
        assertEquals("healthConnectUnavailable", result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun lookupWorkoutData_unavailableWithoutEnergyReportsNotExpected() {
        val result = RoutingResult()

        HealthPlugin().onMethodCall(
            MethodCall("lookupWorkoutData", validLookupArguments(includeEnergy = false)),
            result,
        )

        assertEquals("unavailable", result.componentMap("workout")["status"])
        assertEquals("notExpected", result.componentMap("energy")["status"])
        assertEquals("unavailable", result.successMap()["derivedStatus"])
        assertEquals("healthConnectUnavailable", result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun lookupWorkoutData_unavailableMalformedPayloadStaysTyped() {
        val result = RoutingResult()
        val malformed =
            validLookupArguments() + ("endTime" to START.toEpochMilli())

        HealthPlugin().onMethodCall(MethodCall("lookupWorkoutData", malformed), result)

        assertEquals("unavailable", result.componentMap("workout")["status"])
        assertEquals("unavailable", result.componentMap("energy")["status"])
        assertEquals("unavailable", result.successMap()["derivedStatus"])
        assertEquals("invalidInput", result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun lookupWorkoutData_availableRoutesOnlyThroughDedicatedMethodHandler() = runTest {
        val operations = RoutingOperations()
        val plugin = HealthPlugin()
        setField(plugin, "healthConnectAvailable", true)
        setField(plugin, "workoutMethodHandler", HealthWorkoutMethodHandler(this, operations))
        val result = RoutingResult()

        plugin.onMethodCall(MethodCall("lookupWorkoutData", validLookupArguments()), result)
        advanceUntilIdle()

        assertEquals(1, operations.lookupCalls)
        assertEquals(WORKOUT_CLIENT_ID, operations.lastLookupRequest?.workoutClientRecordId)
        assertEquals(ENERGY_CLIENT_ID, operations.lastLookupRequest?.energyClientRecordId)
        assertEquals("present", result.successMap()["derivedStatus"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun lookupWorkoutData_availableMalformedPayloadReturnsTypedInvalidInput() = runTest {
        val operations = RoutingOperations()
        val plugin = HealthPlugin()
        setField(plugin, "healthConnectAvailable", true)
        setField(plugin, "workoutMethodHandler", HealthWorkoutMethodHandler(this, operations))
        val result = RoutingResult()

        plugin.onMethodCall(
            MethodCall(
                "lookupWorkoutData",
                validLookupArguments() + ("workoutClientRecordId" to "not-a-uuid"),
            ),
            result,
        )
        advanceUntilIdle()

        assertEquals(0, operations.lookupCalls)
        assertEquals("unavailable", result.successMap()["derivedStatus"])
        assertEquals("invalidInput", result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun lookupBodyMassData_unavailableReturnsStructuredResultWithoutInitializedHelpers() {
        val result = RoutingResult()

        HealthPlugin().onMethodCall(MethodCall("lookupBodyMassData", validBodyMassArguments()), result)

        assertEquals("unavailable", result.successMap()["status"])
        assertNull(result.successMap()["recordId"])
        assertEquals("healthConnectUnavailable", result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun lookupBodyMassData_unavailableMalformedPayloadStaysTyped() {
        val result = RoutingResult()

        HealthPlugin().onMethodCall(
            MethodCall("lookupBodyMassData", validBodyMassArguments() + ("extra" to true)),
            result,
        )

        assertEquals("unavailable", result.successMap()["status"])
        assertEquals("invalidInput", result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun lookupBodyMassData_availableRoutesOnlyThroughDedicatedMethodHandler() = runTest {
        val operations = BodyMassRoutingOperations()
        val plugin = HealthPlugin()
        setField(plugin, "healthConnectAvailable", true)
        setField(plugin, "bodyMassMethodHandler", HealthBodyMassMethodHandler(this, operations))
        val result = RoutingResult()

        plugin.onMethodCall(MethodCall("lookupBodyMassData", validBodyMassArguments()), result)
        advanceUntilIdle()

        assertEquals(1, operations.lookupCalls)
        assertEquals(BODY_MASS_CLIENT_ID, operations.lastRequest?.clientRecordId)
        assertEquals(BODY_MASS_MEASURED_AT, operations.lastRequest?.measuredAt)
        assertEquals("present", result.successMap()["status"])
        assertEquals("native-weight", result.successMap()["recordId"])
        assertNull(result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun lookupBodyMassData_availableRejectsAnyArgumentsBeyondTheExactPair() = runTest {
        val operations = BodyMassRoutingOperations()
        val plugin = HealthPlugin()
        setField(plugin, "healthConnectAvailable", true)
        setField(plugin, "bodyMassMethodHandler", HealthBodyMassMethodHandler(this, operations))
        val result = RoutingResult()

        plugin.onMethodCall(
            MethodCall("lookupBodyMassData", validBodyMassArguments() + ("unexpected" to true)),
            result,
        )
        advanceUntilIdle()

        assertEquals(0, operations.lookupCalls)
        assertEquals("unavailable", result.successMap()["status"])
        assertEquals("invalidInput", result.successMap()["platformCode"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun getAuthorizationSnapshot_unavailableReturnsExactUnavailableTypesOnce() {
        val result = RoutingResult()

        HealthPlugin().onMethodCall(
            MethodCall("getAuthorizationSnapshot", validAuthorizationArguments()),
            result,
        )

        assertEquals(false, result.successMap()["available"])
        assertEquals("healthConnectUnavailable", result.successMap()["platformCode"])
        val types = result.successMap()["types"] as List<*>
        assertEquals(2, types.size)
        assertAuthorizationType(
            types[0],
            HealthConstants.WORKOUT,
            read = "unavailable",
            write = "unavailable",
        )
        assertAuthorizationType(
            types[1],
            HealthConstants.ACTIVE_ENERGY_BURNED,
            read = "unavailable",
            write = "unavailable",
        )
        result.assertOnlyOneSuccess()
    }

    @Test
    fun getAuthorizationSnapshot_availableRoutesOnlyThroughDedicatedMethodHandler() = runTest {
        val operations = RoutingOperations()
        val plugin = HealthPlugin()
        setField(plugin, "healthConnectAvailable", true)
        setField(plugin, "workoutMethodHandler", HealthWorkoutMethodHandler(this, operations))
        val result = RoutingResult()

        plugin.onMethodCall(
            MethodCall("getAuthorizationSnapshot", validAuthorizationArguments()),
            result,
        )
        advanceUntilIdle()

        assertEquals(1, operations.authorizationCalls)
        assertEquals(
            listOf(HealthConstants.WORKOUT, HealthConstants.ACTIVE_ENERGY_BURNED),
            operations.lastAuthorizationTypes,
        )
        assertEquals(true, result.successMap()["available"])
        result.assertOnlyOneSuccess()
    }

    @Test
    fun getAuthorizationSnapshot_availableMalformedPayloadReturnsOneErrorWithoutOperation() =
        runTest {
            val operations = RoutingOperations()
            val plugin = HealthPlugin()
            setField(plugin, "healthConnectAvailable", true)
            setField(plugin, "workoutMethodHandler", HealthWorkoutMethodHandler(this, operations))
            val result = RoutingResult()

            plugin.onMethodCall(
                MethodCall(
                    "getAuthorizationSnapshot",
                    mapOf("types" to listOf(HealthConstants.WORKOUT, 1)),
                ),
                result,
            )
            advanceUntilIdle()

            assertEquals(0, operations.authorizationCalls)
            result.assertOnlyOneError("invalidInput")
        }

    @Test
    fun getAuthorizationSnapshot_unavailableMalformedPayloadReturnsOneError() {
        val result = RoutingResult()

        HealthPlugin().onMethodCall(
            MethodCall("getAuthorizationSnapshot", mapOf("types" to emptyList<String>())),
            result,
        )

        result.assertOnlyOneError("invalidInput")
    }
}

private class RoutingOperations : HealthWorkoutOperationsContract {
    var writeCalls = 0
        private set
    var lastRequest: WorkoutWriteRequest? = null
        private set
    var lookupCalls = 0
        private set
    var lastLookupRequest: WorkoutLookupRequest? = null
        private set
    var authorizationCalls = 0
        private set
    var lastAuthorizationTypes: List<String>? = null
        private set

    override suspend fun write(request: WorkoutWriteRequest): WorkoutWriteResultPayload {
        writeCalls += 1
        lastRequest = request
        return WorkoutWriteResultPayload(
            status = WorkoutWriteStatus.WRITTEN,
            workoutRecordId = "native-workout",
            energyRecordId = "native-energy",
            energyStatus = EnergyWriteStatus.WRITTEN,
            retryable = false,
            submissionCertainty = SubmissionCertainty.SUBMITTED,
        )
    }

    override suspend fun lookup(request: WorkoutLookupRequest): WorkoutLookupResultPayload {
        lookupCalls += 1
        lastLookupRequest = request
        return WorkoutLookupResultPayload(
            workout = ComponentLookupPayload(ComponentLookupStatus.PRESENT, "native-workout"),
            energy = ComponentLookupPayload(ComponentLookupStatus.PRESENT, "native-energy"),
            derivedStatus = WorkoutLookupStatus.PRESENT,
        )
    }

    override suspend fun authorizationSnapshot(types: List<String>): AuthorizationSnapshotPayload {
        authorizationCalls += 1
        lastAuthorizationTypes = types
        return AuthorizationSnapshotPayload(
            available = true,
            types =
                types.map { type ->
                    TypeAuthorizationPayload(
                        type = type,
                        read = AuthorizationState.AUTHORIZED,
                        write = AuthorizationState.AUTHORIZED,
                    )
                },
        )
    }
}

private class BodyMassRoutingOperations : HealthBodyMassOperationsContract {
    var lookupCalls = 0
        private set
    var lastRequest: BodyMassLookupRequest? = null
        private set

    override suspend fun lookup(request: BodyMassLookupRequest): BodyMassLookupResultPayload {
        lookupCalls += 1
        lastRequest = request
        return BodyMassLookupResultPayload(
            status = BodyMassLookupStatus.PRESENT,
            recordId = "native-weight",
        )
    }
}

private class RoutingResult : Result {
    val successes = mutableListOf<Any?>()
    val errors = mutableListOf<Any?>()
    var notImplementedCalls = 0

    override fun success(result: Any?) {
        successes += result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        errors.add(listOf(errorCode, errorMessage, errorDetails))
    }

    override fun notImplemented() {
        notImplementedCalls += 1
    }

    @Suppress("UNCHECKED_CAST")
    fun successMap(): Map<String, Any?> = successes.single() as Map<String, Any?>

    @Suppress("UNCHECKED_CAST")
    fun componentMap(key: String): Map<String, Any?> = successMap()[key] as Map<String, Any?>

    fun assertOnlyOneSuccess() {
        assertTrue(errors.isEmpty())
        assertEquals(0, notImplementedCalls)
        assertEquals(1, successes.size)
    }

    fun assertOnlyOneError(expectedCode: String) {
        assertTrue(successes.isEmpty())
        assertEquals(0, notImplementedCalls)
        assertEquals(1, errors.size)
        assertEquals(expectedCode, (errors.single() as List<*>)[0])
    }
}

private fun assertAuthorizationType(value: Any?, type: String, read: String, write: String) {
    val map = value as Map<*, *>
    assertEquals(type, map["type"])
    assertEquals(read, map["read"])
    assertEquals(write, map["write"])
}

private fun setField(target: Any, name: String, value: Any) {
    target.javaClass.getDeclaredField(name).apply {
        isAccessible = true
        set(target, value)
    }
}

private const val WORKOUT_CLIENT_ID = "018f8d7e-1111-7111-8111-111111111111"
private const val ENERGY_CLIENT_ID = "018f8d7e-2222-7222-8222-222222222222"
private val START = Instant.parse("2026-03-08T06:55:00Z")
private val END = Instant.parse("2026-03-08T07:25:00Z")

private fun validWriteArguments(includeEnergy: Boolean = true): Map<String, Any?> {
    val arguments =
        mutableMapOf<String, Any?>(
            "workoutClientRecordId" to WORKOUT_CLIENT_ID,
            "clientRecordVersion" to 0,
            "activityType" to "STRENGTH_TRAINING",
            "startTime" to START.toEpochMilli(),
            "endTime" to END.toEpochMilli(),
            "startZoneOffsetSeconds" to -18_000,
            "endZoneOffsetSeconds" to -14_400,
            "title" to "Plates Workout",
            "recordingProvenance" to "activelyRecorded",
            "recordingDevice" to "phone",
        )
    if (includeEnergy) {
        arguments["energyClientRecordId"] = ENERGY_CLIENT_ID
        arguments["activeEnergyKcal"] = 123.5
    }
    return arguments
}

private fun validLookupArguments(includeEnergy: Boolean = true): Map<String, Any?> {
    val arguments =
        mutableMapOf<String, Any?>(
            "workoutClientRecordId" to WORKOUT_CLIENT_ID,
            "startTime" to START.toEpochMilli(),
            "endTime" to END.toEpochMilli(),
        )
    if (includeEnergy) {
        arguments["energyClientRecordId"] = ENERGY_CLIENT_ID
    }
    return arguments
}

private fun validBodyMassArguments(): Map<String, Any?> =
    mapOf(
        "clientRecordId" to BODY_MASS_CLIENT_ID,
        "measuredAt" to BODY_MASS_MEASURED_AT.toEpochMilli(),
    )

private fun validAuthorizationArguments(): Map<String, Any?> =
    mapOf(
        "types" to listOf(HealthConstants.WORKOUT, HealthConstants.ACTIVE_ENERGY_BURNED)
    )

private const val BODY_MASS_CLIENT_ID = "018f8d7e-3333-7333-8333-333333333333"
private val BODY_MASS_MEASURED_AT = Instant.parse("2026-07-20T12:00:00Z")
