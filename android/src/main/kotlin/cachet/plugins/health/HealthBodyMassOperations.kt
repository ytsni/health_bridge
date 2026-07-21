package cachet.plugins.health

import android.content.Context
import android.os.RemoteException
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.time.TimeRangeFilter
import java.io.IOException
import java.time.DateTimeException
import java.time.Instant
import kotlinx.coroutines.CancellationException

internal enum class BodyMassLookupStatus(val wireName: String) {
    PRESENT("present"),
    ABSENT("absent"),
    UNAVAILABLE("unavailable"),
}

internal class BodyMassLookupPayloadException(message: String) : IllegalArgumentException(message)

internal data class BodyMassLookupRequest(
    val clientRecordId: String,
    val measuredAt: Instant,
) {
    companion object {
        fun fromMap(arguments: Any?): BodyMassLookupRequest {
            val map = arguments as? Map<*, *>
                ?: throw BodyMassLookupPayloadException("arguments must be a map")
            if (map.keys.any { it !is String } || map.keys != BODY_MASS_ARGUMENT_KEYS) {
                throw BodyMassLookupPayloadException("arguments must contain exactly clientRecordId and measuredAt")
            }
            val clientRecordId = (map["clientRecordId"] as? String)?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: throw BodyMassLookupPayloadException("clientRecordId must be nonblank")
            val milliseconds =
                when (val value = map["measuredAt"]) {
                    is Byte -> value.toLong()
                    is Short -> value.toLong()
                    is Int -> value.toLong()
                    is Long -> value
                    else -> throw BodyMassLookupPayloadException("measuredAt must be an integer")
                }
            val measuredAt =
                try {
                    Instant.ofEpochMilli(milliseconds)
                } catch (_: DateTimeException) {
                    throw BodyMassLookupPayloadException("measuredAt is not representable")
                }
            return BodyMassLookupRequest(clientRecordId = clientRecordId, measuredAt = measuredAt)
        }
    }
}

internal data class BodyMassLookupResultPayload(
    val status: BodyMassLookupStatus,
    val recordId: String? = null,
    val platformCode: String? = null,
) {
    init {
        require(recordId == null || recordId.isNotBlank()) { "recordId must be nonblank when present" }
        require(platformCode == null || platformCode.isNotBlank()) {
            "platformCode must be nonblank when present"
        }
        require((status == BodyMassLookupStatus.PRESENT) == (recordId != null)) {
            "recordId must exist only for a present body-mass lookup"
        }
    }

    fun toMap(): Map<String, Any?> =
        mapOf(
            "status" to status.wireName,
            "recordId" to recordId,
            "platformCode" to platformCode,
        )

    companion object {
        fun unavailable(platformCode: String): BodyMassLookupResultPayload =
            BodyMassLookupResultPayload(
                status = BodyMassLookupStatus.UNAVAILABLE,
                platformCode = platformCode,
            )
    }
}

internal interface HealthBodyMassOperationsContract {
    suspend fun lookup(request: BodyMassLookupRequest): BodyMassLookupResultPayload
}

internal interface HealthBodyMassClient {
    suspend fun readWeights(
        request: ReadRecordsRequest<WeightRecord>
    ): ReadRecordsResponse<WeightRecord>
}

internal class AndroidHealthBodyMassClient(
    private val delegate: HealthConnectClient,
) : HealthBodyMassClient {
    override suspend fun readWeights(
        request: ReadRecordsRequest<WeightRecord>
    ): ReadRecordsResponse<WeightRecord> = delegate.readRecords(request)
}

/** A capability-isolated lookup for API 34 extension 7 and newer devices. */
internal interface HealthBodyMassDirectLookup {
    val isAvailable: Boolean

    suspend fun lookup(clientRecordId: String): BodyMassLookupResultPayload
}

internal class HealthBodyMassOperations(
    private val client: HealthBodyMassClient,
    private val appPackageName: String,
    private val directLookup: HealthBodyMassDirectLookup = UnavailableBodyMassDirectLookup,
) : HealthBodyMassOperationsContract {
    constructor(
        client: HealthConnectClient,
        context: Context,
        appPackageName: String,
    ) : this(
        client = AndroidHealthBodyMassClient(client),
        appPackageName = appPackageName,
        directLookup = PlatformHealthBodyMassDirectLookupFactory.create(context, appPackageName),
    )

    override suspend fun lookup(request: BodyMassLookupRequest): BodyMassLookupResultPayload {
        if (directLookup.isAvailable) {
            return directLookup.lookup(request.clientRecordId)
        }
        return lookupWithBoundedFallback(request)
    }

    private suspend fun lookupWithBoundedFallback(
        request: BodyMassLookupRequest,
    ): BodyMassLookupResultPayload {
        val timeRangeFilter =
            try {
                TimeRangeFilter.between(
                    request.measuredAt.minusSeconds(LOOKUP_WINDOW_SECONDS),
                    request.measuredAt.plusSeconds(LOOKUP_WINDOW_SECONDS),
                )
            } catch (_: DateTimeException) {
                return BodyMassLookupResultPayload.unavailable(LOOKUP_BOUND_EXCEEDED)
            } catch (_: ArithmeticException) {
                return BodyMassLookupResultPayload.unavailable(LOOKUP_BOUND_EXCEEDED)
            }

        return try {
            var pageToken: String? = null
            var inspectedRecords = 0
            repeat(MAX_LOOKUP_PAGES) { pageIndex ->
                val response =
                    client.readWeights(
                        ReadRecordsRequest(
                            recordType = WeightRecord::class,
                            timeRangeFilter = timeRangeFilter,
                            dataOriginFilter = setOf(DataOrigin(appPackageName)),
                            pageSize = LOOKUP_PAGE_SIZE,
                            pageToken = pageToken,
                        )
                    )
                val matches = response.records.filter {
                    it.metadata.clientRecordId == request.clientRecordId
                }
                if (matches.size > 1) {
                    return BodyMassLookupResultPayload.unavailable(MULTIPLE_MATCHING_RECORDS)
                }
                matches.singleOrNull()?.let { record ->
                    return record.toPresentLookup()
                }

                inspectedRecords += response.records.size
                val nextPageToken = response.pageToken
                // A terminal response is complete evidence of absence, even if it
                // exactly fills the inspection budget. Only an unvisited page makes
                // the bounded result inconclusive.
                if (nextPageToken == null) {
                    return BodyMassLookupResultPayload(status = BodyMassLookupStatus.ABSENT)
                }
                if (inspectedRecords >= MAX_INSPECTED_RECORDS) {
                    return BodyMassLookupResultPayload.unavailable(LOOKUP_BOUND_EXCEEDED)
                }
                if (pageIndex == MAX_LOOKUP_PAGES - 1) {
                    return BodyMassLookupResultPayload.unavailable(LOOKUP_BOUND_EXCEEDED)
                }
                pageToken = nextPageToken
            }
            BodyMassLookupResultPayload.unavailable(LOOKUP_BOUND_EXCEEDED)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            BodyMassLookupResultPayload.unavailable(fallbackFailureCode(error))
        }
    }

    private fun WeightRecord.toPresentLookup(): BodyMassLookupResultPayload {
        val nativeId = metadata.id
        return if (nativeId.isBlank()) {
            BodyMassLookupResultPayload.unavailable(LOOKUP_FAILED)
        } else {
            BodyMassLookupResultPayload(
                status = BodyMassLookupStatus.PRESENT,
                recordId = nativeId,
            )
        }
    }
}

internal object UnavailableBodyMassDirectLookup : HealthBodyMassDirectLookup {
    override val isAvailable: Boolean = false

    override suspend fun lookup(clientRecordId: String): BodyMassLookupResultPayload =
        BodyMassLookupResultPayload.unavailable(LOOKUP_FAILED)
}

internal fun supportsDirectBodyMassLookup(sdkInt: Int, extensionVersion: Int): Boolean =
    sdkInt >= DIRECT_LOOKUP_MINIMUM_SDK && extensionVersion >= MINIMUM_DIRECT_LOOKUP_EXTENSION

internal fun fallbackFailureCode(error: Exception): String =
    when (error) {
        is IllegalStateException -> HISTORY_WINDOW_UNAVAILABLE
        is SecurityException -> LOOKUP_SECURITY_FAILURE
        is RemoteException -> LOOKUP_REMOTE_FAILURE
        is IOException -> LOOKUP_IO_FAILURE
        else -> LOOKUP_FAILED
    }

private const val LOOKUP_WINDOW_SECONDS = 60L
private const val LOOKUP_PAGE_SIZE = 100
private const val MAX_LOOKUP_PAGES = 2
private const val MAX_INSPECTED_RECORDS = 200
internal const val DIRECT_LOOKUP_MINIMUM_SDK = 34
internal const val MINIMUM_DIRECT_LOOKUP_EXTENSION = 7
private const val HISTORY_WINDOW_UNAVAILABLE = "historyWindowUnavailable"
private const val LOOKUP_BOUND_EXCEEDED = "lookupBoundExceeded"
private const val LOOKUP_SECURITY_FAILURE = "lookupSecurityFailure"
private const val LOOKUP_REMOTE_FAILURE = "lookupRemoteFailure"
private const val LOOKUP_IO_FAILURE = "lookupIoFailure"
internal const val LOOKUP_FAILED = "lookupFailed"
internal const val MULTIPLE_MATCHING_RECORDS = "multipleMatchingRecords"
private val BODY_MASS_ARGUMENT_KEYS = setOf("clientRecordId", "measuredAt")
