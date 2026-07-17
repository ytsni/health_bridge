package cachet.plugins.health

import java.time.DateTimeException
import java.time.Instant
import java.time.ZoneOffset

internal class WorkoutPayloadException(message: String) : IllegalArgumentException(message)

internal enum class RecordingProvenance(val wireName: String) {
    ACTIVELY_RECORDED("activelyRecorded"),
    MANUAL_ENTRY("manualEntry");

    companion object {
        fun fromWire(value: Any?): RecordingProvenance =
            entries.firstOrNull { it.wireName == value }
                ?: throw WorkoutPayloadException("recordingProvenance is invalid")
    }
}

internal enum class RecordingDevice(val wireName: String) {
    PHONE("phone"),
    WATCH("watch");

    companion object {
        fun fromWire(value: Any?): RecordingDevice =
            entries.firstOrNull { it.wireName == value }
                ?: throw WorkoutPayloadException("recordingDevice is invalid")
    }
}

internal enum class WorkoutWriteStatus(val wireName: String) {
    WRITTEN("written"),
    ALREADY_PRESENT("alreadyPresent"),
    WRITTEN_WITHOUT_ENERGY("writtenWithoutEnergy"),
    BLOCKED_WORKOUT_PERMISSION("blockedWorkoutPermission"),
    VERIFICATION_REQUIRED("verificationRequired"),
    INCONSISTENT_NATIVE_STATE("inconsistentNativeState"),
    TRANSIENT_FAILURE("transientFailure"),
    INVALID_INPUT("invalidInput"),
    UNAVAILABLE("unavailable"),
}

internal enum class EnergyWriteStatus(val wireName: String) {
    NOT_EXPECTED("notExpected"),
    WRITTEN("written"),
    ALREADY_PRESENT("alreadyPresent"),
    OMITTED_PERMISSION("omittedPermission"),
    ABSENT("absent"),
    NOT_SUBMITTED("notSubmitted"),
    VERIFICATION_REQUIRED("verificationRequired"),
}

internal enum class SubmissionCertainty(val wireName: String) {
    NOT_SUBMITTED("notSubmitted"),
    MAY_HAVE_SUBMITTED("mayHaveSubmitted"),
    SUBMITTED("submitted"),
}

internal enum class ComponentLookupStatus(val wireName: String) {
    PRESENT("present"),
    ABSENT("absent"),
    UNAVAILABLE("unavailable"),
    NOT_EXPECTED("notExpected"),
}

internal enum class WorkoutLookupStatus(val wireName: String) {
    PRESENT("present"),
    WORKOUT_ONLY("workoutOnly"),
    ABSENT("absent"),
    UNAVAILABLE("unavailable"),
    INCONSISTENT("inconsistent"),
}

internal enum class AuthorizationState(val wireName: String) {
    AUTHORIZED("authorized"),
    DENIED("denied"),
    NOT_DETERMINED("notDetermined"),
    REQUESTED_OR_UNKNOWN("requestedOrUnknown"),
    UNAVAILABLE("unavailable"),
    UNSUPPORTED("unsupported"),
}

internal data class WorkoutWriteRequest(
    val workoutClientRecordId: String,
    val energyClientRecordId: String?,
    val clientRecordVersion: Long,
    val activityType: String,
    val startTime: Instant,
    val endTime: Instant,
    val startZoneOffsetSeconds: Int,
    val endZoneOffsetSeconds: Int,
    val activeEnergyKcal: Double?,
    val title: String,
    val recordingProvenance: RecordingProvenance,
    val recordingDevice: RecordingDevice,
) {
    companion object {
        fun fromMap(arguments: Any?): WorkoutWriteRequest {
            val map = strictMap(arguments)
            val workoutClientRecordId = requiredUuid(map, "workoutClientRecordId")
            val energyClientRecordId = optionalUuid(map, "energyClientRecordId")
            val clientRecordVersion = requiredLong(map, "clientRecordVersion")
            if (clientRecordVersion != 0L) {
                throw WorkoutPayloadException("clientRecordVersion must be 0")
            }

            val activityType = requiredString(map, "activityType")
            if (!HealthConstants.workoutTypeMap.containsKey(activityType)) {
                throw WorkoutPayloadException("activityType is unsupported")
            }

            val startTime = Instant.ofEpochMilli(requiredLong(map, "startTime"))
            val endTime = Instant.ofEpochMilli(requiredLong(map, "endTime"))
            validateRange(startTime, endTime)

            val startZoneOffsetSeconds = requiredZoneOffsetSeconds(map, "startZoneOffsetSeconds")
            val endZoneOffsetSeconds = requiredZoneOffsetSeconds(map, "endZoneOffsetSeconds")
            val activeEnergyKcal = optionalDouble(map, "activeEnergyKcal")
            if ((energyClientRecordId == null) != (activeEnergyKcal == null)) {
                throw WorkoutPayloadException("activeEnergyKcal and energyClientRecordId must be present together")
            }
            if (activeEnergyKcal != null && (!activeEnergyKcal.isFinite() || activeEnergyKcal <= 0.0)) {
                throw WorkoutPayloadException("activeEnergyKcal must be finite and positive")
            }

            val title = requiredString(map, "title").trim()
            if (title.isEmpty()) {
                throw WorkoutPayloadException("title must be nonblank")
            }

            return WorkoutWriteRequest(
                workoutClientRecordId = workoutClientRecordId,
                energyClientRecordId = energyClientRecordId,
                clientRecordVersion = clientRecordVersion,
                activityType = activityType,
                startTime = startTime,
                endTime = endTime,
                startZoneOffsetSeconds = startZoneOffsetSeconds,
                endZoneOffsetSeconds = endZoneOffsetSeconds,
                activeEnergyKcal = activeEnergyKcal,
                title = title,
                recordingProvenance = RecordingProvenance.fromWire(map["recordingProvenance"]),
                recordingDevice = RecordingDevice.fromWire(map["recordingDevice"]),
            )
        }
    }
}

internal data class WorkoutLookupRequest(
    val workoutClientRecordId: String,
    val energyClientRecordId: String?,
    val startTime: Instant,
    val endTime: Instant,
) {
    companion object {
        fun fromMap(arguments: Any?): WorkoutLookupRequest {
            val map = strictMap(arguments)
            val startTime = Instant.ofEpochMilli(requiredLong(map, "startTime"))
            val endTime = Instant.ofEpochMilli(requiredLong(map, "endTime"))
            validateRange(startTime, endTime)
            return WorkoutLookupRequest(
                workoutClientRecordId = requiredUuid(map, "workoutClientRecordId"),
                energyClientRecordId = optionalUuid(map, "energyClientRecordId"),
                startTime = startTime,
                endTime = endTime,
            )
        }
    }
}

internal data class WorkoutWriteResultPayload(
    val status: WorkoutWriteStatus,
    val workoutRecordId: String? = null,
    val energyRecordId: String? = null,
    val energyStatus: EnergyWriteStatus,
    val retryable: Boolean,
    val submissionCertainty: SubmissionCertainty,
    val platformCode: String? = null,
) {
    init {
        requireNonblankOptional(workoutRecordId, "workoutRecordId")
        requireNonblankOptional(energyRecordId, "energyRecordId")
        requireNonblankOptional(platformCode, "platformCode")
        require(isAllowedWriteStatusPair(status, energyStatus)) {
            "${status.wireName} cannot pair with ${energyStatus.wireName}"
        }

        when (energyStatus) {
            EnergyWriteStatus.WRITTEN,
            EnergyWriteStatus.ALREADY_PRESENT ->
                require(energyRecordId != null) {
                    "energyRecordId is required for present energy"
                }
            EnergyWriteStatus.NOT_EXPECTED,
            EnergyWriteStatus.OMITTED_PERMISSION,
            EnergyWriteStatus.ABSENT,
            EnergyWriteStatus.NOT_SUBMITTED,
            EnergyWriteStatus.VERIFICATION_REQUIRED ->
                require(energyRecordId == null) {
                    "energyRecordId is forbidden when energy is not confirmed present"
                }
        }

        when (status) {
            WorkoutWriteStatus.WRITTEN,
            WorkoutWriteStatus.ALREADY_PRESENT,
            WorkoutWriteStatus.WRITTEN_WITHOUT_ENERGY -> {
                require(workoutRecordId != null) {
                    "workoutRecordId is required for ${status.wireName}"
                }
                require(submissionCertainty == SubmissionCertainty.SUBMITTED) {
                    "${status.wireName} must be submitted"
                }
            }
            WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION,
            WorkoutWriteStatus.INVALID_INPUT,
            WorkoutWriteStatus.UNAVAILABLE -> {
                require(workoutRecordId == null && energyRecordId == null) {
                    "${status.wireName} cannot contain record IDs"
                }
                require(submissionCertainty == SubmissionCertainty.NOT_SUBMITTED) {
                    "${status.wireName} must be notSubmitted"
                }
            }
            WorkoutWriteStatus.VERIFICATION_REQUIRED -> {
                require(workoutRecordId == null && energyRecordId == null) {
                    "verificationRequired cannot contain confirmed record IDs"
                }
                require(submissionCertainty == SubmissionCertainty.MAY_HAVE_SUBMITTED) {
                    "verificationRequired must be mayHaveSubmitted"
                }
            }
            WorkoutWriteStatus.INCONSISTENT_NATIVE_STATE -> {
                require(workoutRecordId == null && energyRecordId != null) {
                    "inconsistentNativeState requires energy without a workout"
                }
                require(submissionCertainty == SubmissionCertainty.SUBMITTED) {
                    "inconsistentNativeState must be submitted"
                }
            }
            WorkoutWriteStatus.TRANSIENT_FAILURE -> {
                require(workoutRecordId == null && energyRecordId == null) {
                    "transientFailure cannot contain record IDs"
                }
                require(submissionCertainty == SubmissionCertainty.NOT_SUBMITTED) {
                    "transientFailure must be notSubmitted"
                }
            }
        }
    }

    fun toMap(): Map<String, Any?> =
        mapOf(
            "status" to status.wireName,
            "workoutRecordId" to workoutRecordId,
            "energyRecordId" to energyRecordId,
            "energyStatus" to energyStatus.wireName,
            "retryable" to retryable,
            "submissionCertainty" to submissionCertainty.wireName,
            "platformCode" to platformCode,
        )

    companion object {
        fun invalidInput(energyExpected: Boolean): WorkoutWriteResultPayload =
            WorkoutWriteResultPayload(
                status = WorkoutWriteStatus.INVALID_INPUT,
                energyStatus =
                    if (energyExpected) EnergyWriteStatus.NOT_SUBMITTED
                    else EnergyWriteStatus.NOT_EXPECTED,
                retryable = false,
                submissionCertainty = SubmissionCertainty.NOT_SUBMITTED,
                platformCode = "invalidInput",
            )

        fun unavailable(energyExpected: Boolean, platformCode: String): WorkoutWriteResultPayload =
            WorkoutWriteResultPayload(
                status = WorkoutWriteStatus.UNAVAILABLE,
                energyStatus =
                    if (energyExpected) EnergyWriteStatus.NOT_SUBMITTED
                    else EnergyWriteStatus.NOT_EXPECTED,
                retryable = true,
                submissionCertainty = SubmissionCertainty.NOT_SUBMITTED,
                platformCode = platformCode,
            )
    }
}

internal data class ComponentLookupPayload(
    val status: ComponentLookupStatus,
    val recordId: String? = null,
) {
    init {
        requireNonblankOptional(recordId, "recordId")
        require((status == ComponentLookupStatus.PRESENT) == (recordId != null)) {
            "recordId must exist only for present lookup"
        }
    }

    fun toMap(): Map<String, Any?> =
        mapOf(
            "status" to status.wireName,
            "recordId" to recordId,
        )
}

internal data class WorkoutLookupResultPayload(
    val workout: ComponentLookupPayload,
    val energy: ComponentLookupPayload,
    val derivedStatus: WorkoutLookupStatus,
    val platformCode: String? = null,
) {
    init {
        requireNonblankOptional(platformCode, "platformCode")
        require(workout.status != ComponentLookupStatus.NOT_EXPECTED) {
            "workout lookup cannot be notExpected"
        }
        val expected = deriveWorkoutLookupStatus(workout.status, energy.status)
        require(derivedStatus == expected) {
            "derivedStatus ${derivedStatus.wireName} does not match ${expected.wireName}"
        }
    }

    fun toMap(): Map<String, Any?> =
        mapOf(
            "workout" to workout.toMap(),
            "energy" to energy.toMap(),
            "derivedStatus" to derivedStatus.wireName,
            "platformCode" to platformCode,
        )

    companion object {
        fun unavailable(energyExpected: Boolean, platformCode: String): WorkoutLookupResultPayload =
            WorkoutLookupResultPayload(
                workout = ComponentLookupPayload(ComponentLookupStatus.UNAVAILABLE),
                energy =
                    ComponentLookupPayload(
                        if (energyExpected) ComponentLookupStatus.UNAVAILABLE
                        else ComponentLookupStatus.NOT_EXPECTED
                    ),
                derivedStatus = WorkoutLookupStatus.UNAVAILABLE,
                platformCode = platformCode,
            )
    }
}

internal data class TypeAuthorizationPayload(
    val type: String,
    val read: AuthorizationState,
    val write: AuthorizationState,
) {
    init {
        require(type.isNotBlank()) { "authorization type must be nonblank" }
    }

    fun toMap(): Map<String, Any?> =
        mapOf(
            "type" to type,
            "read" to read.wireName,
            "write" to write.wireName,
        )
}

internal class AuthorizationSnapshotPayload(
    val available: Boolean,
    types: List<TypeAuthorizationPayload>,
    val platformCode: String? = null,
) {
    val types: List<TypeAuthorizationPayload> = types.toList()

    init {
        requireNonblankOptional(platformCode, "platformCode")
        require(this.types.isNotEmpty()) { "authorization types must be nonempty" }
        require(this.types.map { it.type }.toSet().size == this.types.size) {
            "authorization types must be unique"
        }
        if (available) {
            require(
                this.types.none {
                    it.read == AuthorizationState.UNAVAILABLE || it.write == AuthorizationState.UNAVAILABLE
                }
            ) { "available snapshots cannot contain unavailable states" }
        } else {
            require(
                this.types.all {
                    it.read == AuthorizationState.UNAVAILABLE && it.write == AuthorizationState.UNAVAILABLE
                }
            ) { "unavailable snapshots require every component state unavailable" }
        }
    }

    fun toMap(): Map<String, Any?> =
        mapOf(
            "available" to available,
            "types" to types.map { it.toMap() },
            "platformCode" to platformCode,
        )

    companion object {
        fun unavailable(types: List<String>, platformCode: String): AuthorizationSnapshotPayload =
            AuthorizationSnapshotPayload(
                available = false,
                types =
                    types.map { type ->
                        TypeAuthorizationPayload(
                            type = type,
                            read = AuthorizationState.UNAVAILABLE,
                            write = AuthorizationState.UNAVAILABLE,
                        )
                    },
                platformCode = platformCode,
            )
    }
}

internal fun authorizationTypesFromMap(arguments: Any?): List<String> {
    val map = strictMap(arguments)
    val rawTypes = map["types"] as? List<*>
        ?: throw WorkoutPayloadException("types must be a list")
    val types =
        rawTypes.map { value ->
            val type = value as? String
                ?: throw WorkoutPayloadException("authorization type must be a string")
            if (type.isBlank()) {
                throw WorkoutPayloadException("authorization type must be nonblank")
            }
            type
        }
    if (types.isEmpty() || types.toSet().size != types.size) {
        throw WorkoutPayloadException("authorization types must be nonempty and unique")
    }
    return types
}

private val opaqueUuid =
    Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

private fun strictMap(arguments: Any?): Map<*, *> {
    val map = arguments as? Map<*, *> ?: throw WorkoutPayloadException("arguments must be a map")
    if (map.keys.any { it !is String }) {
        throw WorkoutPayloadException("argument keys must be strings")
    }
    return map
}

private fun requiredString(map: Map<*, *>, field: String): String =
    map[field] as? String ?: throw WorkoutPayloadException("$field must be a string")

private fun requiredUuid(map: Map<*, *>, field: String): String {
    val value = requiredString(map, field).trim()
    if (!opaqueUuid.matches(value)) {
        throw WorkoutPayloadException("$field must be a UUID string")
    }
    return value
}

private fun optionalUuid(map: Map<*, *>, field: String): String? {
    val raw = map[field] ?: return null
    val value = raw as? String ?: throw WorkoutPayloadException("$field must be a string")
    val trimmed = value.trim()
    if (!opaqueUuid.matches(trimmed)) {
        throw WorkoutPayloadException("$field must be a UUID string")
    }
    return trimmed
}

private fun requiredLong(map: Map<*, *>, field: String): Long =
    when (val value = map[field]) {
        is Byte -> value.toLong()
        is Short -> value.toLong()
        is Int -> value.toLong()
        is Long -> value
        else -> throw WorkoutPayloadException("$field must be an integer")
    }

private fun optionalDouble(map: Map<*, *>, field: String): Double? =
    when (val value = map[field]) {
        null -> null
        is Byte -> value.toDouble()
        is Short -> value.toDouble()
        is Int -> value.toDouble()
        is Long -> value.toDouble()
        is Float -> value.toDouble()
        is Double -> value
        else -> throw WorkoutPayloadException("$field must be numeric")
    }

private fun requiredZoneOffsetSeconds(map: Map<*, *>, field: String): Int {
    val value = requiredLong(map, field)
    if (value < Int.MIN_VALUE || value > Int.MAX_VALUE) {
        throw WorkoutPayloadException("$field is outside the integer range")
    }
    val seconds = value.toInt()
    try {
        ZoneOffset.ofTotalSeconds(seconds)
    } catch (_: DateTimeException) {
        throw WorkoutPayloadException("$field must be a valid zone offset")
    }
    return seconds
}

private fun validateRange(startTime: Instant, endTime: Instant) {
    if (!endTime.isAfter(startTime)) {
        throw WorkoutPayloadException("endTime must be after startTime")
    }
}

private fun requireNonblankOptional(value: String?, field: String) {
    require(value == null || value.isNotBlank()) { "$field must be nonblank when present" }
}

private fun isAllowedWriteStatusPair(
    status: WorkoutWriteStatus,
    energyStatus: EnergyWriteStatus,
): Boolean =
    when (status) {
        WorkoutWriteStatus.WRITTEN ->
            energyStatus == EnergyWriteStatus.WRITTEN || energyStatus == EnergyWriteStatus.NOT_EXPECTED
        WorkoutWriteStatus.ALREADY_PRESENT ->
            energyStatus == EnergyWriteStatus.ALREADY_PRESENT ||
                energyStatus == EnergyWriteStatus.ABSENT ||
                energyStatus == EnergyWriteStatus.NOT_EXPECTED
        WorkoutWriteStatus.WRITTEN_WITHOUT_ENERGY ->
            energyStatus == EnergyWriteStatus.OMITTED_PERMISSION
        WorkoutWriteStatus.BLOCKED_WORKOUT_PERMISSION ->
            energyStatus == EnergyWriteStatus.NOT_SUBMITTED || energyStatus == EnergyWriteStatus.NOT_EXPECTED
        WorkoutWriteStatus.VERIFICATION_REQUIRED ->
            energyStatus == EnergyWriteStatus.VERIFICATION_REQUIRED ||
                energyStatus == EnergyWriteStatus.OMITTED_PERMISSION ||
                energyStatus == EnergyWriteStatus.NOT_EXPECTED
        WorkoutWriteStatus.INCONSISTENT_NATIVE_STATE ->
            energyStatus == EnergyWriteStatus.ALREADY_PRESENT
        WorkoutWriteStatus.TRANSIENT_FAILURE,
        WorkoutWriteStatus.INVALID_INPUT,
        WorkoutWriteStatus.UNAVAILABLE ->
            energyStatus == EnergyWriteStatus.NOT_SUBMITTED || energyStatus == EnergyWriteStatus.NOT_EXPECTED
    }

private fun deriveWorkoutLookupStatus(
    workout: ComponentLookupStatus,
    energy: ComponentLookupStatus,
): WorkoutLookupStatus {
    require(workout != ComponentLookupStatus.NOT_EXPECTED) {
        "workout lookup cannot be notExpected"
    }
    return when {
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
