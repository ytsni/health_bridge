package cachet.plugins.health

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.annotation.NonNull
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import kotlinx.coroutines.*

/**
 * Main Flutter plugin class for Health Connect integration. Manages plugin lifecycle, method
 * channel communication, permission handling, and coordinates between Flutter and Android Health
 * Connect APIs.
 */
class HealthPlugin(private var channel: MethodChannel? = null) :
        MethodCallHandler, ActivityResultListener, ActivityAware, FlutterPlugin {

    private val permissionRequestLifecycle = HealthConnectPermissionRequestLifecycle()
    private var activity: Activity? = null
    private var context: Context? = null
    private var healthConnectClient: HealthConnectClient? = null
    private var scope: CoroutineScope? = null

    // Helper classes
    private var dataReader: HealthDataReader? = null
    private var dataWriter: HealthDataWriter? = null
    private var dataOperations: HealthDataOperations? = null
    private var dataConverter: HealthDataConverter? = null
    private var dataChanges: HealthDataChanges? = null
    private var workoutMethodHandler: HealthWorkoutMethodHandler? = null

    // Health Connect availability
    private var healthConnectAvailable = false
    private var healthConnectStatus = HealthConnectClient.SDK_UNAVAILABLE

    companion object {
        const val CHANNEL_NAME = "flutter_health"
    }

    /**
     * Initializes the plugin when attached to the Flutter engine. Sets up method channel, checks
     * Health Connect availability, and initializes helper classes.
     *
     * @param flutterPluginBinding Plugin binding providing access to Flutter engine resources
     */
    override fun onAttachedToEngine(
            @NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    ) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext

        checkAvailability()
        if (healthConnectAvailable) {
            healthConnectClient =
                    HealthConnectClient.getOrCreate(flutterPluginBinding.applicationContext)
            initializeHelpers()
        }
    }

    /**
     * Cleans up resources when plugin is detached from Flutter engine. Cancels coroutines and
     * nullifies references to prevent memory leaks.
     *
     * @param binding Plugin binding (unused in cleanup)
     */
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        permissionRequestLifecycle.detachPermanently()
        channel?.setMethodCallHandler(null)
        channel = null
        activity = null
        context = null
        scope?.cancel()
        scope = null
        healthConnectClient = null
        dataReader = null
        dataWriter = null
        dataOperations = null
        dataConverter = null
        dataChanges = null
        workoutMethodHandler = null
        healthConnectAvailable = false
        healthConnectStatus = HealthConnectClient.SDK_UNAVAILABLE
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        return false
    }

    /**
     * Handles method calls from Flutter and routes them to appropriate handler classes. Central
     * dispatcher for all Health Connect operations including permissions, data reading, writing,
     * and deletion.
     *
     * @param call Method call from Flutter containing method name and arguments
     * @param result Result callback to return data or status to Flutter
     */
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // SDK and Installation
            "installHealthConnect" -> installHealthConnect(call, result)
            "getHealthConnectSdkStatus" -> {
                checkAvailability()
                if (healthConnectAvailable && dataOperations == null) {
                    healthConnectClient = HealthConnectClient.getOrCreate(context!!)
                    initializeHelpers()
                }
                result.success(healthConnectStatus)
            }

            // Permissions
            "hasPermissions" -> checkNotNull(dataOperations).hasPermissions(call, result)
            "requestAuthorization" -> requestAuthorization(call, result)
            "revokePermissions" -> checkNotNull(dataOperations).revokePermissions(call, result)

            // History permissions
            "isHealthDataHistoryAvailable" ->
                    checkNotNull(dataOperations).isHealthDataHistoryAvailable(call, result)
            "isHealthDataHistoryAuthorized" ->
                    checkNotNull(dataOperations).isHealthDataHistoryAuthorized(call, result)
            "requestHealthDataHistoryAuthorization" ->
                    requestHealthDataHistoryAuthorization(call, result)

            // Background permissions
            "isHealthDataInBackgroundAvailable" ->
                    checkNotNull(dataOperations).isHealthDataInBackgroundAvailable(call, result)
            "isHealthDataInBackgroundAuthorized" ->
                    checkNotNull(dataOperations).isHealthDataInBackgroundAuthorized(call, result)
            "requestHealthDataInBackgroundAuthorization" ->
                    requestHealthDataInBackgroundAuthorization(call, result)
            "isSkinTemperatureAvailable" ->
                    checkNotNull(dataOperations).isSkinTemperatureAvailable(call, result)

            // Reading data
            "getData" -> checkNotNull(dataReader).getData(call, result)
            "getDataByUUID" -> checkNotNull(dataReader).getDataByUUID(call, result)
            "getIntervalData" -> checkNotNull(dataReader).getIntervalData(call, result)
            "getAggregateData" -> checkNotNull(dataReader).getAggregateData(call, result)
            "getTotalStepsInInterval" ->
                    checkNotNull(dataReader).getTotalStepsInInterval(call, result)
            "getChangesToken" -> checkNotNull(dataChanges).getChangesToken(call, result)
            "getChanges" -> checkNotNull(dataChanges).getChanges(call, result)

            // Writing data
            "writeData" -> checkNotNull(dataWriter).writeData(call, result)
            "writeWorkoutData" -> {
                if (healthConnectAvailable && workoutMethodHandler != null) {
                    checkNotNull(workoutMethodHandler).write(call.arguments, result)
                } else {
                    val arguments = call.arguments
                    val energyExpected =
                            arguments is Map<*, *> && arguments["energyClientRecordId"] != null
                    result.success(
                            WorkoutWriteResultPayload.unavailable(
                                            energyExpected = energyExpected,
                                            platformCode = "healthConnectUnavailable",
                                    )
                                    .toMap()
                    )
                }
            }
            "lookupWorkoutData" -> {
                if (healthConnectAvailable && workoutMethodHandler != null) {
                    checkNotNull(workoutMethodHandler).lookup(call.arguments, result)
                } else {
                    result.success(unavailableLookupResult(call.arguments))
                }
            }
            "getAuthorizationSnapshot" -> {
                if (healthConnectAvailable && workoutMethodHandler != null) {
                    checkNotNull(workoutMethodHandler).authorizationSnapshot(call.arguments, result)
                } else {
                    val types =
                            try {
                                authorizationTypesFromMap(call.arguments)
                            } catch (_: WorkoutPayloadException) {
                                result.error(
                                        "invalidInput",
                                        "Invalid authorization snapshot arguments",
                                        null,
                                )
                                return
                            }
                    result.success(
                            AuthorizationSnapshotPayload.unavailable(
                                            types,
                                            "healthConnectUnavailable",
                                    )
                                    .toMap()
                    )
                }
            }
            "writeBloodPressure" -> checkNotNull(dataWriter).writeBloodPressure(call, result)
            "writeBloodOxygen" -> checkNotNull(dataWriter).writeBloodOxygen(call, result)
            "writeMenstruationFlow" ->
                    checkNotNull(dataWriter).writeMenstruationFlow(call, result)
            "writeMeal" -> checkNotNull(dataWriter).writeMeal(call, result)
            "writeActivityIntensity" ->
                    checkNotNull(dataWriter).writeActivityIntensity(call, result)
            "startWorkoutRoute" -> checkNotNull(dataWriter).startWorkoutRoute(result)
            "insertWorkoutRouteData" ->
                    checkNotNull(dataWriter).insertWorkoutRouteData(call, result)
            "finishWorkoutRoute" -> checkNotNull(dataWriter).finishWorkoutRoute(call, result)
            "discardWorkoutRoute" -> checkNotNull(dataWriter).discardWorkoutRoute(call, result)
            // TODO: Add support for multiple speed for iOS as well
            // "writeMultipleSpeed" -> dataWriter.writeMultipleSpeedData(call, result)

            // Deleting data
            "delete" -> checkNotNull(dataOperations).deleteData(call, result)
            "deleteByUUID" -> checkNotNull(dataOperations).deleteByUUID(call, result)
            "deleteByClientRecordId" ->
                    checkNotNull(dataOperations).deleteByClientRecordId(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Called when activity is attached to the plugin. Sets up permission request launcher and
     * activity result handling.
     *
     * @param binding Activity plugin binding providing activity context
     */
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        if (channel == null) {
            return
        }
        binding.addActivityResultListener(this)
        activity = binding.activity

        val requestPermissionActivityContract =
                PermissionController.createRequestPermissionResultContract()

        val launcher =
                (activity as ComponentActivity).registerForActivityResult(
                        requestPermissionActivityContract
                ) { granted -> onHealthConnectPermissionCallback(granted) }
        permissionRequestLifecycle.attach(
                AndroidHealthConnectPermissionLauncher(launcher)
        )
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        permissionRequestLifecycle.detachForConfigurationChange()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    /**
     * Called when activity is detached from plugin. Cleans up activity-specific resources and
     * permission launchers.
     */
    override fun onDetachedFromActivity() {
        activity = null
        permissionRequestLifecycle.detachPermanently()
    }

    /**
     * Checks Health Connect availability and SDK status on the current device. Determines if Health
     * Connect is installed and accessible.
     */
    private fun checkAvailability() {
        healthConnectStatus = HealthConnectClient.getSdkStatus(checkNotNull(context))
        healthConnectAvailable = healthConnectStatus == HealthConnectClient.SDK_AVAILABLE
    }

    /**
     * Initializes helper classes for data operations after Health Connect client is ready. Creates
     * instances of reader, writer, operations, and converter classes.
     */
    private fun initializeHelpers() {
        val client = checkNotNull(healthConnectClient)
        val operationScope = checkNotNull(scope)
        val appContext = checkNotNull(context)
        val converter = HealthDataConverter()
        dataConverter = converter
        dataReader = HealthDataReader(client, operationScope, converter)
        dataWriter = HealthDataWriter(client, operationScope)
        dataOperations =
                HealthDataOperations(
                        client,
                        operationScope,
                        healthConnectStatus,
                        healthConnectAvailable
                )
        dataChanges = HealthDataChanges(client, operationScope, appContext, converter)
        workoutMethodHandler =
                HealthWorkoutMethodHandler(
                        operationScope,
                        HealthWorkoutOperations(client, appContext.packageName),
                )
    }

    private fun unavailableLookupResult(arguments: Any?): Map<String, Any?> {
        val energyExpected =
                arguments is Map<*, *> && arguments["energyClientRecordId"] != null
        val platformCode =
                try {
                    WorkoutLookupRequest.fromMap(arguments)
                    "healthConnectUnavailable"
                } catch (_: WorkoutPayloadException) {
                    "invalidInput"
                }
        return WorkoutLookupResultPayload.unavailable(
                        energyExpected = energyExpected,
                        platformCode = platformCode,
                )
                .toMap()
    }

    /**
     * Launches Health Connect installation flow via Google Play Store. Directs users to install
     * Health Connect when it's not available.
     *
     * @param call Method call from Flutter (unused)
     * @param result Flutter result callback
     */
    private fun installHealthConnect(call: MethodCall, result: Result) {
        val uriString =
                "market://details?id=com.google.android.apps.healthdata&url=healthconnect%3A%2F%2Fonboarding"
        context!!.startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setPackage("com.android.vending")
                    data = android.net.Uri.parse(uriString)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra("overlay", true)
                    putExtra("callerId", context!!.packageName)
                }
        )
        result.success(null)
    }

    /**
     * Handles permission request results from Health Connect permission dialog. Called when user
     * responds to permission request, updates Flutter with result.
     *
     * @param permissionGranted Set of permission strings that were granted
     */
    private fun onHealthConnectPermissionCallback(permissionGranted: Set<String>) {
        if (permissionRequestLifecycle.completeFromCallback(permissionGranted)) {
            Log.i(
                    "FLUTTER_HEALTH",
                    "Health Connect permission request completed with ${permissionGranted.size} returned permissions."
            )
        }
    }

    /**
     * Initiates Health Connect permission request flow. Prepares permission list and launches
     * system permission dialog.
     *
     * @param call Method call containing permission types and access levels
     * @param result Flutter result callback for permission request outcome
     */
    private fun requestAuthorization(call: MethodCall, result: Result) {
        if (context == null) {
            result.success(false)
            return
        }

        val permList =
                try {
                    dataOperations?.preparePermissionsList(call)
                } catch (_: Exception) {
                    null
                }
        if (permList == null) {
            result.success(false)
            return
        }

        permissionRequestLifecycle.launch(permList.toSet(), result)
    }

    /**
     * Requests specific permission for accessing health data history. Launches permission dialog
     * for historical data access capability.
     *
     * @param call Method call from Flutter (unused)
     * @param result Flutter result callback for permission request outcome
     */
    private fun requestHealthDataHistoryAuthorization(call: MethodCall, result: Result) {
        if (context == null) {
            result.success(false)
            Log.i("FLUTTER_HEALTH", "Permission launcher not found")
            return
        }

        permissionRequestLifecycle.launch(
                setOf(HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY),
                result,
        )
    }

    /**
     * Requests specific permission for background health data access. Launches permission dialog
     * for background data reading capability.
     *
     * @param call Method call from Flutter (unused)
     * @param result Flutter result callback for permission request outcome
     */
    private fun requestHealthDataInBackgroundAuthorization(call: MethodCall, result: Result) {
        if (context == null) {
            result.success(false)
            Log.i("FLUTTER_HEALTH", "Permission launcher not found")
            return
        }

        permissionRequestLifecycle.launch(
                setOf(HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND),
                result,
        )
    }
}

internal interface HealthConnectPermissionLauncher {
    fun launch(permissions: Set<String>)

    fun unregister()
}

private class AndroidHealthConnectPermissionLauncher(
        private val delegate: ActivityResultLauncher<Set<String>>
) : HealthConnectPermissionLauncher {
    override fun launch(permissions: Set<String>) {
        delegate.launch(permissions)
    }

    override fun unregister() {
        delegate.unregister()
    }
}

/** Couples the single pending result to the launcher registered by the current Activity. */
internal class HealthConnectPermissionRequestLifecycle(
        private val completion: HealthConnectPermissionRequestCompletion =
                HealthConnectPermissionRequestCompletion()
) {
    private var launcher: HealthConnectPermissionLauncher? = null

    fun attach(launcher: HealthConnectPermissionLauncher) {
        releaseLauncher()
        this.launcher = launcher
    }

    fun launch(permissions: Set<String>, result: Result) {
        val currentLauncher = launcher
        if (currentLauncher == null) {
            result.success(false)
            return
        }
        if (!completion.begin(result)) {
            result.success(false)
            return
        }

        try {
            currentLauncher.launch(permissions)
        } catch (_: Exception) {
            completion.failImmediately()
        }
    }

    fun detachForConfigurationChange() {
        // Do not unregister here: ActivityResultRegistry carries launched keys and queued results
        // through recreation. The new Activity registers the replacement callback on reattach.
        launcher = null
    }

    fun detachPermanently() {
        try {
            releaseLauncher()
        } finally {
            completion.failImmediately()
        }
    }

    fun completeFromCallback(permissionGranted: Set<String>): Boolean =
            completion.completeFromCallback(permissionGranted)

    private fun releaseLauncher() {
        val currentLauncher = launcher
        launcher = null
        try {
            currentLauncher?.unregister()
        } catch (_: Exception) {
            // The launcher is already cleared; permanent detach clears the result in its finally.
        }
    }
}

/** Owns the single pending Flutter result for Health Connect's activity-result callback. */
internal class HealthConnectPermissionRequestCompletion {
    private val lock = Any()
    private var pendingResult: Result? = null

    fun begin(result: Result): Boolean =
            synchronized(lock) {
                if (pendingResult != null) {
                    false
                } else {
                    pendingResult = result
                    true
                }
            }

    fun completeFromCallback(
            @Suppress("UNUSED_PARAMETER") permissionGranted: Set<String>
    ): Boolean = success(true)

    fun failImmediately(): Boolean = success(false)

    private fun success(value: Any?): Boolean {
        val result = takePendingResult() ?: return false
        result.success(value)
        return true
    }

    private fun takePendingResult(): Result? =
            synchronized(lock) {
                val result = pendingResult
                pendingResult = null
                result
            }
}
