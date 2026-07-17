package cachet.plugins.health

import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.testing.populatedWithTestValues
import androidx.health.connect.client.units.Mass
import java.time.Instant
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class HealthDataConverterIdentityTest {
    @Test
    fun convertRecord_exposesNativeClientAndSourceIdentity() {
        val metadata =
            Metadata.autoRecorded(
                clientRecordId = "scale-reading-42",
                clientRecordVersion = 7,
                device = Device(type = Device.TYPE_SCALE),
            ).populatedWithTestValues(
                id = "native-record-id",
                dataOrigin = DataOrigin("com.example.scale"),
                lastModifiedTime = Instant.parse("2026-07-15T12:01:00Z"),
            )
        val record =
            WeightRecord(
                time = Instant.parse("2026-07-15T12:00:00Z"),
                zoneOffset = ZoneOffset.UTC,
                weight = Mass.kilograms(80.0),
                metadata = metadata,
            )

        val converted = HealthDataConverter().convertRecord(record, "WEIGHT").single()

        assertEquals("native-record-id", converted["uuid"])
        assertEquals("scale-reading-42", converted["client_record_id"])
        assertEquals("healthConnectClientRecordId", converted["client_record_id_type"])
        assertEquals(7L, converted["client_record_version"])
        assertEquals("com.example.scale", converted["source_id"])
        assertEquals("com.example.scale", converted["source_name"])
    }

    @Test
    fun flutterIdentityFields_omitsClientVersionWithoutClientIdentity() {
        val metadata = Metadata.manualEntry()

        val fields = metadata.flutterIdentityFields()

        assertFalse(fields.containsKey("client_record_id"))
        assertFalse(fields.containsKey("client_record_version"))
    }
}
