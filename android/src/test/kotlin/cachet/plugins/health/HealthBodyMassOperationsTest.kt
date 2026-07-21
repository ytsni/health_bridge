package cachet.plugins.health

import android.os.RemoteException
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.units.Mass
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthBodyMassOperationsTest {
    @Test
    fun lookup_usesDirectClientIdPathOnlyWhenTheGateIsAvailable() = runTest {
        val fallback = FakeBodyMassClient()
        val direct =
            FakeBodyMassDirectLookup(
                isAvailable = true,
                result =
                    BodyMassLookupResultPayload(
                        status = BodyMassLookupStatus.PRESENT,
                        recordId = "native-direct",
                    ),
            )

        val result =
            HealthBodyMassOperations(
                client = fallback,
                appPackageName = APP_PACKAGE,
                directLookup = direct,
            ).lookup(validRequest())

        assertEquals(1, direct.calls)
        assertEquals(BODY_MASS_CLIENT_ID, direct.lastClientRecordId)
        assertTrue(fallback.readRequests.isEmpty())
        assertEquals(BodyMassLookupStatus.PRESENT, result.status)
        assertEquals("native-direct", result.recordId)
    }

    @Test
    fun lookup_usesBoundedFallbackWhenTheDirectGateIsUnavailable() = runTest {
        val fallback =
            FakeBodyMassClient(
                responses =
                    listOf(
                        response(
                            records = listOf(weightRecord(BODY_MASS_CLIENT_ID, "native-fallback")),
                        )
                    ),
            )
        val direct = FakeBodyMassDirectLookup(isAvailable = false)

        val result =
            HealthBodyMassOperations(
                client = fallback,
                appPackageName = APP_PACKAGE,
                directLookup = direct,
            ).lookup(validRequest())

        assertEquals(0, direct.calls)
        assertEquals(1, fallback.readRequests.size)
        assertEquals(BodyMassLookupStatus.PRESENT, result.status)
        assertEquals("native-fallback", result.recordId)
    }

    @Test
    fun directLookupAvailability_requiresApi34AndExtension7() {
        assertFalse(supportsDirectBodyMassLookup(sdkInt = 33, extensionVersion = 7))
        assertFalse(supportsDirectBodyMassLookup(sdkInt = 34, extensionVersion = 6))
        assertTrue(supportsDirectBodyMassLookup(sdkInt = 34, extensionVersion = 7))
    }

    @Test
    fun fallback_usesOnlyTheAppOriginExactMinuteWindowAndPageSize100() = runTest {
        val fallback =
            FakeBodyMassClient(
                responses =
                    listOf(
                        response(
                            records = listOf(
                                weightRecord("other-client-id", "other-id"),
                                weightRecord(BODY_MASS_CLIENT_ID, "native-weight"),
                            ),
                        )
                    ),
            )

        val result = HealthBodyMassOperations(fallback, APP_PACKAGE).lookup(validRequest())

        assertEquals(BodyMassLookupStatus.PRESENT, result.status)
        assertEquals("native-weight", result.recordId)
        val request = fallback.readRequests.single()
        assertEquals(WeightRecord::class, request.recordType)
        assertEquals(setOf(DataOrigin(APP_PACKAGE)), request.dataOriginFilter)
        assertEquals(MEASURED_AT.minusSeconds(60), request.timeRangeFilter.startTime)
        assertEquals(MEASURED_AT.plusSeconds(60), request.timeRangeFilter.endTime)
        assertEquals(100, request.pageSize)
        assertNull(request.pageToken)
    }

    @Test
    fun fallback_returnsAbsentOnlyForACompleteTerminalResponse() = runTest {
        val fallback = FakeBodyMassClient(responses = listOf(response(records = emptyList())))

        val result = HealthBodyMassOperations(fallback, APP_PACKAGE).lookup(validRequest())

        assertEquals(BodyMassLookupStatus.ABSENT, result.status)
        assertNull(result.recordId)
        assertNull(result.platformCode)
    }

    @Test
    fun fallback_returnsUnavailableWhenAThirdPageWouldBeNeeded() = runTest {
        val fallback =
            FakeBodyMassClient(
                responses =
                    listOf(
                        response(records = listOf(weightRecord("first", "native-1")), pageToken = "page-2"),
                        response(records = listOf(weightRecord("second", "native-2")), pageToken = "page-3"),
                    ),
            )

        val result = HealthBodyMassOperations(fallback, APP_PACKAGE).lookup(validRequest())

        assertEquals(BodyMassLookupStatus.UNAVAILABLE, result.status)
        assertEquals("lookupBoundExceeded", result.platformCode)
        assertEquals(2, fallback.readRequests.size)
        assertEquals("page-2", fallback.readRequests[1].pageToken)
    }

    @Test
    fun fallback_returnsAbsentAfterInspecting200TerminalRecords() = runTest {
        val firstPage = (0 until 100).map { index -> weightRecord("first-$index", "first-$index") }
        val secondPage = (0 until 100).map { index -> weightRecord("second-$index", "second-$index") }
        val fallback =
            FakeBodyMassClient(
                responses =
                    listOf(
                        response(records = firstPage, pageToken = "page-2"),
                        response(records = secondPage),
                    ),
            )

        val result = HealthBodyMassOperations(fallback, APP_PACKAGE).lookup(validRequest())

        assertEquals(BodyMassLookupStatus.ABSENT, result.status)
        assertNull(result.recordId)
        assertNull(result.platformCode)
        assertEquals(2, fallback.readRequests.size)
    }

    @Test
    fun fallback_returnsUnavailableAfterInspecting200RecordsWhenAnotherPageRemains() = runTest {
        val firstPage = (0 until 100).map { index -> weightRecord("first-$index", "first-$index") }
        val secondPage = (0 until 100).map { index -> weightRecord("second-$index", "second-$index") }
        val fallback =
            FakeBodyMassClient(
                responses =
                    listOf(
                        response(records = firstPage, pageToken = "page-2"),
                        response(records = secondPage, pageToken = "page-3"),
                    ),
            )

        val result = HealthBodyMassOperations(fallback, APP_PACKAGE).lookup(validRequest())

        assertEquals(BodyMassLookupStatus.UNAVAILABLE, result.status)
        assertNull(result.recordId)
        assertEquals("lookupBoundExceeded", result.platformCode)
        assertEquals(2, fallback.readRequests.size)
        assertEquals("page-2", fallback.readRequests[1].pageToken)
    }

    @Test
    fun lookup_mapsHistoryAndServiceFailuresToBoundedUnavailableCodes() = runTest {
        val cases =
            listOf(
                IllegalStateException("history unavailable") to "historyWindowUnavailable",
                RemoteException("service unavailable") to "lookupRemoteFailure",
                IOException("transport unavailable") to "lookupIoFailure",
                SecurityException("permission changed") to "lookupSecurityFailure",
            )

        for ((failure, expectedCode) in cases) {
            val fallback = FakeBodyMassClient(failure = failure)

            val result = HealthBodyMassOperations(fallback, APP_PACKAGE).lookup(validRequest())

            assertEquals(BodyMassLookupStatus.UNAVAILABLE, result.status)
            assertNull(result.recordId)
            assertEquals(expectedCode, result.platformCode)
        }
    }
}

private class FakeBodyMassClient(
    responses: List<ReadRecordsResponse<WeightRecord>> = emptyList(),
    private val failure: Exception? = null,
) : HealthBodyMassClient {
    private val queuedResponses = ArrayDeque(responses)
    val readRequests = mutableListOf<ReadRecordsRequest<WeightRecord>>()

    override suspend fun readWeights(
        request: ReadRecordsRequest<WeightRecord>
    ): ReadRecordsResponse<WeightRecord> {
        readRequests += request
        failure?.let { throw it }
        return queuedResponses.removeFirstOrNull() ?: response(records = emptyList())
    }
}

private class FakeBodyMassDirectLookup(
    override val isAvailable: Boolean,
    private val result: BodyMassLookupResultPayload =
        BodyMassLookupResultPayload(status = BodyMassLookupStatus.ABSENT),
) : HealthBodyMassDirectLookup {
    var calls = 0
        private set
    var lastClientRecordId: String? = null
        private set

    override suspend fun lookup(clientRecordId: String): BodyMassLookupResultPayload {
        calls += 1
        lastClientRecordId = clientRecordId
        return result
    }
}

private fun validRequest(): BodyMassLookupRequest =
    BodyMassLookupRequest(clientRecordId = BODY_MASS_CLIENT_ID, measuredAt = MEASURED_AT)

private fun response(
    records: List<WeightRecord>,
    pageToken: String? = null,
): ReadRecordsResponse<WeightRecord> = ReadRecordsResponse(records = records, pageToken = pageToken)

private fun weightRecord(clientRecordId: String, nativeId: String): WeightRecord {
    val metadata =
        Metadata.activelyRecorded(
            clientRecordId = clientRecordId,
            clientRecordVersion = 0,
            device = Device(type = Device.TYPE_PHONE),
        )
    Metadata::class.java.getDeclaredField("id").apply {
        isAccessible = true
        set(metadata, nativeId)
    }
    return WeightRecord(
        time = MEASURED_AT,
        zoneOffset = ZoneOffset.UTC,
        weight = Mass.kilograms(70.0),
        metadata = metadata,
    )
}

private const val APP_PACKAGE = "app.myplates"
private const val BODY_MASS_CLIENT_ID = "018f8d7e-3333-7333-8333-333333333333"
private val MEASURED_AT = Instant.parse("2026-07-20T12:00:00Z")
