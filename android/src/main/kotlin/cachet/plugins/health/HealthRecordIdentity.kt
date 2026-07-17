package cachet.plugins.health

import androidx.health.connect.client.records.metadata.Metadata

/** Platform record identity exported to the method-channel payload. */
internal fun Metadata.flutterIdentityFields(): Map<String, Any> = buildMap {
    put("uuid", id)
    put("source_id", dataOrigin.packageName)
    put("source_name", dataOrigin.packageName)
    clientRecordId?.takeIf { it.isNotBlank() }?.let { clientId ->
        put("client_record_id", clientId)
        put("client_record_id_type", "healthConnectClientRecordId")
        put("client_record_version", clientRecordVersion)
    }
}
