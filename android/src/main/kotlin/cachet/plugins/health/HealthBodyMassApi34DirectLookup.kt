package cachet.plugins.health

import android.content.Context
import android.health.connect.HealthConnectException
import android.health.connect.HealthConnectManager
import android.health.connect.ReadRecordsRequestUsingIds
import android.health.connect.ReadRecordsResponse as PlatformReadRecordsResponse
import android.health.connect.datatypes.WeightRecord as PlatformWeightRecord
import android.os.Build
import android.os.OutcomeReceiver
import android.os.ext.SdkExtensions
import androidx.annotation.DoNotInline
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresExtension
import java.util.concurrent.Executor
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/** API-34-only extension check and Health Connect implementation. */
@RequiresApi(34)
internal object Api34HealthBodyMassDirectLookupFactory {
    fun createIfSupported(
        context: Context,
        appPackageName: String,
    ): HealthBodyMassDirectLookup {
        val extensionVersion =
            SdkExtensions.getExtensionVersion(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
        if (!supportsDirectBodyMassLookup(Build.VERSION.SDK_INT, extensionVersion)) {
            return UnavailableBodyMassDirectLookup
        }
        return createApi34Extension7Lookup(context, appPackageName)
    }

    @DoNotInline
    @RequiresApi(34)
    @RequiresExtension(extension = 34, version = 7)
    private fun createApi34Extension7Lookup(
        context: Context,
        appPackageName: String,
    ): HealthBodyMassDirectLookup =
        Api34Extension7HealthBodyMassDirectLookup(context, appPackageName)
}

/**
 * API-34-extension-7-only body-mass record read. The generic factory reaches
 * this class only through its API-annotated, non-inlined creation boundary.
 */
@RequiresApi(34)
@RequiresExtension(extension = 34, version = 7)
internal class Api34Extension7HealthBodyMassDirectLookup(
    private val context: Context,
    private val appPackageName: String,
) : HealthBodyMassDirectLookup {
    override val isAvailable: Boolean = true

    override suspend fun lookup(clientRecordId: String): BodyMassLookupResultPayload {
        val manager = context.getSystemService(HealthConnectManager::class.java)
            ?: return BodyMassLookupResultPayload.unavailable(LOOKUP_FAILED)
        return suspendCancellableCoroutine { continuation ->
            fun complete(value: BodyMassLookupResultPayload) {
                if (continuation.isActive) {
                    continuation.resume(value)
                }
            }

            try {
                val request =
                    ReadRecordsRequestUsingIds.Builder(PlatformWeightRecord::class.java)
                        .addClientRecordId(clientRecordId)
                        .build()
                manager.readRecords(
                    request,
                    DIRECT_LOOKUP_EXECUTOR,
                    object : OutcomeReceiver<
                        PlatformReadRecordsResponse<PlatformWeightRecord>,
                        HealthConnectException,
                    > {
                        override fun onResult(
                            response: PlatformReadRecordsResponse<PlatformWeightRecord>
                        ) {
                            val matches =
                                response.records.filter {
                                    it.metadata.clientRecordId == clientRecordId &&
                                        it.metadata.dataOrigin.packageName == appPackageName
                                }
                            complete(matches.toDirectLookupResult())
                        }

                        override fun onError(error: HealthConnectException) {
                            complete(BodyMassLookupResultPayload.unavailable(LOOKUP_FAILED))
                        }
                    },
                )
            } catch (error: Exception) {
                complete(BodyMassLookupResultPayload.unavailable(fallbackFailureCode(error)))
            }
        }
    }

    private fun List<PlatformWeightRecord>.toDirectLookupResult(): BodyMassLookupResultPayload =
        when (size) {
            0 -> BodyMassLookupResultPayload(status = BodyMassLookupStatus.ABSENT)
            1 -> {
                val nativeId = single().metadata.id
                if (nativeId.isBlank()) {
                    BodyMassLookupResultPayload.unavailable(LOOKUP_FAILED)
                } else {
                    BodyMassLookupResultPayload(
                        status = BodyMassLookupStatus.PRESENT,
                        recordId = nativeId,
                    )
                }
            }
            else -> BodyMassLookupResultPayload.unavailable(MULTIPLE_MATCHING_RECORDS)
        }
}

private val DIRECT_LOOKUP_EXECUTOR = Executor { command -> command.run() }
