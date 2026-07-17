package cachet.plugins.health

import io.flutter.plugin.common.MethodChannel.Result as FlutterResult
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

internal interface HealthWorkoutOperationsContract {
    suspend fun write(request: WorkoutWriteRequest): WorkoutWriteResultPayload

    suspend fun lookup(request: WorkoutLookupRequest): WorkoutLookupResultPayload

    suspend fun authorizationSnapshot(types: List<String>): AuthorizationSnapshotPayload
}

internal class HealthWorkoutMethodHandler(
    private val scope: CoroutineScope,
    private val operations: HealthWorkoutOperationsContract,
) {
    fun write(arguments: Any?, result: FlutterResult) {
        val once = FlutterResultOnce(result)
        val request =
            try {
                WorkoutWriteRequest.fromMap(arguments)
            } catch (_: WorkoutPayloadException) {
                once.success(
                    WorkoutWriteResultPayload.invalidInput(
                        energyExpected = hasRequestedEnergy(arguments),
                    ).toMap()
                )
                return
            }

        launchOnce(
            once = once,
            canceled = {
                WorkoutWriteResultPayload.unavailable(
                    energyExpected = request.energyClientRecordId != null,
                    platformCode = OPERATION_CANCELED,
                ).toMap()
            },
            unexpected = {
                WorkoutWriteResultPayload.unavailable(
                    energyExpected = request.energyClientRecordId != null,
                    platformCode = UNEXPECTED_FAILURE,
                ).toMap()
            },
        ) {
            operations.write(request).toMap()
        }
    }

    fun lookup(arguments: Any?, result: FlutterResult) {
        val once = FlutterResultOnce(result)
        val request =
            try {
                WorkoutLookupRequest.fromMap(arguments)
            } catch (_: WorkoutPayloadException) {
                once.success(
                    WorkoutLookupResultPayload.unavailable(
                        energyExpected = hasRequestedEnergy(arguments),
                        platformCode = INVALID_INPUT,
                    ).toMap()
                )
                return
            }

        launchOnce(
            once = once,
            canceled = {
                WorkoutLookupResultPayload.unavailable(
                    energyExpected = request.energyClientRecordId != null,
                    platformCode = OPERATION_CANCELED,
                ).toMap()
            },
            unexpected = {
                WorkoutLookupResultPayload.unavailable(
                    energyExpected = request.energyClientRecordId != null,
                    platformCode = UNEXPECTED_FAILURE,
                ).toMap()
            },
        ) {
            operations.lookup(request).toMap()
        }
    }

    fun authorizationSnapshot(arguments: Any?, result: FlutterResult) {
        val once = FlutterResultOnce(result)
        val types =
            try {
                authorizationTypesFromMap(arguments)
            } catch (_: WorkoutPayloadException) {
                once.error(INVALID_INPUT, "Invalid authorization snapshot arguments", null)
                return
            }

        launchOnce(
            once = once,
            canceled = {
                AuthorizationSnapshotPayload.unavailable(types, OPERATION_CANCELED).toMap()
            },
            unexpected = {
                AuthorizationSnapshotPayload.unavailable(types, UNEXPECTED_FAILURE).toMap()
            },
        ) {
            operations.authorizationSnapshot(types).toMap()
        }
    }

    private fun launchOnce(
        once: FlutterResultOnce,
        canceled: () -> Map<String, Any?>,
        unexpected: () -> Map<String, Any?>,
        operation: suspend () -> Map<String, Any?>,
    ) {
        val job: Job =
            try {
                scope.launch {
                    try {
                        once.success(operation())
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        once.success(unexpected())
                    }
                }
            } catch (_: Exception) {
                once.success(unexpected())
                return
            }

        job.invokeOnCompletion { cause ->
            when (cause) {
                is CancellationException -> once.success(canceled())
                null -> Unit
                else -> once.success(unexpected())
            }
        }
    }

    private companion object {
        const val INVALID_INPUT = "invalidInput"
        const val OPERATION_CANCELED = "operationCanceled"
        const val UNEXPECTED_FAILURE = "unexpectedFailure"
    }
}

private class FlutterResultOnce(private val result: FlutterResult) {
    private val completed = AtomicBoolean(false)

    fun success(value: Any?) {
        if (completed.compareAndSet(false, true)) {
            result.success(value)
        }
    }

    fun error(code: String, message: String?, details: Any?) {
        if (completed.compareAndSet(false, true)) {
            result.error(code, message, details)
        }
    }
}

private fun hasRequestedEnergy(arguments: Any?): Boolean =
    arguments is Map<*, *> && arguments["energyClientRecordId"] != null
