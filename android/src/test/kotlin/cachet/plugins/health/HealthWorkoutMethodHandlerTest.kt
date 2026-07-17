package cachet.plugins.health

import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HealthWorkoutMethodHandlerTest {
    @Test
    fun write_successForwardsParsedRequestAndCompletesExactlyOnce() = runTest {
        val operations = FakeHealthWorkoutOperations()
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(this, operations)

        handler.write(validWriteArguments(), result)
        advanceUntilIdle()

        assertEquals(1, operations.writeCalls)
        assertEquals(WORKOUT_CLIENT_ID, operations.lastWriteRequest?.workoutClientRecordId)
        assertEquals(ENERGY_CLIENT_ID, operations.lastWriteRequest?.energyClientRecordId)
        assertEquals(1, result.successes.size)
        assertEquals("written", result.successMap()["status"])
        assertEquals("submitted", result.successMap()["submissionCertainty"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun lookup_successForwardsParsedRequestAndCompletesExactlyOnce() = runTest {
        val operations = FakeHealthWorkoutOperations()
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(this, operations)

        handler.lookup(validLookupArguments(), result)
        advanceUntilIdle()

        assertEquals(1, operations.lookupCalls)
        assertEquals(WORKOUT_CLIENT_ID, operations.lastLookupRequest?.workoutClientRecordId)
        assertEquals(ENERGY_CLIENT_ID, operations.lastLookupRequest?.energyClientRecordId)
        assertEquals(1, result.successes.size)
        assertEquals("workoutOnly", result.successMap()["derivedStatus"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun authorizationSnapshot_successForwardsExactTypesAndCompletesExactlyOnce() = runTest {
        val operations = FakeHealthWorkoutOperations()
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(this, operations)

        handler.authorizationSnapshot(
            mapOf("types" to listOf(HealthConstants.WORKOUT, HealthConstants.ACTIVE_ENERGY_BURNED)),
            result,
        )
        advanceUntilIdle()

        assertEquals(1, operations.authorizationCalls)
        assertEquals(
            listOf(HealthConstants.WORKOUT, HealthConstants.ACTIVE_ENERGY_BURNED),
            operations.lastAuthorizationTypes,
        )
        assertEquals(1, result.successes.size)
        assertEquals(true, result.successMap()["available"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun write_parserFailureReturnsInvalidInputOnceWithoutLaunchingOperation() = runTest {
        val operations = FakeHealthWorkoutOperations()
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(this, operations)

        handler.write(validWriteArguments() + ("workoutClientRecordId" to "not-a-uuid"), result)
        advanceUntilIdle()

        assertEquals(0, operations.writeCalls)
        assertEquals(1, result.successes.size)
        assertEquals("invalidInput", result.successMap()["status"])
        assertEquals("notSubmitted", result.successMap()["energyStatus"])
        assertEquals("notSubmitted", result.successMap()["submissionCertainty"])
        assertEquals("invalidInput", result.successMap()["platformCode"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun write_noEnergyParserFailureReturnsNotExpectedOnceWithoutLaunchingOperation() = runTest {
        val operations = FakeHealthWorkoutOperations()
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(this, operations)
        val arguments =
            validWriteArguments().toMutableMap().apply {
                remove("energyClientRecordId")
                remove("activeEnergyKcal")
                this["workoutClientRecordId"] = "not-a-uuid"
            }

        handler.write(arguments, result)
        advanceUntilIdle()

        assertEquals(0, operations.writeCalls)
        assertEquals(1, result.successes.size)
        assertEquals("invalidInput", result.successMap()["status"])
        assertEquals("notExpected", result.successMap()["energyStatus"])
        assertEquals("notSubmitted", result.successMap()["submissionCertainty"])
        assertEquals("invalidInput", result.successMap()["platformCode"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun lookup_parserFailureReturnsUnavailableOnceWithoutLaunchingOperation() = runTest {
        val operations = FakeHealthWorkoutOperations()
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(this, operations)

        handler.lookup(validLookupArguments() + ("endTime" to WORKOUT_START.toEpochMilli()), result)
        advanceUntilIdle()

        assertEquals(0, operations.lookupCalls)
        assertEquals(1, result.successes.size)
        assertEquals("unavailable", result.componentMap("workout")["status"])
        assertEquals("unavailable", result.componentMap("energy")["status"])
        assertEquals("unavailable", result.successMap()["derivedStatus"])
        assertEquals("invalidInput", result.successMap()["platformCode"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun write_thrownSuspendOperationReturnsUnavailableExactlyOnce() = runTest {
        val operations = FakeHealthWorkoutOperations(writeFailure = IllegalStateException("boom"))
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(this, operations)

        handler.write(validWriteArguments(), result)
        advanceUntilIdle()

        assertEquals(1, operations.writeCalls)
        assertEquals(1, result.successes.size)
        assertEquals("unavailable", result.successMap()["status"])
        assertEquals("notSubmitted", result.successMap()["submissionCertainty"])
        assertEquals("unexpectedFailure", result.successMap()["platformCode"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun lookup_thrownSuspendOperationReturnsUnavailableExactlyOnce() = runTest {
        val operations = FakeHealthWorkoutOperations(lookupFailure = IllegalStateException("boom"))
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(this, operations)

        handler.lookup(validLookupArguments(), result)
        advanceUntilIdle()

        assertEquals(1, operations.lookupCalls)
        assertEquals(1, result.successes.size)
        assertEquals("unavailable", result.successMap()["derivedStatus"])
        assertEquals("unexpectedFailure", result.successMap()["platformCode"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun authorizationSnapshot_thrownSuspendOperationReturnsUnavailableExactlyOnce() = runTest {
        val operations = FakeHealthWorkoutOperations(authorizationFailure = IllegalStateException("boom"))
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(this, operations)

        handler.authorizationSnapshot(mapOf("types" to listOf(HealthConstants.WORKOUT)), result)
        advanceUntilIdle()

        assertEquals(1, operations.authorizationCalls)
        assertEquals(1, result.successes.size)
        assertEquals(false, result.successMap()["available"])
        assertEquals("unexpectedFailure", result.successMap()["platformCode"])
        val types = result.successMap()["types"] as List<*>
        val type = types.single() as Map<*, *>
        assertEquals("unavailable", type["read"])
        assertEquals("unavailable", type["write"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun alreadyCanceledScopeReturnsOperationCanceledOnceAndDoesNotHang() = runTest {
        val canceledJob = Job().apply { cancel() }
        val canceledScope = CoroutineScope(StandardTestDispatcher(testScheduler) + canceledJob)
        val operations = FakeHealthWorkoutOperations()
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(canceledScope, operations)

        handler.write(validWriteArguments(), result)
        advanceUntilIdle()

        assertEquals(0, operations.writeCalls)
        assertEquals(1, result.successes.size)
        assertEquals("unavailable", result.successMap()["status"])
        assertEquals("operationCanceled", result.successMap()["platformCode"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun cancellationRaceStillCompletesResultOnlyOnce() = runTest {
        val operationJob = Job()
        val operationScope = CoroutineScope(StandardTestDispatcher(testScheduler) + operationJob)
        val operations = FakeHealthWorkoutOperations(yieldBeforeWrite = true)
        val result = RecordingResult()
        val handler = HealthWorkoutMethodHandler(operationScope, operations)

        handler.write(validWriteArguments(), result)
        operationJob.cancel()
        advanceUntilIdle()

        assertTrue(result.successes.isNotEmpty())
        assertEquals(1, result.successes.size)
        assertEquals("operationCanceled", result.successMap()["platformCode"])
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun authorizationSnapshot_rejectsEmptyDuplicateAndNonStringTypesWithoutOperation() = runTest {
        val invalidArguments =
            listOf<Any?>(
                emptyMap<String, Any?>(),
                mapOf("types" to emptyList<String>()),
                mapOf("types" to listOf(HealthConstants.WORKOUT, HealthConstants.WORKOUT)),
                mapOf("types" to listOf(HealthConstants.WORKOUT, 1)),
                mapOf("types" to "WORKOUT"),
            )

        invalidArguments.forEach { arguments ->
            val operations = FakeHealthWorkoutOperations()
            val result = RecordingResult()
            val handler = HealthWorkoutMethodHandler(this, operations)

            handler.authorizationSnapshot(arguments, result)
            advanceUntilIdle()

            assertEquals(0, operations.authorizationCalls)
            assertEquals(1, result.errors.size)
            assertEquals("invalidInput", result.errors.single().code)
            assertTrue(result.successes.isEmpty())
        }
    }

    @Test
    fun requestCompletion_emptyAndDuplicateCallbacksCompleteTrueExactlyOnce() {
        val completion = HealthConnectPermissionRequestCompletion()
        val result = RecordingResult()

        assertTrue(completion.begin(result))
        completion.completeFromCallback(emptySet())
        completion.completeFromCallback(emptySet())

        assertEquals(listOf(true), result.successes)
        result.assertNoErrorOrNotImplemented()
    }

    @Test
    fun requestCompletion_immediateFailureClearsPendingAndIgnoresStaleCallback() {
        val completion = HealthConnectPermissionRequestCompletion()
        val failedResult = RecordingResult()

        assertTrue(completion.begin(failedResult))
        completion.failImmediately()
        completion.completeFromCallback(emptySet())

        assertEquals(listOf(false), failedResult.successes)
        failedResult.assertNoErrorOrNotImplemented()

        val nextResult = RecordingResult()
        assertTrue(completion.begin(nextResult))
        completion.completeFromCallback(emptySet())

        assertEquals(listOf(true), nextResult.successes)
        nextResult.assertNoErrorOrNotImplemented()
    }

    @Test
    fun requestCompletion_rejectsConcurrentBeginWithoutReplacingPendingResult() {
        val completion = HealthConnectPermissionRequestCompletion()
        val firstResult = RecordingResult()
        val secondResult = RecordingResult()

        assertTrue(completion.begin(firstResult))
        assertFalse(completion.begin(secondResult))
        completion.completeFromCallback(emptySet())

        assertEquals(listOf(true), firstResult.successes)
        assertTrue(secondResult.successes.isEmpty())
        firstResult.assertNoErrorOrNotImplemented()
        assertTrue(secondResult.errors.isEmpty())
        assertEquals(0, secondResult.notImplementedCalls)
    }

    @Test
    fun requestLifecycle_configurationDetachPreservesPendingAcrossReattach() {
        val lifecycle = HealthConnectPermissionRequestLifecycle()
        val oldLauncher = RecordingPermissionLauncher()
        val pendingResult = RecordingResult()
        lifecycle.attach(oldLauncher)

        lifecycle.launch(setOf("write-workout"), pendingResult)
        lifecycle.detachForConfigurationChange()

        assertEquals(listOf(setOf("write-workout")), oldLauncher.launches)
        assertEquals(0, oldLauncher.unregisterCalls)
        assertTrue(pendingResult.successes.isEmpty())

        val newLauncher = RecordingPermissionLauncher()
        lifecycle.attach(newLauncher)
        lifecycle.completeFromCallback(emptySet())
        lifecycle.completeFromCallback(emptySet())
        assertEquals(listOf(true), pendingResult.successes)

        val nextResult = RecordingResult()
        lifecycle.launch(setOf("write-energy"), nextResult)
        lifecycle.completeFromCallback(emptySet())

        assertEquals(listOf(setOf("write-energy")), newLauncher.launches)
        assertEquals(listOf(true), nextResult.successes)
    }

    @Test
    fun requestLifecycle_permanentDetachFailsPendingAndAllowsLaterNewRequest() {
        val lifecycle = HealthConnectPermissionRequestLifecycle()
        val oldLauncher =
            RecordingPermissionLauncher(
                unregisterFailure = IllegalStateException("activity already destroyed")
            )
        val detachedResult = RecordingResult()
        lifecycle.attach(oldLauncher)
        lifecycle.launch(setOf("write-workout"), detachedResult)

        lifecycle.detachPermanently()
        lifecycle.completeFromCallback(emptySet())

        assertEquals(1, oldLauncher.unregisterCalls)
        assertEquals(listOf(false), detachedResult.successes)

        val newLauncher = RecordingPermissionLauncher()
        val newResult = RecordingResult()
        lifecycle.attach(newLauncher)
        lifecycle.launch(setOf("write-workout"), newResult)
        lifecycle.completeFromCallback(emptySet())

        assertEquals(listOf(setOf("write-workout")), newLauncher.launches)
        assertEquals(listOf(true), newResult.successes)
    }
}

private class RecordingPermissionLauncher(
    private val unregisterFailure: Exception? = null,
) : HealthConnectPermissionLauncher {
    val launches = mutableListOf<Set<String>>()
    var unregisterCalls = 0
        private set

    override fun launch(permissions: Set<String>) {
        launches += permissions
    }

    override fun unregister() {
        unregisterCalls += 1
        unregisterFailure?.let { throw it }
    }
}

private class FakeHealthWorkoutOperations(
    private val writeFailure: Throwable? = null,
    private val lookupFailure: Throwable? = null,
    private val authorizationFailure: Throwable? = null,
    private val yieldBeforeWrite: Boolean = false,
) : HealthWorkoutOperationsContract {
    var writeCalls: Int = 0
        private set
    var lookupCalls: Int = 0
        private set
    var authorizationCalls: Int = 0
        private set
    var lastWriteRequest: WorkoutWriteRequest? = null
        private set
    var lastLookupRequest: WorkoutLookupRequest? = null
        private set
    var lastAuthorizationTypes: List<String>? = null
        private set

    override suspend fun write(request: WorkoutWriteRequest): WorkoutWriteResultPayload {
        writeCalls += 1
        lastWriteRequest = request
        if (yieldBeforeWrite) yield()
        writeFailure?.let { throw it }
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
        lookupFailure?.let { throw it }
        return WorkoutLookupResultPayload(
            workout = ComponentLookupPayload(ComponentLookupStatus.PRESENT, "native-workout"),
            energy = ComponentLookupPayload(ComponentLookupStatus.ABSENT),
            derivedStatus = WorkoutLookupStatus.WORKOUT_ONLY,
        )
    }

    override suspend fun authorizationSnapshot(types: List<String>): AuthorizationSnapshotPayload {
        authorizationCalls += 1
        lastAuthorizationTypes = types
        authorizationFailure?.let { throw it }
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

private class RecordingResult : Result {
    data class ErrorCall(val code: String, val message: String?, val details: Any?)

    val successes = mutableListOf<Any?>()
    val errors = mutableListOf<ErrorCall>()
    var notImplementedCalls: Int = 0
        private set

    override fun success(result: Any?) {
        successes += result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        errors += ErrorCall(errorCode, errorMessage, errorDetails)
    }

    override fun notImplemented() {
        notImplementedCalls += 1
    }

    @Suppress("UNCHECKED_CAST")
    fun successMap(): Map<String, Any?> = successes.single() as Map<String, Any?>

    @Suppress("UNCHECKED_CAST")
    fun componentMap(key: String): Map<String, Any?> = successMap()[key] as Map<String, Any?>

    fun assertNoErrorOrNotImplemented() {
        assertTrue(errors.isEmpty())
        assertEquals(0, notImplementedCalls)
        assertNotNull(successes.single())
        assertNull(errors.singleOrNull())
    }
}

private const val WORKOUT_CLIENT_ID = "018f8d7e-1111-7111-8111-111111111111"
private const val ENERGY_CLIENT_ID = "018f8d7e-2222-7222-8222-222222222222"
private val WORKOUT_START = java.time.Instant.parse("2026-03-08T06:55:00Z")
private val WORKOUT_END = java.time.Instant.parse("2026-03-08T07:25:00Z")

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
