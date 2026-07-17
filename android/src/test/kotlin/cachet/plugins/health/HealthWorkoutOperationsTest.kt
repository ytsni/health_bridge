package cachet.plugins.health

import android.os.RemoteException
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.InsertRecordsResponse
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.testing.FakeHealthConnectClient
import androidx.health.connect.client.testing.FakePermissionController
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import java.util.concurrent.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.reflect.KClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HealthWorkoutOperationsTest {
    @Test
    fun lookup_fullReturnsIndependentRealNativeIds() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val writeResult = HealthWorkoutOperations(fake, APP_PACKAGE).write(validWriteRequest())

        val result = HealthWorkoutOperations(fake, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.PRESENT, result.workout.status)
        assertEquals(writeResult.workoutRecordId, result.workout.recordId)
        assertEquals(ComponentLookupStatus.PRESENT, result.energy.status)
        assertEquals(writeResult.energyRecordId, result.energy.recordId)
        assertEquals(WorkoutLookupStatus.PRESENT, result.derivedStatus)
        assertNull(result.platformCode)
    }

    @Test
    fun lookup_workoutOnlyWhenEnergyIsNotExpected() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE))
        val fake = fakeClient(permissions)
        val writeResult =
            HealthWorkoutOperations(fake, APP_PACKAGE).write(validWriteRequest(includeEnergy = false))

        val result =
            HealthWorkoutOperations(fake, APP_PACKAGE)
                .lookup(validLookupRequest(includeEnergy = false))

        assertEquals(ComponentLookupStatus.PRESENT, result.workout.status)
        assertEquals(writeResult.workoutRecordId, result.workout.recordId)
        assertEquals(ComponentLookupStatus.NOT_EXPECTED, result.energy.status)
        assertNull(result.energy.recordId)
        assertEquals(WorkoutLookupStatus.WORKOUT_ONLY, result.derivedStatus)
        assertNull(result.platformCode)
    }

    @Test
    fun lookup_successfulEmptyQueriesReturnAbsent() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)

        val result = HealthWorkoutOperations(fake, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.ABSENT, result.workout.status)
        assertEquals(ComponentLookupStatus.ABSENT, result.energy.status)
        assertEquals(WorkoutLookupStatus.ABSENT, result.derivedStatus)
        assertNull(result.platformCode)
    }

    @Test
    fun lookup_includesExactFrozenEndButExcludesAdjustedEndBoundary() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val workoutId =
            fake.insertRecords(
                    listOf(workoutRecord(WORKOUT_CLIENT_ID))
                )
                .recordIdsList
                .first()
        val recording =
            RecordingHealthWorkoutClient(
                delegate = AndroidHealthWorkoutClient(fake),
                transformEnergyRead = { _, response ->
                    ReadRecordsResponse(
                        records =
                            response.records +
                                energyRecord(
                                    clientRecordId = ENERGY_CLIENT_ID,
                                    endTime = WORKOUT_END.plusNanos(1),
                                ),
                        pageToken = response.pageToken,
                    )
                },
            )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.PRESENT, result.workout.status)
        assertEquals(workoutId, result.workout.recordId)
        assertEquals(ComponentLookupStatus.ABSENT, result.energy.status)
        assertEquals(WorkoutLookupStatus.WORKOUT_ONLY, result.derivedStatus)
    }

    @Test
    fun lookup_endAdjustmentOverflowReturnsTypedUnavailableWithoutQuery() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))
        val request =
            validLookupRequest().copy(
                startTime = Instant.MAX.minusSeconds(1),
                endTime = Instant.MAX,
            )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).lookup(request)

        assertEquals(ComponentLookupStatus.UNAVAILABLE, result.workout.status)
        assertEquals(ComponentLookupStatus.UNAVAILABLE, result.energy.status)
        assertEquals(WorkoutLookupStatus.UNAVAILABLE, result.derivedStatus)
        assertEquals("invalidTimeRange", result.platformCode)
        assertTrue(recording.workoutReadRequests.isEmpty())
        assertTrue(recording.energyReadRequests.isEmpty())
    }

    @Test
    fun lookup_missingWorkoutWriteGrantLeavesEnergyQueryIndependent() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.UNAVAILABLE, result.workout.status)
        assertEquals(ComponentLookupStatus.ABSENT, result.energy.status)
        assertEquals(WorkoutLookupStatus.UNAVAILABLE, result.derivedStatus)
        assertEquals("writePermissionDenied", result.platformCode)
        assertTrue(recording.workoutReadRequests.isEmpty())
        assertEquals(1, recording.energyReadRequests.size)
    }

    @Test
    fun lookup_missingExpectedEnergyWriteGrantLeavesWorkoutQueryIndependent() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.ABSENT, result.workout.status)
        assertEquals(ComponentLookupStatus.UNAVAILABLE, result.energy.status)
        assertEquals(WorkoutLookupStatus.UNAVAILABLE, result.derivedStatus)
        assertEquals("writePermissionDenied", result.platformCode)
        assertEquals(1, recording.workoutReadRequests.size)
        assertTrue(recording.energyReadRequests.isEmpty())
    }

    @Test
    fun lookup_energyPresentWithoutWorkoutIsInconsistent() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val energyId =
            fake.insertRecords(listOf(energyRecord(ENERGY_CLIENT_ID))).recordIdsList.single()

        val result = HealthWorkoutOperations(fake, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.ABSENT, result.workout.status)
        assertEquals(ComponentLookupStatus.PRESENT, result.energy.status)
        assertEquals(energyId, result.energy.recordId)
        assertEquals(WorkoutLookupStatus.INCONSISTENT, result.derivedStatus)
        assertNull(result.platformCode)
    }

    @Test
    fun lookup_ignoresAnotherOriginEvenWithExactClientIds() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        fake.setPackageName(OTHER_PACKAGE)
        fake.insertRecords(
            listOf(
                workoutRecord(WORKOUT_CLIENT_ID),
                energyRecord(ENERGY_CLIENT_ID),
            )
        )
        fake.setPackageName(APP_PACKAGE)

        val result = HealthWorkoutOperations(fake, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.ABSENT, result.workout.status)
        assertEquals(ComponentLookupStatus.ABSENT, result.energy.status)
        assertEquals(WorkoutLookupStatus.ABSENT, result.derivedStatus)
    }

    @Test
    fun lookup_ignoresSameTimeRecordsWithWrongClientIds() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        fake.insertRecords(
            listOf(
                workoutRecord(WRONG_WORKOUT_CLIENT_ID),
                energyRecord(WRONG_ENERGY_CLIENT_ID),
            )
        )

        val result = HealthWorkoutOperations(fake, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.ABSENT, result.workout.status)
        assertEquals(ComponentLookupStatus.ABSENT, result.energy.status)
        assertEquals(WorkoutLookupStatus.ABSENT, result.derivedStatus)
    }

    @Test
    fun lookup_filtersFrozenBoundsAndOriginAcrossEveryPageToken() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val records =
            buildList<Record> {
                repeat(4) { index ->
                    add(
                        workoutRecord(
                            clientRecordId = pageClientId(100 + index),
                        )
                    )
                    add(
                        energyRecord(
                            clientRecordId = pageClientId(200 + index),
                        )
                    )
                }
                add(workoutRecord(clientRecordId = WORKOUT_CLIENT_ID))
                add(energyRecord(clientRecordId = ENERGY_CLIENT_ID))
            }
        fake.insertRecords(records)
        val targetWorkoutId =
            readAll<ExerciseSessionRecord>(fake)
                .single { it.metadata.clientRecordId == WORKOUT_CLIENT_ID }
                .metadata.id
        val targetEnergyId =
            readAll<ActiveCaloriesBurnedRecord>(fake)
                .single { it.metadata.clientRecordId == ENERGY_CLIENT_ID }
                .metadata.id
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result =
            HealthWorkoutOperations(recording, APP_PACKAGE, lookupPageSize = 2)
                .lookup(validLookupRequest())

        assertEquals(targetWorkoutId, result.workout.recordId)
        assertEquals(targetEnergyId, result.energy.recordId)
        assertEquals(WorkoutLookupStatus.PRESENT, result.derivedStatus)
        assertFullyPaginated(
            recording.workoutReadRequests,
            recording.workoutReadResponses,
            WORKOUT_CLIENT_ID,
        )
        assertFullyPaginated(
            recording.energyReadRequests,
            recording.energyReadResponses,
            ENERGY_CLIENT_ID,
        )
    }

    @Test
    fun lookup_rechecksMatchingWriteGrantBeforeEachExpectedComponentQuery() = runTest {
        val permissions =
            SequencedPermissionController(
                listOf(
                    setOf(WRITE_EXERCISE, WRITE_ENERGY),
                    setOf(WRITE_EXERCISE),
                )
            )
        val fake =
            FakeHealthConnectClient(
                packageName = APP_PACKAGE,
                permissionController = permissions,
            )
        val workoutId =
            fake.insertRecords(
                    listOf(
                        workoutRecord(WORKOUT_CLIENT_ID),
                        energyRecord(ENERGY_CLIENT_ID),
                    )
                )
                .recordIdsList
                .first()
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.PRESENT, result.workout.status)
        assertEquals(workoutId, result.workout.recordId)
        assertEquals(ComponentLookupStatus.UNAVAILABLE, result.energy.status)
        assertEquals(WorkoutLookupStatus.UNAVAILABLE, result.derivedStatus)
        assertEquals("writePermissionDenied", result.platformCode)
        assertEquals(2, permissions.getGrantedCalls)
        assertEquals(1, recording.workoutReadRequests.size)
        assertTrue(recording.energyReadRequests.isEmpty())
    }

    @Test
    fun lookup_permissionCheckFailureReturnsUnavailableWithoutQuery() = runTest {
        val fake = fakeClient(FakePermissionController(grantAll = false))
        val recording =
            RecordingHealthWorkoutClient(
                delegate = AndroidHealthWorkoutClient(fake),
                permissionControllerOverride =
                    ThrowingPermissionController(IOException("permission service unavailable")),
            )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.UNAVAILABLE, result.workout.status)
        assertEquals(ComponentLookupStatus.UNAVAILABLE, result.energy.status)
        assertEquals(WorkoutLookupStatus.UNAVAILABLE, result.derivedStatus)
        assertEquals("permissionCheckFailed", result.platformCode)
        assertTrue(recording.workoutReadRequests.isEmpty())
        assertTrue(recording.energyReadRequests.isEmpty())
    }

    @Test
    fun lookup_workoutQueryFailuresAreTypedUnavailableNeverAbsent() = runTest {
        lookupFailureCases().forEach { (failure, expectedCode) ->
            val permissions = FakePermissionController(grantAll = false)
            permissions.grantPermissions(setOf(WRITE_EXERCISE))
            val fake = fakeClient(permissions)
            val recording =
                RecordingHealthWorkoutClient(
                    delegate = AndroidHealthWorkoutClient(fake),
                    transformWorkoutRead = { _, _ -> throw failure },
                )

            val result =
                HealthWorkoutOperations(recording, APP_PACKAGE)
                    .lookup(validLookupRequest(includeEnergy = false))

            assertEquals(ComponentLookupStatus.UNAVAILABLE, result.workout.status)
            assertNull(result.workout.recordId)
            assertEquals(ComponentLookupStatus.NOT_EXPECTED, result.energy.status)
            assertEquals(WorkoutLookupStatus.UNAVAILABLE, result.derivedStatus)
            assertEquals(expectedCode, result.platformCode)
            assertEquals(1, recording.workoutReadRequests.size)
        }
    }

    @Test
    fun lookup_energyQueryFailuresAreTypedUnavailableNeverAbsent() = runTest {
        lookupFailureCases().forEach { (failure, expectedCode) ->
            val permissions = FakePermissionController(grantAll = false)
            permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
            val fake = fakeClient(permissions)
            val workoutId =
                fake.insertRecords(listOf(workoutRecord(WORKOUT_CLIENT_ID))).recordIdsList.single()
            val recording =
                RecordingHealthWorkoutClient(
                    delegate = AndroidHealthWorkoutClient(fake),
                    transformEnergyRead = { _, _ -> throw failure },
                )

            val result = HealthWorkoutOperations(recording, APP_PACKAGE).lookup(validLookupRequest())

            assertEquals(ComponentLookupStatus.PRESENT, result.workout.status)
            assertEquals(workoutId, result.workout.recordId)
            assertEquals(ComponentLookupStatus.UNAVAILABLE, result.energy.status)
            assertNull(result.energy.recordId)
            assertEquals(WorkoutLookupStatus.UNAVAILABLE, result.derivedStatus)
            assertEquals(expectedCode, result.platformCode)
            assertEquals(1, recording.energyReadRequests.size)
        }
    }

    @Test
    fun lookup_multipleExactWorkoutMatchesReturnUnavailableWithoutArbitraryId() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE))
        val fake = fakeClient(permissions)
        val recording =
            RecordingHealthWorkoutClient(
                delegate = AndroidHealthWorkoutClient(fake),
                transformWorkoutRead = { _, response ->
                    ReadRecordsResponse(
                        records =
                            listOf(
                                workoutRecord(WORKOUT_CLIENT_ID, nativeId = "native-workout-1"),
                                workoutRecord(WORKOUT_CLIENT_ID, nativeId = "native-workout-2"),
                            ),
                        pageToken = response.pageToken,
                    )
                },
            )

        val result =
            HealthWorkoutOperations(recording, APP_PACKAGE)
                .lookup(validLookupRequest(includeEnergy = false))

        assertEquals(ComponentLookupStatus.UNAVAILABLE, result.workout.status)
        assertNull(result.workout.recordId)
        assertEquals(ComponentLookupStatus.NOT_EXPECTED, result.energy.status)
        assertEquals(WorkoutLookupStatus.UNAVAILABLE, result.derivedStatus)
        assertEquals("multipleMatchingRecords", result.platformCode)
    }

    @Test
    fun lookup_multipleExactEnergyMatchesAreUnavailableNotInconsistent() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording =
            RecordingHealthWorkoutClient(
                delegate = AndroidHealthWorkoutClient(fake),
                transformEnergyRead = { _, response ->
                    ReadRecordsResponse(
                        records =
                            listOf(
                                energyRecord(ENERGY_CLIENT_ID, nativeId = "native-energy-1"),
                                energyRecord(ENERGY_CLIENT_ID, nativeId = "native-energy-2"),
                            ),
                        pageToken = response.pageToken,
                    )
                },
            )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).lookup(validLookupRequest())

        assertEquals(ComponentLookupStatus.ABSENT, result.workout.status)
        assertEquals(ComponentLookupStatus.UNAVAILABLE, result.energy.status)
        assertNull(result.energy.recordId)
        assertEquals(WorkoutLookupStatus.UNAVAILABLE, result.derivedStatus)
        assertEquals("multipleMatchingRecords", result.platformCode)
    }

    @Test
    fun lookup_writeOnlyGrantsFindOwnWriteAndNeverExposeAnotherOrigin() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        fake.setPackageName(OTHER_PACKAGE)
        fake.insertRecords(
            listOf(
                workoutRecord(WORKOUT_CLIENT_ID),
                energyRecord(ENERGY_CLIENT_ID),
            )
        )
        fake.setPackageName(APP_PACKAGE)
        val operations = HealthWorkoutOperations(fake, APP_PACKAGE)
        val writeResult = operations.write(validWriteRequest())

        val lookupResult = operations.lookup(validLookupRequest())

        assertTrue(READ_EXERCISE !in permissions.getGrantedPermissions())
        assertTrue(READ_ENERGY !in permissions.getGrantedPermissions())
        assertEquals(writeResult.workoutRecordId, lookupResult.workout.recordId)
        assertEquals(writeResult.energyRecordId, lookupResult.energy.recordId)
        assertEquals(WorkoutLookupStatus.PRESENT, lookupResult.derivedStatus)
    }

    @Test
    fun lookup_lostWorkoutOnlyReplyThenEnergyGrantNeverBackfillsEnergy() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE))
        val fake = fakeClient(permissions)
        val recording =
            RecordingHealthWorkoutClient(
                delegate = AndroidHealthWorkoutClient(fake),
                transformResponse = { _, _ ->
                    throw RemoteException("workout-only response lost")
                },
            )
        val operations = HealthWorkoutOperations(recording, APP_PACKAGE)

        val writeResult = operations.write(validWriteRequest())
        permissions.grantPermissions(setOf(WRITE_ENERGY))
        val lookupResult = operations.lookup(validLookupRequest())

        assertEquals(WorkoutWriteStatus.VERIFICATION_REQUIRED, writeResult.status)
        assertEquals(EnergyWriteStatus.OMITTED_PERMISSION, writeResult.energyStatus)
        assertEquals(SubmissionCertainty.MAY_HAVE_SUBMITTED, writeResult.submissionCertainty)
        assertEquals(ComponentLookupStatus.PRESENT, lookupResult.workout.status)
        assertEquals(ComponentLookupStatus.ABSENT, lookupResult.energy.status)
        assertEquals(WorkoutLookupStatus.WORKOUT_ONLY, lookupResult.derivedStatus)
        assertEquals(1, recording.insertedBatches.size)
        assertEquals(1, recording.insertedBatches.single().size)
        assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
        assertTrue(readAll<ActiveCaloriesBurnedRecord>(fake).isEmpty())
    }

    @Test
    fun write_fullBatchSetsFrozenFieldsAndMapsReturnedIdsByRecordOrder() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))
        val operations = HealthWorkoutOperations(recording, APP_PACKAGE)

        val result = operations.write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.WRITTEN, result.status)
        assertEquals(EnergyWriteStatus.WRITTEN, result.energyStatus)
        assertEquals(SubmissionCertainty.SUBMITTED, result.submissionCertainty)
        assertFalse(result.retryable)
        assertEquals(1, recording.insertedBatches.size)
        assertEquals(2, recording.insertedBatches.single().size)
        assertTrue(recording.insertedBatches.single()[0] is ExerciseSessionRecord)
        assertTrue(recording.insertedBatches.single()[1] is ActiveCaloriesBurnedRecord)

        val workout = readAll<ExerciseSessionRecord>(fake).single()
        val energy = readAll<ActiveCaloriesBurnedRecord>(fake).single()
        assertEquals(WORKOUT_CLIENT_ID, workout.metadata.clientRecordId)
        assertEquals(ENERGY_CLIENT_ID, energy.metadata.clientRecordId)
        assertEquals(0L, workout.metadata.clientRecordVersion)
        assertEquals(0L, energy.metadata.clientRecordVersion)
        assertEquals(ZoneOffset.ofHours(-5), workout.startZoneOffset)
        assertEquals(ZoneOffset.ofHours(-4), workout.endZoneOffset)
        assertEquals(ZoneOffset.ofHours(-5), energy.startZoneOffset)
        assertEquals(ZoneOffset.ofHours(-4), energy.endZoneOffset)
        assertEquals(ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING, workout.exerciseType)
        assertEquals("Plates Workout", workout.title)
        assertEquals(123.5, energy.energy.inKilocalories, 0.0)
        assertEquals(Metadata.RECORDING_METHOD_ACTIVELY_RECORDED, workout.metadata.recordingMethod)
        assertEquals(Metadata.RECORDING_METHOD_ACTIVELY_RECORDED, energy.metadata.recordingMethod)
        assertEquals(Device.TYPE_PHONE, workout.metadata.device?.type)
        assertEquals(Device.TYPE_PHONE, energy.metadata.device?.type)
        assertEquals(workout.metadata.id, result.workoutRecordId)
        assertEquals(energy.metadata.id, result.energyRecordId)
        assertNotEquals(result.workoutRecordId, result.energyRecordId)
    }

    @Test
    fun write_activelyRecordedWatchUsesNamedProvenanceAndWatchDevice() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val operations = HealthWorkoutOperations(fake, APP_PACKAGE)

        operations.write(
            validWriteRequest(
                provenance = RecordingProvenance.ACTIVELY_RECORDED,
                device = RecordingDevice.WATCH,
            )
        )

        val workoutMetadata = readAll<ExerciseSessionRecord>(fake).single().metadata
        val energyMetadata = readAll<ActiveCaloriesBurnedRecord>(fake).single().metadata
        assertEquals(
            Metadata.RECORDING_METHOD_ACTIVELY_RECORDED,
            workoutMetadata.recordingMethod,
        )
        assertEquals(
            Metadata.RECORDING_METHOD_ACTIVELY_RECORDED,
            energyMetadata.recordingMethod,
        )
        assertEquals(Device.TYPE_WATCH, workoutMetadata.device?.type)
        assertEquals(Device.TYPE_WATCH, energyMetadata.device?.type)
    }

    @Test
    fun write_manualEntryWatchUsesNamedProvenanceAndWatchDeviceOnBothRecords() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val operations = HealthWorkoutOperations(fake, APP_PACKAGE)

        operations.write(
            validWriteRequest(
                provenance = RecordingProvenance.MANUAL_ENTRY,
                device = RecordingDevice.WATCH,
            )
        )

        val workoutMetadata = readAll<ExerciseSessionRecord>(fake).single().metadata
        val energyMetadata = readAll<ActiveCaloriesBurnedRecord>(fake).single().metadata
        assertEquals(Metadata.RECORDING_METHOD_MANUAL_ENTRY, workoutMetadata.recordingMethod)
        assertEquals(Metadata.RECORDING_METHOD_MANUAL_ENTRY, energyMetadata.recordingMethod)
        assertEquals(Device.TYPE_WATCH, workoutMetadata.device?.type)
        assertEquals(Device.TYPE_WATCH, energyMetadata.device?.type)
    }

    @Test
    fun write_noEnergyRequestInsertsOnlyWorkoutAndReportsNotExpected() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result = HealthWorkoutOperations(recording, APP_PACKAGE)
            .write(validWriteRequest(includeEnergy = false))

        assertEquals(WorkoutWriteStatus.WRITTEN, result.status)
        assertEquals(EnergyWriteStatus.NOT_EXPECTED, result.energyStatus)
        assertNotNull(result.workoutRecordId)
        assertNull(result.energyRecordId)
        assertEquals(1, recording.insertedBatches.single().size)
        assertTrue(recording.insertedBatches.single().single() is ExerciseSessionRecord)
        assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
        assertTrue(readAll<ActiveCaloriesBurnedRecord>(fake).isEmpty())
    }

    @Test
    fun write_deniedEnergyInsertsWorkoutOnlyAndReportsOmittedPermission() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.WRITTEN_WITHOUT_ENERGY, result.status)
        assertEquals(EnergyWriteStatus.OMITTED_PERMISSION, result.energyStatus)
        assertEquals(SubmissionCertainty.SUBMITTED, result.submissionCertainty)
        assertEquals(1, recording.insertedBatches.single().size)
        assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
        assertTrue(readAll<ActiveCaloriesBurnedRecord>(fake).isEmpty())
    }

    @Test
    fun write_deniedWorkoutReturnsBlockedWithoutDispatchOrStoredRecords() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION, result.status)
        assertEquals(EnergyWriteStatus.NOT_SUBMITTED, result.energyStatus)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, result.submissionCertainty)
        assertFalse(result.retryable)
        assertTrue(recording.insertedBatches.isEmpty())
        assertTrue(readAll<ExerciseSessionRecord>(fake).isEmpty())
        assertTrue(readAll<ActiveCaloriesBurnedRecord>(fake).isEmpty())
    }

    @Test
    fun write_deniedWorkoutWithoutEnergyReportsNotExpectedWithoutDispatch() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result = HealthWorkoutOperations(recording, APP_PACKAGE)
            .write(validWriteRequest(includeEnergy = false))

        assertEquals(WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION, result.status)
        assertEquals(EnergyWriteStatus.NOT_EXPECTED, result.energyStatus)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, result.submissionCertainty)
        assertTrue(recording.insertedBatches.isEmpty())
    }

    @Test
    fun write_secondIdenticalBatchDeduplicatesByStableIndependentClientIds() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val operations = HealthWorkoutOperations(fake, APP_PACKAGE)

        val first = operations.write(validWriteRequest())
        val second = operations.write(validWriteRequest())

        assertEquals(first.workoutRecordId, second.workoutRecordId)
        assertEquals(first.energyRecordId, second.energyRecordId)
        assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
        assertEquals(1, readAll<ActiveCaloriesBurnedRecord>(fake).size)
    }

    @Test
    fun write_responseIdCountMismatchRequiresVerificationWithoutGuessingIds() = runTest {
        listOf(
            emptyList(),
            listOf("only-one"),
            listOf("", "energy"),
            listOf("workout", " "),
            listOf("duplicate", "duplicate"),
            listOf("workout", "energy", "extra"),
        ).forEach { returnedIds ->
            val permissions = FakePermissionController(grantAll = false)
            permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
            val fake = fakeClient(permissions)
            val recording = RecordingHealthWorkoutClient(
                delegate = AndroidHealthWorkoutClient(fake),
                transformResponse = { _, _ -> InsertRecordsResponse(returnedIds) },
            )

            val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

            assertEquals(WorkoutWriteStatus.VERIFICATION_REQUIRED, result.status)
            assertEquals(EnergyWriteStatus.VERIFICATION_REQUIRED, result.energyStatus)
            assertEquals(SubmissionCertainty.MAY_HAVE_SUBMITTED, result.submissionCertainty)
            assertFalse(result.retryable)
            assertNull(result.workoutRecordId)
            assertNull(result.energyRecordId)
        }
    }

    @Test
    fun write_workoutOnlyResponseIdEmptyBlankOrExtraRequiresVerification() = runTest {
        val requests =
            listOf(
                validWriteRequest() to EnergyWriteStatus.OMITTED_PERMISSION,
                validWriteRequest(includeEnergy = false) to EnergyWriteStatus.NOT_EXPECTED,
            )
        val invalidReturnedIds =
            listOf(
                emptyList(),
                listOf(" "),
                listOf("workout", "extra"),
            )

        requests.forEach { (request, expectedEnergyStatus) ->
            invalidReturnedIds.forEach { returnedIds ->
                val permissions = FakePermissionController(grantAll = false)
                permissions.grantPermissions(setOf(WRITE_EXERCISE))
                val fake = fakeClient(permissions)
                val recording =
                    RecordingHealthWorkoutClient(
                        delegate = AndroidHealthWorkoutClient(fake),
                        transformResponse = { _, _ -> InsertRecordsResponse(returnedIds) },
                    )

                val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(request)

                assertEquals(WorkoutWriteStatus.VERIFICATION_REQUIRED, result.status)
                assertEquals(expectedEnergyStatus, result.energyStatus)
                assertEquals(
                    SubmissionCertainty.MAY_HAVE_SUBMITTED,
                    result.submissionCertainty,
                )
                assertFalse(result.retryable)
                assertNull(result.workoutRecordId)
                assertNull(result.energyRecordId)
                assertEquals(1, recording.insertedBatches.single().size)
                assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
                assertTrue(readAll<ActiveCaloriesBurnedRecord>(fake).isEmpty())
            }
        }
    }

    @Test
    fun write_energySecurityRaceRefreshesGrantsAndRetriesWorkoutOnlyOnce() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(
            delegate = AndroidHealthWorkoutClient(fake),
            beforeInsert = { call, _ ->
                if (call == 1) {
                    permissions.replaceGrantedPermissions(setOf(WRITE_EXERCISE))
                    throw SecurityException("energy permission revoked")
                }
            },
        )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.WRITTEN_WITHOUT_ENERGY, result.status)
        assertEquals(EnergyWriteStatus.OMITTED_PERMISSION, result.energyStatus)
        assertEquals(SubmissionCertainty.SUBMITTED, result.submissionCertainty)
        assertEquals(2, recording.insertedBatches.size)
        assertEquals(2, recording.insertedBatches.first().size)
        assertEquals(1, recording.insertedBatches.last().size)
        assertTrue(recording.insertedBatches.last().single() is ExerciseSessionRecord)
        assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
        assertTrue(readAll<ActiveCaloriesBurnedRecord>(fake).isEmpty())
    }

    @Test
    fun write_securityRaceWithLostWorkoutGrantDoesNotRetry() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(
            delegate = AndroidHealthWorkoutClient(fake),
            beforeInsert = { call, _ ->
                if (call == 1) {
                    permissions.replaceGrantedPermissions(emptySet())
                    throw SecurityException("workout permission revoked")
                }
            },
        )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION, result.status)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, result.submissionCertainty)
        assertEquals(1, recording.insertedBatches.size)
        assertTrue(readAll<ExerciseSessionRecord>(fake).isEmpty())
        assertTrue(readAll<ActiveCaloriesBurnedRecord>(fake).isEmpty())
    }

    @Test
    fun write_securityFailureWithAllGrantsStillPresentDoesNotBlindRetry() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(
            delegate = AndroidHealthWorkoutClient(fake),
            beforeInsert = { _, _ -> throw SecurityException("unexpected permission failure") },
        )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.TRANSIENT_FAILURE, result.status)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, result.submissionCertainty)
        assertTrue(result.retryable)
        assertEquals(1, recording.insertedBatches.size)
    }

    @Test
    fun write_secondSecurityFailureNeverAttemptsAThirdBatch() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(
            delegate = AndroidHealthWorkoutClient(fake),
            beforeInsert = { call, _ ->
                if (call == 1) permissions.replaceGrantedPermissions(setOf(WRITE_EXERCISE))
                throw SecurityException("security failure $call")
            },
        )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.TRANSIENT_FAILURE, result.status)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, result.submissionCertainty)
        assertTrue(result.retryable)
        assertEquals(2, recording.insertedBatches.size)
    }

    @Test
    fun write_remoteExceptionAfterDispatchRequiresVerification() = runTest {
        assertAmbiguousFailureAfterDispatch(RemoteException("lost binder response"))
    }

    @Test
    fun write_ioExceptionAfterDispatchRequiresVerification() = runTest {
        assertAmbiguousFailureAfterDispatch(IOException("lost transport response"))
    }

    @Test
    fun write_cancellationAfterFullBatchDispatchRequiresVerification() = runTest {
        assertAmbiguousFailureAfterDispatch(CancellationException("canceled after dispatch"))
    }

    @Test
    fun write_unknownExceptionAfterFullBatchDispatchRequiresVerification() = runTest {
        assertAmbiguousFailureAfterDispatch(RuntimeException("unexpected failure after dispatch"))
    }

    @Test
    fun write_illegalStateExceptionAfterStoredFullBatchRequiresVerification() = runTest {
        assertAmbiguousFailureAfterDispatch(
            IllegalStateException("internal failure after stored batch")
        )
    }

    @Test
    fun write_cancellationAfterWorkoutOnlyRetryDispatchRequiresVerification() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(
            delegate = AndroidHealthWorkoutClient(fake),
            beforeInsert = { call, _ ->
                if (call == 1) {
                    permissions.replaceGrantedPermissions(setOf(WRITE_EXERCISE))
                    throw SecurityException("energy permission revoked")
                }
            },
            transformResponse = { call, response ->
                if (call == 2) throw CancellationException("retry canceled after dispatch")
                response
            },
        )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.VERIFICATION_REQUIRED, result.status)
        assertEquals(EnergyWriteStatus.OMITTED_PERMISSION, result.energyStatus)
        assertEquals(SubmissionCertainty.MAY_HAVE_SUBMITTED, result.submissionCertainty)
        assertEquals(2, recording.insertedBatches.size)
        assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
        assertTrue(readAll<ActiveCaloriesBurnedRecord>(fake).isEmpty())
    }

    @Test
    fun write_illegalStateExceptionAfterStoredWorkoutOnlyRetryRequiresVerification() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording =
            RecordingHealthWorkoutClient(
                delegate = AndroidHealthWorkoutClient(fake),
                beforeInsert = { call, _ ->
                    if (call == 1) {
                        permissions.replaceGrantedPermissions(setOf(WRITE_EXERCISE))
                        throw SecurityException("energy permission revoked")
                    }
                },
                transformResponse = { call, response ->
                    if (call == 2) {
                        throw IllegalStateException("internal failure after stored workout")
                    }
                    response
                },
            )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.VERIFICATION_REQUIRED, result.status)
        assertEquals(EnergyWriteStatus.OMITTED_PERMISSION, result.energyStatus)
        assertEquals(SubmissionCertainty.MAY_HAVE_SUBMITTED, result.submissionCertainty)
        assertFalse(result.retryable)
        assertEquals(2, recording.insertedBatches.size)
        assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
        assertTrue(readAll<ActiveCaloriesBurnedRecord>(fake).isEmpty())
    }

    @Test
    fun write_externalJobCancellationAfterStoredBatchWinsOverCanceledHandlerFallback() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val dispatched = CompletableDeferred<Unit>()
        val recording = RecordingHealthWorkoutClient(
            delegate = AndroidHealthWorkoutClient(fake),
            transformResponse = { _, _ ->
                dispatched.complete(Unit)
                awaitCancellation()
            },
        )
        val operations = HealthWorkoutOperations(recording, APP_PACKAGE)
        val operationJob = Job()
        val operationScope = CoroutineScope(StandardTestDispatcher(testScheduler) + operationJob)
        val result = OperationResult()
        val handler = HealthWorkoutMethodHandler(operationScope, operations)

        handler.write(validWriteArguments(), result)
        runCurrent()
        assertTrue(dispatched.isCompleted)
        operationJob.cancel()
        advanceUntilIdle()

        assertEquals(1, result.successes.size)
        assertEquals("verificationRequired", result.successMap()["status"])
        assertEquals("verificationRequired", result.successMap()["energyStatus"])
        assertEquals("mayHaveSubmitted", result.successMap()["submissionCertainty"])
        assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
        assertEquals(1, readAll<ActiveCaloriesBurnedRecord>(fake).size)
    }

    @Test
    fun write_permissionPreflightFailureReturnsUnavailableWithoutDispatch() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(
            delegate = AndroidHealthWorkoutClient(fake),
            permissionControllerOverride = ThrowingPermissionController(IOException("permission service unavailable")),
        )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.UNAVAILABLE, result.status)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, result.submissionCertainty)
        assertTrue(result.retryable)
        assertTrue(recording.insertedBatches.isEmpty())
    }

    @Test
    fun write_unsupportedActivityReturnsInvalidInputWithoutDispatch() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result = HealthWorkoutOperations(recording, APP_PACKAGE)
            .write(validWriteRequest().copy(activityType = "ARCHERY"))

        assertEquals(WorkoutWriteStatus.INVALID_INPUT, result.status)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, result.submissionCertainty)
        assertFalse(result.retryable)
        assertTrue(recording.insertedBatches.isEmpty())
    }

    @Test
    fun write_invalidNoEnergyRequestReportsNotExpectedWithoutDispatch() = runTest {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(AndroidHealthWorkoutClient(fake))

        val result =
            HealthWorkoutOperations(recording, APP_PACKAGE)
                .write(
                    validWriteRequest(includeEnergy = false).copy(
                        activityType = "ARCHERY",
                    )
                )

        assertEquals(WorkoutWriteStatus.INVALID_INPUT, result.status)
        assertEquals(EnergyWriteStatus.NOT_EXPECTED, result.energyStatus)
        assertEquals(SubmissionCertainty.NOT_SUBMITTED, result.submissionCertainty)
        assertFalse(result.retryable)
        assertTrue(recording.insertedBatches.isEmpty())
    }

    @Test
    fun authorizationSnapshot_reportsNoneReadOnlyWriteOnlyAndBothForWorkoutAndEnergy() = runTest {
        val requestedTypes =
            listOf(
                Triple(HealthConstants.WORKOUT, READ_EXERCISE, WRITE_EXERCISE),
                Triple(HealthConstants.ACTIVE_ENERGY_BURNED, READ_ENERGY, WRITE_ENERGY),
            )
        val accessCases =
            listOf(
                Triple(emptySet<String>(), AuthorizationState.DENIED, AuthorizationState.DENIED),
                Triple(setOf("read"), AuthorizationState.AUTHORIZED, AuthorizationState.DENIED),
                Triple(setOf("write"), AuthorizationState.DENIED, AuthorizationState.AUTHORIZED),
                Triple(
                    setOf("read", "write"),
                    AuthorizationState.AUTHORIZED,
                    AuthorizationState.AUTHORIZED,
                ),
            )

        requestedTypes.forEach { (type, readPermission, writePermission) ->
            accessCases.forEach { (access, expectedRead, expectedWrite) ->
                val granted =
                    buildSet {
                        if ("read" in access) add(readPermission)
                        if ("write" in access) add(writePermission)
                    }
                val permissionController = SequencedPermissionController(listOf(granted))
                val fake = fakeClient(FakePermissionController(grantAll = false))
                val operations =
                    HealthWorkoutOperations(
                        RecordingHealthWorkoutClient(
                            delegate = AndroidHealthWorkoutClient(fake),
                            permissionControllerOverride = permissionController,
                        ),
                        APP_PACKAGE,
                    )

                val snapshot = operations.authorizationSnapshot(listOf(type))

                assertTrue(snapshot.available)
                assertNull(snapshot.platformCode)
                assertEquals(1, snapshot.types.size)
                assertEquals(type, snapshot.types.single().type)
                assertEquals(expectedRead, snapshot.types.single().read)
                assertEquals(expectedWrite, snapshot.types.single().write)
                assertEquals(1, permissionController.getGrantedCalls)
            }
        }
    }

    @Test
    fun authorizationSnapshot_mixedSetUsesOneCapturedPermissionSet() = runTest {
        val permissionController =
            SequencedPermissionController(
                listOf(
                    setOf(READ_EXERCISE, WRITE_ENERGY),
                    setOf(WRITE_EXERCISE, READ_ENERGY),
                )
            )
        val fake = fakeClient(FakePermissionController(grantAll = false))
        val operations =
            HealthWorkoutOperations(
                RecordingHealthWorkoutClient(
                    delegate = AndroidHealthWorkoutClient(fake),
                    permissionControllerOverride = permissionController,
                ),
                APP_PACKAGE,
            )

        val snapshot =
            operations.authorizationSnapshot(
                listOf(HealthConstants.WORKOUT, HealthConstants.ACTIVE_ENERGY_BURNED)
            )

        val byType = snapshot.types.associateBy { it.type }
        assertEquals(AuthorizationState.AUTHORIZED, byType.getValue(HealthConstants.WORKOUT).read)
        assertEquals(AuthorizationState.DENIED, byType.getValue(HealthConstants.WORKOUT).write)
        assertEquals(
            AuthorizationState.DENIED,
            byType.getValue(HealthConstants.ACTIVE_ENERGY_BURNED).read,
        )
        assertEquals(
            AuthorizationState.AUTHORIZED,
            byType.getValue(HealthConstants.ACTIVE_ENERGY_BURNED).write,
        )
        assertEquals(1, permissionController.getGrantedCalls)
    }

    @Test
    fun authorizationSnapshot_scalarAndSleepTypesUseExactMappedPermissions() = runTest {
        val weightType = HealthConstants.mapToType.getValue(HealthConstants.WEIGHT)
        val bodyFatType = HealthConstants.mapToType.getValue(HealthConstants.BODY_FAT_PERCENTAGE)
        val sleepType = HealthConstants.mapToType.getValue(HealthConstants.SLEEP_ASLEEP)
        val permissionController =
            SequencedPermissionController(
                listOf(
                    setOf(
                        HealthPermission.getReadPermission(weightType),
                        HealthPermission.getWritePermission(bodyFatType),
                        HealthPermission.getReadPermission(sleepType),
                        HealthPermission.getWritePermission(sleepType),
                    )
                )
            )
        val fake = fakeClient(FakePermissionController(grantAll = false))
        val operations =
            HealthWorkoutOperations(
                RecordingHealthWorkoutClient(
                    delegate = AndroidHealthWorkoutClient(fake),
                    permissionControllerOverride = permissionController,
                ),
                APP_PACKAGE,
            )

        val snapshot =
            operations.authorizationSnapshot(
                listOf(
                    HealthConstants.WEIGHT,
                    HealthConstants.BODY_FAT_PERCENTAGE,
                    HealthConstants.SLEEP_ASLEEP,
                )
            )

        val byType = snapshot.types.associateBy { it.type }
        assertEquals(AuthorizationState.AUTHORIZED, byType.getValue(HealthConstants.WEIGHT).read)
        assertEquals(AuthorizationState.DENIED, byType.getValue(HealthConstants.WEIGHT).write)
        assertEquals(
            AuthorizationState.DENIED,
            byType.getValue(HealthConstants.BODY_FAT_PERCENTAGE).read,
        )
        assertEquals(
            AuthorizationState.AUTHORIZED,
            byType.getValue(HealthConstants.BODY_FAT_PERCENTAGE).write,
        )
        assertEquals(
            AuthorizationState.AUTHORIZED,
            byType.getValue(HealthConstants.SLEEP_ASLEEP).read,
        )
        assertEquals(
            AuthorizationState.AUTHORIZED,
            byType.getValue(HealthConstants.SLEEP_ASLEEP).write,
        )
        assertEquals(1, permissionController.getGrantedCalls)
    }

    @Test
    fun authorizationSnapshot_revocationBetweenCallsIsReflected() = runTest {
        val permissionController =
            SequencedPermissionController(
                listOf(
                    setOf(READ_EXERCISE, WRITE_EXERCISE, READ_ENERGY, WRITE_ENERGY),
                    emptySet(),
                )
            )
        val fake = fakeClient(FakePermissionController(grantAll = false))
        val operations =
            HealthWorkoutOperations(
                RecordingHealthWorkoutClient(
                    delegate = AndroidHealthWorkoutClient(fake),
                    permissionControllerOverride = permissionController,
                ),
                APP_PACKAGE,
            )
        val types = listOf(HealthConstants.WORKOUT, HealthConstants.ACTIVE_ENERGY_BURNED)

        val beforeRevocation = operations.authorizationSnapshot(types)
        val afterRevocation = operations.authorizationSnapshot(types)

        beforeRevocation.types.forEach { entry ->
            assertEquals(AuthorizationState.AUTHORIZED, entry.read)
            assertEquals(AuthorizationState.AUTHORIZED, entry.write)
        }
        afterRevocation.types.forEach { entry ->
            assertEquals(AuthorizationState.DENIED, entry.read)
            assertEquals(AuthorizationState.DENIED, entry.write)
        }
        assertEquals(2, permissionController.getGrantedCalls)
    }

    @Test
    fun authorizationSnapshot_unknownTypeIsUnsupportedForBothAccessModes() = runTest {
        val permissionController =
            SequencedPermissionController(
                listOf(setOf(READ_EXERCISE, WRITE_EXERCISE, READ_ENERGY, WRITE_ENERGY))
            )
        val fake = fakeClient(FakePermissionController(grantAll = false))
        val operations =
            HealthWorkoutOperations(
                RecordingHealthWorkoutClient(
                    delegate = AndroidHealthWorkoutClient(fake),
                    permissionControllerOverride = permissionController,
                ),
                APP_PACKAGE,
            )

        val snapshot =
            operations.authorizationSnapshot(listOf(HealthConstants.WORKOUT, "UNKNOWN_TYPE"))

        val byType = snapshot.types.associateBy { it.type }
        assertEquals(AuthorizationState.AUTHORIZED, byType.getValue(HealthConstants.WORKOUT).read)
        assertEquals(AuthorizationState.AUTHORIZED, byType.getValue(HealthConstants.WORKOUT).write)
        assertEquals(AuthorizationState.UNSUPPORTED, byType.getValue("UNKNOWN_TYPE").read)
        assertEquals(AuthorizationState.UNSUPPORTED, byType.getValue("UNKNOWN_TYPE").write)
        assertEquals(1, permissionController.getGrantedCalls)
    }

    @Test
    fun authorizationSnapshot_permissionControllerFailuresAreTypedUnavailable() = runTest {
        val failures =
            listOf(
                IOException("permission service unavailable") to
                    "authorizationPermissionCheckFailed",
                CancellationException("permission request canceled") to
                    "authorizationPermissionCheckCanceled",
            )

        failures.forEach { (failure, expectedPlatformCode) ->
            val permissionController = ThrowingPermissionController(failure)
            val fake = fakeClient(FakePermissionController(grantAll = false))
            val operations =
                HealthWorkoutOperations(
                    RecordingHealthWorkoutClient(
                        delegate = AndroidHealthWorkoutClient(fake),
                        permissionControllerOverride = permissionController,
                    ),
                    APP_PACKAGE,
                )

            val snapshot =
                operations.authorizationSnapshot(
                    listOf(HealthConstants.WORKOUT, HealthConstants.ACTIVE_ENERGY_BURNED)
                )

            assertFalse(snapshot.available)
            assertEquals(expectedPlatformCode, snapshot.platformCode)
            snapshot.types.forEach { entry ->
                assertEquals(AuthorizationState.UNAVAILABLE, entry.read)
                assertEquals(AuthorizationState.UNAVAILABLE, entry.write)
            }
            assertEquals(1, permissionController.getGrantedCalls)
        }
    }

    @Test
    fun authorizationSnapshot_permissionMappingFailureIsIsolatedPerAccessAndType() = runTest {
        val permissionController =
            SequencedPermissionController(
                listOf(setOf(READ_EXERCISE, WRITE_EXERCISE, READ_ENERGY, WRITE_ENERGY))
            )
        val fake = fakeClient(FakePermissionController(grantAll = false))
        val delegate = AndroidHealthWorkoutPermissionMapper
        val permissionMapper =
            object : HealthWorkoutPermissionMapper {
                override fun readPermission(recordType: KClass<out Record>): String {
                    if (recordType == ExerciseSessionRecord::class) {
                        throw IllegalArgumentException("workout read unsupported")
                    }
                    return delegate.readPermission(recordType)
                }

                override fun writePermission(recordType: KClass<out Record>): String {
                    if (recordType == ActiveCaloriesBurnedRecord::class) {
                        throw IllegalArgumentException("energy write unsupported")
                    }
                    return delegate.writePermission(recordType)
                }
            }
        val operations =
            HealthWorkoutOperations(
                client =
                    RecordingHealthWorkoutClient(
                        delegate = AndroidHealthWorkoutClient(fake),
                        permissionControllerOverride = permissionController,
                    ),
                appPackageName = APP_PACKAGE,
                permissionMapper = permissionMapper,
            )

        val snapshot =
            operations.authorizationSnapshot(
                listOf(
                    HealthConstants.WORKOUT,
                    HealthConstants.ACTIVE_ENERGY_BURNED,
                    HealthConstants.STEPS,
                )
            )

        val byType = snapshot.types.associateBy { it.type }
        assertEquals(AuthorizationState.UNSUPPORTED, byType.getValue(HealthConstants.WORKOUT).read)
        assertEquals(AuthorizationState.AUTHORIZED, byType.getValue(HealthConstants.WORKOUT).write)
        assertEquals(
            AuthorizationState.AUTHORIZED,
            byType.getValue(HealthConstants.ACTIVE_ENERGY_BURNED).read,
        )
        assertEquals(
            AuthorizationState.UNSUPPORTED,
            byType.getValue(HealthConstants.ACTIVE_ENERGY_BURNED).write,
        )
        assertEquals(AuthorizationState.DENIED, byType.getValue(HealthConstants.STEPS).read)
        assertEquals(AuthorizationState.DENIED, byType.getValue(HealthConstants.STEPS).write)
        assertEquals(1, permissionController.getGrantedCalls)
    }

    @Test
    fun authorizationSnapshot_everyCurrentDistinctRecordTypeMapsBothPermissions() {
        val distinctRecordTypes = HealthConstants.mapToType.values.toSet()

        assertTrue(distinctRecordTypes.isNotEmpty())
        distinctRecordTypes.forEach { recordType ->
            assertTrue(AndroidHealthWorkoutPermissionMapper.readPermission(recordType).isNotBlank())
            assertTrue(AndroidHealthWorkoutPermissionMapper.writePermission(recordType).isNotBlank())
        }
    }

    private suspend fun assertAmbiguousFailureAfterDispatch(failure: Exception) {
        val permissions = FakePermissionController(grantAll = false)
        permissions.grantPermissions(setOf(WRITE_EXERCISE, WRITE_ENERGY))
        val fake = fakeClient(permissions)
        val recording = RecordingHealthWorkoutClient(
            delegate = AndroidHealthWorkoutClient(fake),
            transformResponse = { _, _ -> throw failure },
        )

        val result = HealthWorkoutOperations(recording, APP_PACKAGE).write(validWriteRequest())

        assertEquals(WorkoutWriteStatus.VERIFICATION_REQUIRED, result.status)
        assertEquals(EnergyWriteStatus.VERIFICATION_REQUIRED, result.energyStatus)
        assertEquals(SubmissionCertainty.MAY_HAVE_SUBMITTED, result.submissionCertainty)
        assertFalse(result.retryable)
        assertEquals(1, recording.insertedBatches.size)
        assertEquals(1, readAll<ExerciseSessionRecord>(fake).size)
        assertEquals(1, readAll<ActiveCaloriesBurnedRecord>(fake).size)
    }
}

private class RecordingHealthWorkoutClient(
    private val delegate: HealthWorkoutClient,
    private val permissionControllerOverride: PermissionController? = null,
    private val beforeInsert: suspend (Int, List<Record>) -> Unit = { _, _ -> },
    private val transformResponse: suspend (Int, InsertRecordsResponse) -> InsertRecordsResponse = { _, response ->
        response
    },
    private val transformWorkoutRead: suspend (
        ReadRecordsRequest<ExerciseSessionRecord>,
        ReadRecordsResponse<ExerciseSessionRecord>,
    ) -> ReadRecordsResponse<ExerciseSessionRecord> = { _, response -> response },
    private val transformEnergyRead: suspend (
        ReadRecordsRequest<ActiveCaloriesBurnedRecord>,
        ReadRecordsResponse<ActiveCaloriesBurnedRecord>,
    ) -> ReadRecordsResponse<ActiveCaloriesBurnedRecord> = { _, response -> response },
) : HealthWorkoutClient {
    val insertedBatches = mutableListOf<List<Record>>()
    val workoutReadRequests = mutableListOf<ReadRecordsRequest<ExerciseSessionRecord>>()
    val workoutReadResponses = mutableListOf<ReadRecordsResponse<ExerciseSessionRecord>>()
    val energyReadRequests = mutableListOf<ReadRecordsRequest<ActiveCaloriesBurnedRecord>>()
    val energyReadResponses = mutableListOf<ReadRecordsResponse<ActiveCaloriesBurnedRecord>>()

    override val permissionController: PermissionController
        get() = permissionControllerOverride ?: delegate.permissionController

    override suspend fun insertRecords(records: List<Record>): InsertRecordsResponse {
        val batch = records.toList()
        insertedBatches += batch
        val call = insertedBatches.size
        beforeInsert(call, batch)
        return transformResponse(call, delegate.insertRecords(batch))
    }

    override suspend fun readWorkouts(
        request: ReadRecordsRequest<ExerciseSessionRecord>
    ): ReadRecordsResponse<ExerciseSessionRecord> {
        workoutReadRequests += request
        return transformWorkoutRead(request, delegate.readWorkouts(request)).also {
            workoutReadResponses += it
        }
    }

    override suspend fun readEnergy(
        request: ReadRecordsRequest<ActiveCaloriesBurnedRecord>
    ): ReadRecordsResponse<ActiveCaloriesBurnedRecord> {
        energyReadRequests += request
        return transformEnergyRead(request, delegate.readEnergy(request)).also {
            energyReadResponses += it
        }
    }
}

private class ThrowingPermissionController(private val failure: Throwable) : PermissionController {
    var getGrantedCalls: Int = 0
        private set

    override suspend fun getGrantedPermissions(): Set<String> {
        getGrantedCalls += 1
        throw failure
    }

    override suspend fun revokeAllPermissions() = Unit
}

private class SequencedPermissionController(
    private val grantsByCall: List<Set<String>>,
) : PermissionController {
    var getGrantedCalls: Int = 0
        private set

    override suspend fun getGrantedPermissions(): Set<String> {
        val index = getGrantedCalls.coerceAtMost(grantsByCall.lastIndex)
        getGrantedCalls += 1
        return grantsByCall[index]
    }

    override suspend fun revokeAllPermissions() = Unit
}

private class OperationResult : Result {
    val successes = mutableListOf<Any?>()

    override fun success(result: Any?) {
        successes += result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

    override fun notImplemented() = Unit

    @Suppress("UNCHECKED_CAST")
    fun successMap(): Map<String, Any?> = successes.single() as Map<String, Any?>
}

private fun fakeClient(permissions: FakePermissionController): FakeHealthConnectClient =
    FakeHealthConnectClient(packageName = APP_PACKAGE, permissionController = permissions)

private suspend inline fun <reified T : Record> readAll(client: FakeHealthConnectClient): List<T> =
    client.readRecords(
        ReadRecordsRequest(
            recordType = T::class,
            timeRangeFilter = TimeRangeFilter.between(WORKOUT_START.minusSeconds(1), WORKOUT_END.plusSeconds(1)),
            pageSize = 100,
        )
    ).records

private fun validWriteRequest(
    includeEnergy: Boolean = true,
    provenance: RecordingProvenance = RecordingProvenance.ACTIVELY_RECORDED,
    device: RecordingDevice = RecordingDevice.PHONE,
): WorkoutWriteRequest =
    WorkoutWriteRequest(
        workoutClientRecordId = WORKOUT_CLIENT_ID,
        energyClientRecordId = if (includeEnergy) ENERGY_CLIENT_ID else null,
        clientRecordVersion = 0,
        activityType = "STRENGTH_TRAINING",
        startTime = WORKOUT_START,
        endTime = WORKOUT_END,
        startZoneOffsetSeconds = -18_000,
        endZoneOffsetSeconds = -14_400,
        activeEnergyKcal = if (includeEnergy) 123.5 else null,
        title = "Plates Workout",
        recordingProvenance = provenance,
        recordingDevice = device,
    )

private fun validLookupRequest(includeEnergy: Boolean = true): WorkoutLookupRequest =
    WorkoutLookupRequest(
        workoutClientRecordId = WORKOUT_CLIENT_ID,
        energyClientRecordId = if (includeEnergy) ENERGY_CLIENT_ID else null,
        startTime = WORKOUT_START,
        endTime = WORKOUT_END,
    )

private fun workoutRecord(
    clientRecordId: String,
    startTime: Instant = WORKOUT_START,
    endTime: Instant = WORKOUT_END,
    nativeId: String? = null,
): ExerciseSessionRecord =
    ExerciseSessionRecord(
        startTime = startTime,
        startZoneOffset = ZoneOffset.UTC,
        endTime = endTime,
        endZoneOffset = ZoneOffset.UTC,
        metadata = recordMetadata(clientRecordId, nativeId),
        exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING,
        title = "Fixture workout",
    )

private fun energyRecord(
    clientRecordId: String,
    startTime: Instant = WORKOUT_START,
    endTime: Instant = WORKOUT_END,
    nativeId: String? = null,
): ActiveCaloriesBurnedRecord =
    ActiveCaloriesBurnedRecord(
        startTime = startTime,
        startZoneOffset = ZoneOffset.UTC,
        endTime = endTime,
        endZoneOffset = ZoneOffset.UTC,
        energy = Energy.kilocalories(100.0),
        metadata = recordMetadata(clientRecordId, nativeId),
    )

private fun recordMetadata(clientRecordId: String, nativeId: String?): Metadata {
    val device = Device(type = Device.TYPE_PHONE)
    val metadata =
        Metadata.activelyRecorded(
            clientRecordId = clientRecordId,
            clientRecordVersion = 0,
            device = device,
        )
    if (nativeId != null) {
        Metadata::class.java.getDeclaredField("id").apply {
            isAccessible = true
            set(metadata, nativeId)
        }
    }
    return metadata
}

private fun lookupFailureCases(): List<Pair<Exception, String>> =
    listOf(
        IllegalStateException("outside permitted history window") to "historyWindowUnavailable",
        SecurityException("permission revoked during query") to "lookupSecurityFailure",
        RemoteException("binder query failed") to "lookupRemoteFailure",
        IOException("query transport failed") to "lookupIoFailure",
        CancellationException("query canceled") to "lookupCanceled",
        Exception("unexpected query failure") to "lookupFailed",
    )

private fun assertFullyPaginated(
    requests: List<ReadRecordsRequest<out Record>>,
    responses: List<ReadRecordsResponse<out Record>>,
    targetClientRecordId: String,
) {
    assertEquals(3, requests.size)
    assertEquals(3, responses.size)
    assertNull(requests.first().pageToken)
    requests.indices.drop(1).forEach { index ->
        assertNotNull(requests[index].pageToken)
        assertEquals(responses[index - 1].pageToken, requests[index].pageToken)
    }
    assertNull(responses.last().pageToken)
    assertTrue(
        responses.dropLast(1).flatMap { it.records }.none {
            it.metadata.clientRecordId == targetClientRecordId
        }
    )
    assertTrue(
        responses.last().records.any { it.metadata.clientRecordId == targetClientRecordId }
    )
    requests.forEach { request ->
        assertEquals(2, request.pageSize)
        assertEquals(
            TimeRangeFilter.between(WORKOUT_START, WORKOUT_END.plusNanos(1)),
            request.timeRangeFilter,
        )
        assertEquals(setOf(DataOrigin(APP_PACKAGE)), request.dataOriginFilter)
    }
}

private fun pageClientId(suffix: Int): String =
    "018f8d7e-3333-7333-8333-${suffix.toString().padStart(12, '0')}"

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

private const val APP_PACKAGE = "app.myplates"
private const val OTHER_PACKAGE = "com.example.other"
private const val WORKOUT_CLIENT_ID = "018f8d7e-1111-7111-8111-111111111111"
private const val ENERGY_CLIENT_ID = "018f8d7e-2222-7222-8222-222222222222"
private const val WRONG_WORKOUT_CLIENT_ID = "018f8d7e-aaaa-7aaa-8aaa-aaaaaaaaaaaa"
private const val WRONG_ENERGY_CLIENT_ID = "018f8d7e-bbbb-7bbb-8bbb-bbbbbbbbbbbb"
private val WORKOUT_START: Instant = Instant.parse("2026-03-08T06:55:00Z")
private val WORKOUT_END: Instant = Instant.parse("2026-03-08T07:25:00Z")
private val WRITE_EXERCISE = HealthPermission.getWritePermission(ExerciseSessionRecord::class)
private val WRITE_ENERGY = HealthPermission.getWritePermission(ActiveCaloriesBurnedRecord::class)
private val READ_EXERCISE = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
private val READ_ENERGY = HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class)
