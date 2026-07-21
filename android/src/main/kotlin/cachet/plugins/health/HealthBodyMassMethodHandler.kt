package cachet.plugins.health

import io.flutter.plugin.common.MethodChannel.Result as FlutterResult
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

internal class HealthBodyMassMethodHandler(
    private val scope: CoroutineScope,
    private val operations: HealthBodyMassOperationsContract,
) {
    fun lookup(arguments: Any?, result: FlutterResult) {
        val once = BodyMassFlutterResultOnce(result)
        val request =
            try {
                BodyMassLookupRequest.fromMap(arguments)
            } catch (_: BodyMassLookupPayloadException) {
                once.success(BodyMassLookupResultPayload.unavailable(INVALID_INPUT).toMap())
                return
            }

        val job: Job =
            try {
                scope.launch {
                    try {
                        once.success(operations.lookup(request).toMap())
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        once.success(BodyMassLookupResultPayload.unavailable(UNEXPECTED_FAILURE).toMap())
                    }
                }
            } catch (_: Exception) {
                once.success(BodyMassLookupResultPayload.unavailable(UNEXPECTED_FAILURE).toMap())
                return
            }

        job.invokeOnCompletion { cause ->
            when (cause) {
                is CancellationException ->
                    once.success(BodyMassLookupResultPayload.unavailable(OPERATION_CANCELED).toMap())
                null -> Unit
                else -> once.success(BodyMassLookupResultPayload.unavailable(UNEXPECTED_FAILURE).toMap())
            }
        }
    }

    private companion object {
        const val INVALID_INPUT = "invalidInput"
        const val OPERATION_CANCELED = "operationCanceled"
        const val UNEXPECTED_FAILURE = "unexpectedFailure"
    }
}

private class BodyMassFlutterResultOnce(private val result: FlutterResult) {
    private val completed = AtomicBoolean(false)

    fun success(value: Any?) {
        if (completed.compareAndSet(false, true)) {
            result.success(value)
        }
    }
}
