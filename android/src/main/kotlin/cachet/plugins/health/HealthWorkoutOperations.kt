package cachet.plugins.health

import android.os.RemoteException
import androidx.health.connect.client.HealthConnectClient
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
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
import java.io.IOException
import java.time.DateTimeException
import java.time.ZoneOffset
import kotlin.reflect.KClass
import kotlinx.coroutines.CancellationException

internal interface HealthWorkoutClient {
    val permissionController: PermissionController

    suspend fun insertRecords(records: List<Record>): InsertRecordsResponse

    suspend fun readWorkouts(
        request: ReadRecordsRequest<ExerciseSessionRecord>
    ): ReadRecordsResponse<ExerciseSessionRecord>

    suspend fun readEnergy(
        request: ReadRecordsRequest<ActiveCaloriesBurnedRecord>
    ): ReadRecordsResponse<ActiveCaloriesBurnedRecord>
}

internal class AndroidHealthWorkoutClient(
    private val delegate: HealthConnectClient,
) : HealthWorkoutClient {
    override val permissionController: PermissionController
        get() = delegate.permissionController

    override suspend fun insertRecords(records: List<Record>): InsertRecordsResponse =
        delegate.insertRecords(records)

    override suspend fun readWorkouts(
        request: ReadRecordsRequest<ExerciseSessionRecord>
    ): ReadRecordsResponse<ExerciseSessionRecord> = delegate.readRecords(request)

    override suspend fun readEnergy(
        request: ReadRecordsRequest<ActiveCaloriesBurnedRecord>
    ): ReadRecordsResponse<ActiveCaloriesBurnedRecord> = delegate.readRecords(request)
}

internal interface HealthWorkoutPermissionMapper {
    fun readPermission(recordType: KClass<out Record>): String

    fun writePermission(recordType: KClass<out Record>): String
}

internal object AndroidHealthWorkoutPermissionMapper : HealthWorkoutPermissionMapper {
    override fun readPermission(recordType: KClass<out Record>): String =
        HealthPermission.getReadPermission(recordType)

    override fun writePermission(recordType: KClass<out Record>): String =
        HealthPermission.getWritePermission(recordType)
}

internal class HealthWorkoutOperations(
    private val client: HealthWorkoutClient,
    private val appPackageName: String,
    private val lookupPageSize: Int = DEFAULT_LOOKUP_PAGE_SIZE,
    private val permissionMapper: HealthWorkoutPermissionMapper =
        AndroidHealthWorkoutPermissionMapper,
) : HealthWorkoutOperationsContract {
    constructor(
        client: HealthConnectClient,
        appPackageName: String,
        lookupPageSize: Int = DEFAULT_LOOKUP_PAGE_SIZE,
        permissionMapper: HealthWorkoutPermissionMapper = AndroidHealthWorkoutPermissionMapper,
    ) : this(AndroidHealthWorkoutClient(client), appPackageName, lookupPageSize, permissionMapper)

    override suspend fun write(request: WorkoutWriteRequest): WorkoutWriteResultPayload {
        val energyExpected = request.energyClientRecordId != null
        if (!isValidWriteRequest(request)) {
            return WorkoutWriteResultPayload.invalidInput(energyExpected)
        }

        val grantedPermissions =
            try {
                client.permissionController.getGrantedPermissions()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                return WorkoutWriteResultPayload.unavailable(
                    energyExpected = energyExpected,
                    platformCode = PERMISSION_PREFLIGHT_FAILED,
                )
            }

        if (writeExercisePermission !in grantedPermissions) {
            return blockedWorkoutPermission(energyExpected)
        }

        val includeEnergy = energyExpected && writeEnergyPermission in grantedPermissions
        val records =
            try {
                buildRecords(request, includeEnergy)
            } catch (_: IllegalArgumentException) {
                return WorkoutWriteResultPayload.invalidInput(energyExpected)
            }

        return insertInitialBatch(
            request = request,
            records = records,
            energyExpected = energyExpected,
            includedEnergy = includeEnergy,
        )
    }

    override suspend fun lookup(request: WorkoutLookupRequest): WorkoutLookupResultPayload {
        val timeRangeFilter = lookupTimeRangeFilter(request)
            ?: return WorkoutLookupResultPayload.unavailable(
                energyExpected = request.energyClientRecordId != null,
                platformCode = INVALID_TIME_RANGE,
            )
        val workout = lookupWorkout(request, timeRangeFilter)
        val energy =
            request.energyClientRecordId?.let { clientRecordId ->
                lookupEnergy(request, clientRecordId, timeRangeFilter)
            } ?: ComponentLookupOutcome(
                component = ComponentLookupPayload(ComponentLookupStatus.NOT_EXPECTED),
            )
        return WorkoutLookupResultPayload(
            workout = workout.component,
            energy = energy.component,
            derivedStatus = deriveLookupStatus(workout.component.status, energy.component.status),
            platformCode = workout.platformCode ?: energy.platformCode,
        )
    }

    override suspend fun authorizationSnapshot(types: List<String>): AuthorizationSnapshotPayload {
        val grantedPermissions =
            try {
                client.permissionController.getGrantedPermissions()
            } catch (_: CancellationException) {
                return AuthorizationSnapshotPayload.unavailable(
                    types,
                    AUTHORIZATION_PERMISSION_CHECK_CANCELED,
                )
            } catch (_: Exception) {
                return AuthorizationSnapshotPayload.unavailable(
                    types,
                    AUTHORIZATION_PERMISSION_CHECK_FAILED,
                )
            }

        return AuthorizationSnapshotPayload(
            available = true,
            types =
                types.map { type ->
                    val recordType = HealthConstants.mapToType[type]
                    if (recordType == null) {
                        TypeAuthorizationPayload(
                            type = type,
                            read = AuthorizationState.UNSUPPORTED,
                            write = AuthorizationState.UNSUPPORTED,
                        )
                    } else {
                        TypeAuthorizationPayload(
                            type = type,
                            read =
                                permissionState(grantedPermissions) {
                                    permissionMapper.readPermission(recordType)
                                },
                            write =
                                permissionState(grantedPermissions) {
                                    permissionMapper.writePermission(recordType)
                                },
                        )
                    }
                },
        )
    }

    private inline fun permissionState(
        grantedPermissions: Set<String>,
        permission: () -> String,
    ): AuthorizationState =
        try {
            if (permission() in grantedPermissions) {
                AuthorizationState.AUTHORIZED
            } else {
                AuthorizationState.DENIED
            }
        } catch (_: Exception) {
            AuthorizationState.UNSUPPORTED
        }

    private fun lookupTimeRangeFilter(request: WorkoutLookupRequest): TimeRangeFilter? =
        try {
            // Health Connect's end is exclusive; one nanosecond includes the frozen record end
            // while the exact range check below prevents the adjustment from widening identity.
            TimeRangeFilter.between(request.startTime, request.endTime.plusNanos(1))
        } catch (_: DateTimeException) {
            null
        } catch (_: ArithmeticException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }

    private suspend fun lookupWorkout(
        request: WorkoutLookupRequest,
        timeRangeFilter: TimeRangeFilter,
    ): ComponentLookupOutcome {
        writePermissionFailure(writeExercisePermission)?.let { return it }

        return try {
            var pageToken: String? = null
            var match: ExerciseSessionRecord? = null
            var multipleMatches = false
            do {
                val response =
                    client.readWorkouts(
                        ReadRecordsRequest(
                            recordType = ExerciseSessionRecord::class,
                            timeRangeFilter = timeRangeFilter,
                            dataOriginFilter = setOf(DataOrigin(appPackageName)),
                            pageSize = lookupPageSize,
                            pageToken = pageToken,
                        )
                    )
                response.records.forEach { record ->
                    if (
                        record.metadata.clientRecordId == request.workoutClientRecordId &&
                            record.startTime == request.startTime &&
                            record.endTime == request.endTime
                    ) {
                        if (match == null) {
                            match = record
                        } else {
                            multipleMatches = true
                        }
                    }
                }
                pageToken = response.pageToken
            } while (pageToken != null)
            if (multipleMatches) {
                ComponentLookupOutcome.unavailable(MULTIPLE_MATCHING_RECORDS)
            } else {
                match.toLookupOutcome()
            }
        } catch (error: Exception) {
            ComponentLookupOutcome.unavailable(lookupFailureCode(error))
        }
    }

    private suspend fun lookupEnergy(
        request: WorkoutLookupRequest,
        clientRecordId: String,
        timeRangeFilter: TimeRangeFilter,
    ): ComponentLookupOutcome {
        writePermissionFailure(writeEnergyPermission)?.let { return it }

        return try {
            var pageToken: String? = null
            var match: ActiveCaloriesBurnedRecord? = null
            var multipleMatches = false
            do {
                val response =
                    client.readEnergy(
                        ReadRecordsRequest(
                            recordType = ActiveCaloriesBurnedRecord::class,
                            timeRangeFilter = timeRangeFilter,
                            dataOriginFilter = setOf(DataOrigin(appPackageName)),
                            pageSize = lookupPageSize,
                            pageToken = pageToken,
                        )
                    )
                response.records.forEach { record ->
                    if (
                        record.metadata.clientRecordId == clientRecordId &&
                            record.startTime == request.startTime &&
                            record.endTime == request.endTime
                    ) {
                        if (match == null) {
                            match = record
                        } else {
                            multipleMatches = true
                        }
                    }
                }
                pageToken = response.pageToken
            } while (pageToken != null)
            if (multipleMatches) {
                ComponentLookupOutcome.unavailable(MULTIPLE_MATCHING_RECORDS)
            } else {
                match.toLookupOutcome()
            }
        } catch (error: Exception) {
            ComponentLookupOutcome.unavailable(lookupFailureCode(error))
        }
    }

    private suspend fun writePermissionFailure(permission: String): ComponentLookupOutcome? {
        val grantedPermissions =
            try {
                client.permissionController.getGrantedPermissions()
            } catch (_: Exception) {
                return ComponentLookupOutcome.unavailable(PERMISSION_CHECK_FAILED)
            }
        return if (permission in grantedPermissions) {
            null
        } else {
            ComponentLookupOutcome.unavailable(WRITE_PERMISSION_DENIED)
        }
    }

    private fun lookupFailureCode(error: Exception): String =
        when (error) {
            is CancellationException -> LOOKUP_CANCELED
            is SecurityException -> LOOKUP_SECURITY_FAILURE
            is RemoteException -> LOOKUP_REMOTE_FAILURE
            is IOException -> LOOKUP_IO_FAILURE
            is IllegalStateException -> HISTORY_WINDOW_UNAVAILABLE
            else -> LOOKUP_FAILED
        }

    private fun Record?.toLookupOutcome(): ComponentLookupOutcome {
        if (this == null) {
            return ComponentLookupOutcome(
                component = ComponentLookupPayload(ComponentLookupStatus.ABSENT),
            )
        }
        val nativeId = metadata.id
        return if (nativeId.isBlank()) {
            ComponentLookupOutcome.unavailable(LOOKUP_FAILED)
        } else {
            ComponentLookupOutcome(
                component = ComponentLookupPayload(ComponentLookupStatus.PRESENT, nativeId),
            )
        }
    }

    private fun deriveLookupStatus(
        workout: ComponentLookupStatus,
        energy: ComponentLookupStatus,
    ): WorkoutLookupStatus =
        when {
            workout == ComponentLookupStatus.UNAVAILABLE -> WorkoutLookupStatus.UNAVAILABLE
            workout == ComponentLookupStatus.ABSENT && energy == ComponentLookupStatus.UNAVAILABLE ->
                WorkoutLookupStatus.UNAVAILABLE
            workout == ComponentLookupStatus.ABSENT && energy == ComponentLookupStatus.PRESENT ->
                WorkoutLookupStatus.INCONSISTENT
            workout == ComponentLookupStatus.ABSENT -> WorkoutLookupStatus.ABSENT
            workout == ComponentLookupStatus.PRESENT && energy == ComponentLookupStatus.UNAVAILABLE ->
                WorkoutLookupStatus.UNAVAILABLE
            workout == ComponentLookupStatus.PRESENT && energy == ComponentLookupStatus.PRESENT ->
                WorkoutLookupStatus.PRESENT
            else -> WorkoutLookupStatus.WORKOUT_ONLY
        }

    private suspend fun insertInitialBatch(
        request: WorkoutWriteRequest,
        records: List<Record>,
        energyExpected: Boolean,
        includedEnergy: Boolean,
    ): WorkoutWriteResultPayload =
        try {
            successfulWriteResult(
                response = client.insertRecords(records),
                expectedRecordCount = records.size,
                energyExpected = energyExpected,
                includedEnergy = includedEnergy,
            )
        } catch (_: CancellationException) {
            verificationRequired(energyExpected, includedEnergy, CANCELED_AFTER_DISPATCH)
        } catch (_: SecurityException) {
            recoverFromSecurityRace(request, energyExpected, includedEnergy)
        } catch (_: RemoteException) {
            verificationRequired(energyExpected, includedEnergy, REMOTE_INSERT_FAILURE)
        } catch (_: IOException) {
            verificationRequired(energyExpected, includedEnergy, IO_INSERT_FAILURE)
        } catch (_: IllegalArgumentException) {
            WorkoutWriteResultPayload.invalidInput(energyExpected)
        } catch (_: IllegalStateException) {
            verificationRequired(energyExpected, includedEnergy, INTERNAL_INSERT_FAILURE)
        } catch (_: Exception) {
            verificationRequired(energyExpected, includedEnergy, UNKNOWN_INSERT_FAILURE)
        }

    private suspend fun recoverFromSecurityRace(
        request: WorkoutWriteRequest,
        energyExpected: Boolean,
        includedEnergy: Boolean,
    ): WorkoutWriteResultPayload {
        val refreshedPermissions =
            try {
                client.permissionController.getGrantedPermissions()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                return WorkoutWriteResultPayload.unavailable(
                    energyExpected = energyExpected,
                    platformCode = PERMISSION_REFRESH_FAILED,
                )
            }

        if (writeExercisePermission !in refreshedPermissions) {
            return blockedWorkoutPermission(energyExpected)
        }

        val energyWasRevoked =
            energyExpected && includedEnergy && writeEnergyPermission !in refreshedPermissions
        if (!energyWasRevoked) {
            return transientFailure(energyExpected, SECURITY_FAILURE)
        }

        val workoutOnly =
            try {
                listOf<Record>(buildWorkoutRecord(request))
            } catch (_: IllegalArgumentException) {
                return WorkoutWriteResultPayload.invalidInput(energyExpected)
            }

        return try {
            successfulWriteResult(
                response = client.insertRecords(workoutOnly),
                expectedRecordCount = 1,
                energyExpected = true,
                includedEnergy = false,
            )
        } catch (_: CancellationException) {
            verificationRequired(
                energyExpected = true,
                includedEnergy = false,
                platformCode = CANCELED_AFTER_DISPATCH,
            )
        } catch (_: SecurityException) {
            resultAfterFinalSecurityFailure(energyExpected)
        } catch (_: RemoteException) {
            verificationRequired(energyExpected = true, includedEnergy = false, REMOTE_INSERT_FAILURE)
        } catch (_: IOException) {
            verificationRequired(energyExpected = true, includedEnergy = false, IO_INSERT_FAILURE)
        } catch (_: IllegalArgumentException) {
            WorkoutWriteResultPayload.invalidInput(energyExpected)
        } catch (_: IllegalStateException) {
            verificationRequired(
                energyExpected = true,
                includedEnergy = false,
                platformCode = INTERNAL_INSERT_FAILURE,
            )
        } catch (_: Exception) {
            verificationRequired(
                energyExpected = true,
                includedEnergy = false,
                platformCode = UNKNOWN_INSERT_FAILURE,
            )
        }
    }

    private suspend fun resultAfterFinalSecurityFailure(
        energyExpected: Boolean
    ): WorkoutWriteResultPayload {
        val refreshedPermissions =
            try {
                client.permissionController.getGrantedPermissions()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                return WorkoutWriteResultPayload.unavailable(
                    energyExpected = energyExpected,
                    platformCode = PERMISSION_REFRESH_FAILED,
                )
            }
        return if (writeExercisePermission in refreshedPermissions) {
            transientFailure(energyExpected, SECURITY_RETRY_FAILED)
        } else {
            blockedWorkoutPermission(energyExpected)
        }
    }

    private fun successfulWriteResult(
        response: InsertRecordsResponse,
        expectedRecordCount: Int,
        energyExpected: Boolean,
        includedEnergy: Boolean,
    ): WorkoutWriteResultPayload {
        val ids = response.recordIdsList
        if (
            ids.size != expectedRecordCount ||
                ids.any { it.isBlank() } ||
                ids.toSet().size != ids.size
        ) {
            return verificationRequired(
                energyExpected = energyExpected,
                includedEnergy = includedEnergy,
                platformCode = INSERT_ID_MISMATCH,
            )
        }

        return WorkoutWriteResultPayload(
            status =
                if (energyExpected && !includedEnergy) {
                    WorkoutWriteStatus.WRITTEN_WITHOUT_ENERGY
                } else {
                    WorkoutWriteStatus.WRITTEN
                },
            workoutRecordId = ids[0],
            energyRecordId = if (includedEnergy) ids[1] else null,
            energyStatus =
                when {
                    includedEnergy -> EnergyWriteStatus.WRITTEN
                    energyExpected -> EnergyWriteStatus.OMITTED_PERMISSION
                    else -> EnergyWriteStatus.NOT_EXPECTED
                },
            retryable = false,
            submissionCertainty = SubmissionCertainty.SUBMITTED,
        )
    }

    private fun buildRecords(
        request: WorkoutWriteRequest,
        includeEnergy: Boolean,
    ): List<Record> =
        buildList {
            add(buildWorkoutRecord(request))
            if (includeEnergy) {
                add(buildEnergyRecord(request))
            }
        }

    private fun buildWorkoutRecord(request: WorkoutWriteRequest): ExerciseSessionRecord =
        ExerciseSessionRecord(
            startTime = request.startTime,
            startZoneOffset = ZoneOffset.ofTotalSeconds(request.startZoneOffsetSeconds),
            endTime = request.endTime,
            endZoneOffset = ZoneOffset.ofTotalSeconds(request.endZoneOffsetSeconds),
            metadata = metadataFor(request, request.workoutClientRecordId),
            exerciseType = HealthConstants.workoutTypeMap.getValue(request.activityType),
            title = request.title,
        )

    private fun buildEnergyRecord(request: WorkoutWriteRequest): ActiveCaloriesBurnedRecord =
        ActiveCaloriesBurnedRecord(
            startTime = request.startTime,
            startZoneOffset = ZoneOffset.ofTotalSeconds(request.startZoneOffsetSeconds),
            endTime = request.endTime,
            endZoneOffset = ZoneOffset.ofTotalSeconds(request.endZoneOffsetSeconds),
            energy = Energy.kilocalories(requireNotNull(request.activeEnergyKcal)),
            metadata = metadataFor(request, requireNotNull(request.energyClientRecordId)),
        )

    private fun metadataFor(
        request: WorkoutWriteRequest,
        clientRecordId: String,
    ): Metadata {
        val device =
            Device(
                type =
                    when (request.recordingDevice) {
                        RecordingDevice.PHONE -> Device.TYPE_PHONE
                        RecordingDevice.WATCH -> Device.TYPE_WATCH
                    }
            )
        return when (request.recordingProvenance) {
            RecordingProvenance.ACTIVELY_RECORDED ->
                Metadata.activelyRecorded(
                    device = device,
                    clientRecordId = clientRecordId,
                    clientRecordVersion = 0,
                )
            RecordingProvenance.MANUAL_ENTRY ->
                Metadata.manualEntry(
                    device = device,
                    clientRecordId = clientRecordId,
                    clientRecordVersion = 0,
                )
        }
    }

    private fun isValidWriteRequest(request: WorkoutWriteRequest): Boolean {
        if (
            request.clientRecordVersion != 0L ||
                request.activityType !in HealthConstants.workoutTypeMap ||
                !request.endTime.isAfter(request.startTime) ||
                request.title.isBlank() ||
                ((request.energyClientRecordId == null) != (request.activeEnergyKcal == null)) ||
                (request.activeEnergyKcal != null &&
                    (!request.activeEnergyKcal.isFinite() || request.activeEnergyKcal <= 0.0))
        ) {
            return false
        }
        return try {
            ZoneOffset.ofTotalSeconds(request.startZoneOffsetSeconds)
            ZoneOffset.ofTotalSeconds(request.endZoneOffsetSeconds)
            true
        } catch (_: DateTimeException) {
            false
        }
    }

    private fun blockedWorkoutPermission(energyExpected: Boolean): WorkoutWriteResultPayload =
        WorkoutWriteResultPayload(
            status = WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION,
            energyStatus =
                if (energyExpected) EnergyWriteStatus.NOT_SUBMITTED
                else EnergyWriteStatus.NOT_EXPECTED,
            retryable = false,
            submissionCertainty = SubmissionCertainty.NOT_SUBMITTED,
            platformCode = WORKOUT_PERMISSION_MISSING,
        )

    private fun transientFailure(
        energyExpected: Boolean,
        platformCode: String,
    ): WorkoutWriteResultPayload =
        WorkoutWriteResultPayload(
            status = WorkoutWriteStatus.TRANSIENT_FAILURE,
            energyStatus =
                if (energyExpected) EnergyWriteStatus.NOT_SUBMITTED
                else EnergyWriteStatus.NOT_EXPECTED,
            retryable = true,
            submissionCertainty = SubmissionCertainty.NOT_SUBMITTED,
            platformCode = platformCode,
        )

    private fun verificationRequired(
        energyExpected: Boolean,
        includedEnergy: Boolean,
        platformCode: String,
    ): WorkoutWriteResultPayload =
        WorkoutWriteResultPayload(
            status = WorkoutWriteStatus.VERIFICATION_REQUIRED,
            energyStatus =
                when {
                    includedEnergy -> EnergyWriteStatus.VERIFICATION_REQUIRED
                    energyExpected -> EnergyWriteStatus.OMITTED_PERMISSION
                    else -> EnergyWriteStatus.NOT_EXPECTED
                },
            retryable = false,
            submissionCertainty = SubmissionCertainty.MAY_HAVE_SUBMITTED,
            platformCode = platformCode,
        )

    private companion object {
        const val DEFAULT_LOOKUP_PAGE_SIZE = 1_000
        val writeExercisePermission =
            HealthPermission.getWritePermission(ExerciseSessionRecord::class)
        val writeEnergyPermission =
            HealthPermission.getWritePermission(ActiveCaloriesBurnedRecord::class)

        const val PERMISSION_PREFLIGHT_FAILED = "permissionPreflightFailed"
        const val PERMISSION_REFRESH_FAILED = "permissionRefreshFailed"
        const val WORKOUT_PERMISSION_MISSING = "workoutPermissionMissing"
        const val SECURITY_FAILURE = "securityFailure"
        const val SECURITY_RETRY_FAILED = "securityRetryFailed"
        const val REMOTE_INSERT_FAILURE = "remoteInsertFailure"
        const val IO_INSERT_FAILURE = "ioInsertFailure"
        const val CANCELED_AFTER_DISPATCH = "canceledAfterDispatch"
        const val INTERNAL_INSERT_FAILURE = "internalInsertFailure"
        const val UNKNOWN_INSERT_FAILURE = "unknownInsertFailure"
        const val INSERT_ID_MISMATCH = "insertIdMismatch"
        const val WRITE_PERMISSION_DENIED = "writePermissionDenied"
        const val PERMISSION_CHECK_FAILED = "permissionCheckFailed"
        const val LOOKUP_FAILED = "lookupFailed"
        const val HISTORY_WINDOW_UNAVAILABLE = "historyWindowUnavailable"
        const val LOOKUP_SECURITY_FAILURE = "lookupSecurityFailure"
        const val LOOKUP_REMOTE_FAILURE = "lookupRemoteFailure"
        const val LOOKUP_IO_FAILURE = "lookupIoFailure"
        const val LOOKUP_CANCELED = "lookupCanceled"
        const val MULTIPLE_MATCHING_RECORDS = "multipleMatchingRecords"
        const val INVALID_TIME_RANGE = "invalidTimeRange"
        const val AUTHORIZATION_PERMISSION_CHECK_FAILED =
            "authorizationPermissionCheckFailed"
        const val AUTHORIZATION_PERMISSION_CHECK_CANCELED =
            "authorizationPermissionCheckCanceled"
    }
}

private data class ComponentLookupOutcome(
    val component: ComponentLookupPayload,
    val platformCode: String? = null,
) {
    companion object {
        fun unavailable(platformCode: String): ComponentLookupOutcome =
            ComponentLookupOutcome(
                component = ComponentLookupPayload(ComponentLookupStatus.UNAVAILABLE),
                platformCode = platformCode,
            )
    }
}
