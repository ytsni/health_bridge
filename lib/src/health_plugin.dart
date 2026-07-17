part of '../health.dart';

/// Main class for the Plugin.
///
/// Use this class to get an instance of the Health plugin, like this:
///
///         final health = Health();
///
/// The plugin must be configured using the [configure] method before used.
///
/// Overall, the plugin supports:
///
///  * Handling permissions to access health data using the [hasPermissions],
///    [requestAuthorization], [revokePermissions] methods.
///  * Reading health data using the [getHealthDataFromTypes] method.
///  * Writing health data using the [writeHealthData] method.
///  * Cleaning up duplicate data points via the [removeDuplicates] method.
///
/// In addition, the plugin has a set of specialized methods for reading and writing
/// different types of health data:
///
///  * Reading aggregate health data using the [getHealthIntervalDataFromTypes]
///    and [getHealthAggregateDataFromTypes] methods.
///  * Reading total step counts using the [getTotalStepsInInterval] method.
///  * Writing different types of specialized health data like the [writeWorkoutData],
///    [writeBloodPressure], [writeBloodOxygen], [writeAudiogram], [writeMeal],
///    [writeMenstruationFlow], [writeInsulinDelivery], [writeActivityIntensity] methods.
///
/// On **Android**, this plugin relies on the Google Health Connect (GHC) SDK.
/// Since Health Connect is not installed on SDK level < 34, the plugin has a
/// set of specialized methods to handle GHC:
///
///  * [getHealthConnectSdkStatus] to check the status of GHC
///  * [isHealthConnectAvailable] to check if GHC is installed on this phone
///  * [installHealthConnect] to direct the user to the app store to install GHC
///
/// **Note** that you should check the availability of GHC before using any setter
/// or getter methods. Otherwise, the plugin will throw an exception.
class Health {
  static const MethodChannel _channel = MethodChannel('flutter_health');

  String? _deviceId;
  final DeviceInfoPlugin _deviceInfo;
  final bool Function() _workoutPlatformIsIOS;
  final bool Function() _workoutPlatformIsAndroid;
  HealthConnectSdkStatus _healthConnectSdkStatus = HealthConnectSdkStatus.sdkUnavailable;

  /// Get an instance of the health plugin.
  Health({
    DeviceInfoPlugin? deviceInfo,
    @visibleForTesting bool Function()? workoutPlatformIsIOS,
    @visibleForTesting bool Function()? workoutPlatformIsAndroid,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
       _workoutPlatformIsIOS = workoutPlatformIsIOS ?? (() => Platform.isIOS),
       _workoutPlatformIsAndroid = workoutPlatformIsAndroid ?? (() => Platform.isAndroid) {
    _registerFromJsonFunctions();
  }

  /// The latest status on availability of Health Connect SDK on this phone.
  HealthConnectSdkStatus get healthConnectSdkStatus => _healthConnectSdkStatus;

  /// The type of platform of this device.
  HealthPlatformType get platformType =>
      Platform.isIOS ? HealthPlatformType.appleHealth : HealthPlatformType.googleHealthConnect;

  /// The id of this device.
  ///
  /// On Android this is the [ID](https://developer.android.com/reference/android/os/Build#ID) of the BUILD.
  /// On iOS this is the [identifierForVendor](https://developer.apple.com/documentation/uikit/uidevice/1620059-identifierforvendor) of the UIDevice.
  String get deviceId => _deviceId ?? 'unknown';

  /// Configure the health plugin. Must be called before using the plugin.
  Future<void> configure() async {
    _deviceId = Platform.isAndroid
        ? (await _deviceInfo.androidInfo).id
        : (await _deviceInfo.iosInfo).identifierForVendor;
  }

  /// Check if a given data type is available on the platform
  bool isDataTypeAvailable(HealthDataType dataType) =>
      Platform.isAndroid ? dataTypeKeysAndroid.contains(dataType) : dataTypeKeysIOS.contains(dataType);

  /// Check if a given data type is available on this device.
  /// Currently only needed for Android Skin Temperature support.
  Future<void> _checkIfDataTypeAvailableOnDevice(HealthDataType dataType) async {
    if (!Platform.isAndroid) return;

    if (dataType == HealthDataType.SKIN_TEMPERATURE) {
      final available = await isSkinTemperatureAvailable();
      if (!available) {
        throw HealthException(dataType, 'Not available on this Android device');
      }
    }
  }

  /// Aggregate legacy convenience for checking whether health data [types]
  /// have the specified access rights [permissions].
  ///
  /// Use [getAuthorizationSnapshot] when per-type state is required. This
  /// aggregate result does not replace that exact snapshot.
  ///
  /// Returns:
  ///
  ///  * true - if all of the data types have been granted with the specified access rights.
  ///  * false - if any of the data types has not been granted with the specified access right(s).
  ///  * null - if it can not be determined if the data types have been granted with the specified access right(s).
  ///
  /// Parameters:
  ///
  ///  * [types]  - List of [HealthDataType] whose permissions are to be checked.
  ///  * [permissions] - Optional.
  ///    + If unspecified, this method checks if each HealthDataType in [types] has been granted READ access.
  ///    + If specified, this method checks if each [HealthDataType] in [types] has been granted with the access specified in its
  ///   corresponding entry in this list. The length of this list must be equal to that of [types].
  ///
  /// Caveat:
  ///
  ///  * As Apple HealthKit will not disclose if READ access has been granted for a data type due to privacy concern,
  ///   this method can only return null to represent an undetermined status, if it is called on iOS
  ///   with a READ or READ_WRITE access.
  ///
  ///  * On Android, this function returns true or false, depending on whether the specified access right has been granted.
  Future<bool?> hasPermissions(List<HealthDataType> types, {List<HealthDataAccess>? permissions}) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    if (permissions != null && permissions.length != types.length) {
      throw ArgumentError("The lists of types and permissions must be of same length.");
    }

    final mTypes = List<HealthDataType>.from(types, growable: true);
    final mPermissions = permissions == null
        ? List<int>.filled(types.length, HealthDataAccess.READ.index, growable: true)
        : permissions.map((permission) => permission.index).toList();

    /// On Android, if BMI is requested, then also ask for weight and height
    if (Platform.isAndroid) {
      _handleBMI(mTypes, mPermissions);
      _handleWorkoutRoute(mTypes, mPermissions);
    }

    return await _channel.invokeMethod('hasPermissions', {
      "types": mTypes.map((type) => type.name).toList(),
      "permissions": mPermissions,
    });
  }

  /// Returns the per-type authorization state after a platform request.
  ///
  /// Every [HealthDataType] may be requested. A platform reports an unmapped
  /// type as [HealthAuthorizationState.unsupported]. HealthKit cannot disclose
  /// exact read access, so mapped iOS reads are
  /// [HealthAuthorizationState.requestedOrUnknown]; its write states are exact.
  ///
  /// This method does not use the Android availability guard. Platform
  /// unavailability is represented by an immutable snapshot with
  /// [HealthAuthorizationSnapshot.available] set to false.
  Future<HealthAuthorizationSnapshot> getAuthorizationSnapshot(List<HealthDataType> types) async {
    if (types.isEmpty || types.toSet().length != types.length) {
      throw ArgumentError.value(types, 'types', 'must be nonempty and unique');
    }
    final value = await _channel.invokeMethod<Object?>('getAuthorizationSnapshot', {
      'types': types.map((type) => type.name).toList(growable: false),
    });
    return HealthAuthorizationSnapshot.fromMethodChannel(value, types.toSet());
  }

  /// Revokes Google Health Connect permissions on Android of all types.
  ///
  /// NOTE: The app must be completely killed and restarted for the changes to take effect.
  /// Not implemented on iOS as there is no way to programmatically remove access.
  ///
  /// Android only. On iOS this does nothing.
  Future<void> revokePermissions() async {
    if (Platform.isIOS) return;

    await _checkIfHealthConnectAvailableOnAndroid();
    try {
      await _channel.invokeMethod('revokePermissions');
    } catch (e) {
      debugPrint('$runtimeType - Exception in revokePermissions(): $e');
    }
  }

  /// Checks the current status of Health Connect availability.
  ///
  /// See this for more info:
  /// https://developer.android.com/reference/kotlin/androidx/health/connect/client/HealthConnectClient#getSdkStatus(android.content.Context,kotlin.String)
  ///
  /// Android only. Returns null on iOS or if an error occurs.
  Future<HealthConnectSdkStatus?> getHealthConnectSdkStatus() async {
    if (Platform.isIOS) return null;

    try {
      final status = await _channel.invokeMethod<int>('getHealthConnectSdkStatus');
      _healthConnectSdkStatus = status != null
          ? HealthConnectSdkStatus.fromNativeValue(status)
          : HealthConnectSdkStatus.sdkUnavailable;

      return _healthConnectSdkStatus;
    } catch (e) {
      debugPrint('$runtimeType - Exception in getHealthConnectSdkStatus(): $e');
      return null;
    }
  }

  /// Is Google Health Connect available on this phone?
  ///
  /// Android only. Returns always true on iOS.
  Future<bool> isHealthConnectAvailable() async =>
      !Platform.isAndroid ? true : (await getHealthConnectSdkStatus() == HealthConnectSdkStatus.sdkAvailable);

  /// Prompt the user to install the Google Health Connect app via the
  /// installed store (most likely Play Store).
  ///
  /// Android only. On iOS this does nothing.
  Future<void> installHealthConnect() async {
    if (Platform.isIOS) return;

    try {
      await _channel.invokeMethod('installHealthConnect');
    } catch (e) {
      debugPrint('$runtimeType - Exception in installHealthConnect(): $e');
    }
  }

  /// Checks if Google Health Connect is available and throws an [UnsupportedError]
  /// if not.
  /// Internal methods used to check availability before any getter or setter methods.
  Future<void> _checkIfHealthConnectAvailableOnAndroid() async {
    if (!Platform.isAndroid) return;

    if (!(await isHealthConnectAvailable())) {
      throw UnsupportedError(
        "Google Health Connect is not available on this Android device. "
        "You may prompt the user to install it using the 'installHealthConnect' method",
      );
    }
  }

  /// Checks if the Health Data History feature is available.
  ///
  /// See this for more info: https://developer.android.com/reference/androidx/health/connect/client/permission/HealthPermission#PERMISSION_READ_HEALTH_DATA_HISTORY()
  ///
  ///
  /// Android only. Returns false on iOS or if an error occurs.
  Future<bool> isHealthDataHistoryAvailable() async {
    if (Platform.isIOS) return false;

    try {
      final status = await _channel.invokeMethod<bool>('isHealthDataHistoryAvailable');
      return status ?? false;
    } catch (e) {
      debugPrint('$runtimeType - Exception in isHealthDataHistoryAvailable(): $e');
      return false;
    }
  }

  /// Checks the current status of the Health Data History permission.
  /// Make sure to check [isHealthConnectAvailable] before calling this method.
  ///
  /// See this for more info: https://developer.android.com/reference/androidx/health/connect/client/permission/HealthPermission#PERMISSION_READ_HEALTH_DATA_HISTORY()
  ///
  ///
  /// Android only. Returns true on iOS or false if an error occurs.
  Future<bool> isHealthDataHistoryAuthorized() async {
    if (Platform.isIOS) return true;

    try {
      final status = await _channel.invokeMethod<bool>('isHealthDataHistoryAuthorized');
      return status ?? false;
    } catch (e) {
      debugPrint('$runtimeType - Exception in isHealthDataHistoryAuthorized(): $e');
      return false;
    }
  }

  /// Requests the Health Data History permission.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// See this for more info: https://developer.android.com/reference/androidx/health/connect/client/permission/HealthPermission#PERMISSION_READ_HEALTH_DATA_HISTORY()
  ///
  ///
  /// Android only. Returns true on iOS or false if an error occurs.
  Future<bool> requestHealthDataHistoryAuthorization() async {
    if (Platform.isIOS) return true;

    await _checkIfHealthConnectAvailableOnAndroid();
    try {
      final bool? isAuthorized = await _channel.invokeMethod('requestHealthDataHistoryAuthorization');
      return isAuthorized ?? false;
    } catch (e) {
      debugPrint('$runtimeType - Exception in requestHealthDataHistoryAuthorization(): $e');
      return false;
    }
  }

  /// Checks if the Health Data in Background feature is available.
  ///
  /// See this for more info: https://developer.android.com/reference/androidx/health/connect/client/permission/HealthPermission#PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND()
  ///
  ///
  /// Android only. Returns false on iOS or if an error occurs.
  Future<bool> isHealthDataInBackgroundAvailable() async {
    if (Platform.isIOS) return false;

    try {
      final status = await _channel.invokeMethod<bool>('isHealthDataInBackgroundAvailable');
      return status ?? false;
    } catch (e) {
      debugPrint('$runtimeType - Exception in isHealthDataInBackgroundAvailable(): $e');
      return false;
    }
  }

  /// Checks the current status of the Health Data in Background permission.
  /// Make sure to check [isHealthConnectAvailable] before calling this method.
  ///
  /// See this for more info: https://developer.android.com/reference/androidx/health/connect/client/permission/HealthPermission#PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND()
  ///
  ///
  /// Android only. Returns true on iOS or false if an error occurs.
  Future<bool> isHealthDataInBackgroundAuthorized() async {
    if (Platform.isIOS) return true;

    try {
      final status = await _channel.invokeMethod<bool>('isHealthDataInBackgroundAuthorized');
      return status ?? false;
    } catch (e) {
      debugPrint('$runtimeType - Exception in isHealthDataInBackgroundAuthorized(): $e');
      return false;
    }
  }

  /// Requests the Health Data in Background permission.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// See this for more info: https://developer.android.com/reference/androidx/health/connect/client/permission/HealthPermission#PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND()
  ///
  ///
  /// Android only. Returns true on iOS or false if an error occurs.
  Future<bool> requestHealthDataInBackgroundAuthorization() async {
    if (Platform.isIOS) return true;

    await _checkIfHealthConnectAvailableOnAndroid();
    try {
      final bool? isAuthorized = await _channel.invokeMethod('requestHealthDataInBackgroundAuthorization');
      return isAuthorized ?? false;
    } catch (e) {
      debugPrint('$runtimeType - Exception in requestHealthDataInBackgroundAuthorization(): $e');
      return false;
    }
  }

  /// Checks whether Skin Temperature is available on this Android device.
  ///
  /// Android only. Returns false on iOS or if an error occurs.
  Future<bool> isSkinTemperatureAvailable() async {
    if (Platform.isIOS) return false;

    try {
      final status = await getHealthConnectSdkStatus();
      if (status != HealthConnectSdkStatus.sdkAvailable) {
        return false;
      }

      final available = await _channel.invokeMethod<bool>('isSkinTemperatureAvailable');
      return available ?? false;
    } catch (e) {
      debugPrint('$runtimeType - Exception in isSkinTemperatureAvailable(): $e');
      return false;
    }
  }

  /// Requests the platform permission flow for health data [types].
  ///
  /// A true result means only that the platform request completed without a
  /// plugin error. It is never proof that every requested grant was accepted.
  /// Re-query exact per-type state with [getAuthorizationSnapshot].
  ///
  /// Parameters:
  ///
  /// * [types] - a list of [HealthDataType] which the permissions are requested for.
  /// * [permissions] - Optional.
  ///   + If unspecified, each [HealthDataType] in [types] is requested for READ [HealthDataAccess].
  ///   + If specified, each [HealthDataAccess] in this list is requested for its corresponding indexed
  ///   entry in [types]. In addition, the length of this list must be equal to that of [types].
  ///
  ///  Caveats:
  ///
  ///  * This method may block if permissions are already granted. Hence, check
  ///    [hasPermissions] before calling this method.
  ///  * Apple HealthKit does not disclose exact READ grants. The authorization
  ///    snapshot represents mapped iOS reads as
  ///    [HealthAuthorizationState.requestedOrUnknown].
  Future<bool> requestAuthorization(List<HealthDataType> types, {List<HealthDataAccess>? permissions}) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    if (permissions != null && permissions.length != types.length) {
      throw ArgumentError('The length of [types] must be same as that of [permissions].');
    }

    if (permissions != null) {
      for (int i = 0; i < types.length; i++) {
        final type = types[i];
        final permission = permissions[i];
        if ((type == HealthDataType.ELECTROCARDIOGRAM ||
                type == HealthDataType.HIGH_HEART_RATE_EVENT ||
                type == HealthDataType.LOW_HEART_RATE_EVENT ||
                type == HealthDataType.IRREGULAR_HEART_RATE_EVENT ||
                type == HealthDataType.WALKING_HEART_RATE ||
                type == HealthDataType.ATRIAL_FIBRILLATION_BURDEN) &&
            permission != HealthDataAccess.READ) {
          throw ArgumentError(
            'Requesting WRITE permission on ELECTROCARDIOGRAM / HIGH_HEART_RATE_EVENT / LOW_HEART_RATE_EVENT / IRREGULAR_HEART_RATE_EVENT / WALKING_HEART_RATE / ATRIAL_FIBRILLATION_BURDEN is not allowed.',
          );
        }
      }
    }

    final mTypes = List<HealthDataType>.from(types, growable: true);
    final mPermissions = permissions == null
        ? List<int>.filled(types.length, HealthDataAccess.READ.index, growable: true)
        : permissions.map((permission) => permission.index).toList();

    // on Android, if BMI is requested, then also ask for weight and height
    if (Platform.isAndroid) {
      _handleBMI(mTypes, mPermissions);
      _handleWorkoutRoute(mTypes, mPermissions);
    }

    List<String> keys = mTypes.map((e) => e.name).toList();
    final bool? isAuthorized = await _channel.invokeMethod('requestAuthorization', {
      'types': keys,
      "permissions": mPermissions,
    });
    return isAuthorized ?? false;
  }

  /// Obtains health and weight if BMI is requested on Android.
  void _handleBMI(List<HealthDataType> mTypes, List<int> mPermissions) {
    final index = mTypes.indexOf(HealthDataType.BODY_MASS_INDEX);

    if (index != -1 && Platform.isAndroid) {
      if (!mTypes.contains(HealthDataType.WEIGHT)) {
        mTypes.add(HealthDataType.WEIGHT);
        mPermissions.add(mPermissions[index]);
      }
      if (!mTypes.contains(HealthDataType.HEIGHT)) {
        mTypes.add(HealthDataType.HEIGHT);
        mPermissions.add(mPermissions[index]);
      }
      mTypes.remove(HealthDataType.BODY_MASS_INDEX);
      mPermissions.removeAt(index);
    }
  }

  /// Ensures workout permission is requested whenever workout routes are requested on Android.
  void _handleWorkoutRoute(List<HealthDataType> mTypes, List<int> mPermissions) {
    final index = mTypes.indexOf(HealthDataType.WORKOUT_ROUTE);
    if (index == -1) {
      return;
    }

    if (!mTypes.contains(HealthDataType.WORKOUT)) {
      mTypes.add(HealthDataType.WORKOUT);
      mPermissions.add(mPermissions[index]);
    }
  }

  List<HealthDataType> _normalizeTypesForChanges(List<HealthDataType> types) {
    final normalized = List<HealthDataType>.from(types, growable: true);

    final bmiIndex = normalized.indexOf(HealthDataType.BODY_MASS_INDEX);
    if (bmiIndex != -1) {
      normalized.removeAt(bmiIndex);
      if (!normalized.contains(HealthDataType.WEIGHT)) {
        normalized.add(HealthDataType.WEIGHT);
      }
      if (!normalized.contains(HealthDataType.HEIGHT)) {
        normalized.add(HealthDataType.HEIGHT);
      }
    }

    if (normalized.contains(HealthDataType.WORKOUT_ROUTE) && !normalized.contains(HealthDataType.WORKOUT)) {
      normalized.add(HealthDataType.WORKOUT);
    }

    return normalized.toSet().toList();
  }

  /// Calculate the BMI using the last observed height and weight values.
  Future<List<HealthDataPoint>> _computeAndroidBMI(
    DateTime startTime,
    DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter,
  ) async {
    List<HealthDataPoint> heights = await _prepareQuery(
      startTime,
      endTime,
      HealthDataType.HEIGHT,
      recordingMethodsToFilter,
    );

    if (heights.isEmpty) {
      return [];
    }

    List<HealthDataPoint> weights = await _prepareQuery(
      startTime,
      endTime,
      HealthDataType.WEIGHT,
      recordingMethodsToFilter,
    );

    double h = (heights.last.value as NumericHealthValue).numericValue.toDouble();

    const dataType = HealthDataType.BODY_MASS_INDEX;
    final unit = dataTypeToUnit[dataType]!;

    final bmiHealthPoints = <HealthDataPoint>[];
    for (var i = 0; i < weights.length; i++) {
      final bmiValue = (weights[i].value as NumericHealthValue).numericValue.toDouble() / (h * h);
      final x = HealthDataPoint(
        uuid: '',
        value: NumericHealthValue(numericValue: bmiValue),
        type: dataType,
        unit: unit,
        dateFrom: weights[i].dateFrom,
        dateTo: weights[i].dateTo,
        sourcePlatform: platformType,
        sourceDeviceId: _deviceId!,
        sourceId: '',
        sourceName: '',
        recordingMethod: RecordingMethod.unknown,
      );

      bmiHealthPoints.add(x);
    }
    return bmiHealthPoints;
  }

  /// Write health data.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// Parameters:
  ///  * [value] - the health data's value in double
  ///  * [unit] - **iOS ONLY** the unit the health data is measured in.
  ///  * [type] - the value's HealthDataType
  ///  * [startTime] - the start time when this [value] is measured.
  ///    It must be equal to or earlier than [endTime].
  ///  * [endTime] - the end time when this [value] is measured.
  ///    It must be equal to or later than [startTime].
  ///    Simply set [endTime] equal to [startTime] if the [value] is measured
  ///    only at a specific point in time (default).
  ///  * [recordingMethod] - the recording method of the data point, automatic by default.
  ///    (on iOS this must be manual or automatic)
  ///
  /// Values for Sleep and Headache are ignored and will be automatically assigned
  /// the default value.
  Future<String?> writeHealthData({
    required double value,
    HealthDataUnit? unit,
    required HealthDataType type,
    required DateTime startTime,
    String? clientRecordId,
    double? clientRecordVersion,
    DateTime? endTime,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    await _checkIfDataTypeAvailableOnDevice(type);
    if (Platform.isIOS && [RecordingMethod.active, RecordingMethod.unknown].contains(recordingMethod)) {
      throw ArgumentError("recordingMethod must be manual or automatic on iOS");
    }

    if (type == HealthDataType.WORKOUT) {
      throw ArgumentError("Adding workouts should be done using the writeWorkoutData method.");
    }
    if (type == HealthDataType.ACTIVITY_INTENSITY) {
      throw ArgumentError("Adding activity intensity data should be done using the writeActivityIntensity method.");
    }
    // If not implemented on platform, throw an exception
    if (!isDataTypeAvailable(type)) {
      throw HealthException(type, 'Not available on platform $platformType');
    }
    endTime ??= startTime;
    if (startTime.isAfter(endTime)) {
      throw ArgumentError("startTime must be equal or earlier than endTime");
    }
    if ({
          HealthDataType.HIGH_HEART_RATE_EVENT,
          HealthDataType.LOW_HEART_RATE_EVENT,
          HealthDataType.IRREGULAR_HEART_RATE_EVENT,
          HealthDataType.ELECTROCARDIOGRAM,
        }.contains(type) &&
        Platform.isIOS) {
      throw ArgumentError("$type - iOS does not support writing this data type in HealthKit");
    }

    // Assign default unit if not specified
    unit ??= dataTypeToUnit[type]!;

    // Align values to type in cases where the type defines the value.
    // E.g. SLEEP_IN_BED should have value 0
    if (type == HealthDataType.SLEEP_ASLEEP ||
        type == HealthDataType.SLEEP_AWAKE ||
        type == HealthDataType.SLEEP_IN_BED ||
        type == HealthDataType.SLEEP_DEEP ||
        type == HealthDataType.SLEEP_REM ||
        type == HealthDataType.SLEEP_LIGHT ||
        type == HealthDataType.HEADACHE_NOT_PRESENT ||
        type == HealthDataType.HEADACHE_MILD ||
        type == HealthDataType.HEADACHE_MODERATE ||
        type == HealthDataType.HEADACHE_SEVERE ||
        type == HealthDataType.HEADACHE_UNSPECIFIED) {
      value = _alignValue(type).toDouble();
    }

    Map<String, dynamic> args = {
      'value': value,
      'dataTypeKey': type.name,
      'dataUnitKey': unit.name,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'recordingMethod': recordingMethod.toInt(),
      'clientRecordId': clientRecordId,
      'clientRecordVersion': clientRecordVersion,
    };
    final result = await _channel.invokeMethod('writeData', args);
    if (result == null || result == false) return null;
    return '$result';
  }

  /// Writes an [ActivityIntensityRecord] to Google Health Connect.
  ///
  /// This API is Android only.
  Future<bool> writeActivityIntensity({
    required ActivityIntensityLevel intensityLevel,
    required DateTime startTime,
    DateTime? endTime,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
    String? clientRecordId,
    double? clientRecordVersion,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('writeActivityIntensity is only available on Android');
    }

    await _checkIfHealthConnectAvailableOnAndroid();

    endTime ??= startTime;
    if (startTime.isAfter(endTime)) {
      throw ArgumentError("startTime must be equal or earlier than endTime");
    }

    final intensityValue = intensityLevel.toAndroidValue();
    if (intensityValue == -1) {
      throw ArgumentError('Unknown activity intensity level provided.');
    }

    Map<String, dynamic> args = {
      'intensityType': intensityValue,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'recordingMethod': recordingMethod.toInt(),
      'clientRecordId': clientRecordId,
      'clientRecordVersion': clientRecordVersion,
    };

    final bool? success = await _channel.invokeMethod('writeActivityIntensity', args);
    return success ?? false;
  }

  /// Deletes all records of the given [type] for a given period of time.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// Parameters:
  ///  * [type] - the value's HealthDataType.
  ///  * [startTime] - the start time when this [value] is measured.
  ///    Must be equal to or earlier than [endTime].
  ///  * [endTime] - the end time when this [value] is measured.
  ///    Must be equal to or later than [startTime].
  Future<bool> delete({required HealthDataType type, required DateTime startTime, DateTime? endTime}) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    endTime ??= startTime;
    if (startTime.isAfter(endTime)) {
      throw ArgumentError("startTime must be equal or earlier than endTime");
    }

    Map<String, dynamic> args = {
      'dataTypeKey': type.name,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
    };
    bool? success = await _channel.invokeMethod('delete', args);
    return success ?? false;
  }

  /// Deletes a specific health record by its UUID.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// Parameters:
  ///  * [uuid] - The UUID of the health record to delete.
  ///  * [type] - The health data type of the record. Required on iOS.
  ///
  /// On Android, only the UUID is required. On iOS, both UUID and type are required.
  Future<bool> deleteByUUID({required String uuid, HealthDataType? type}) async {
    await _checkIfHealthConnectAvailableOnAndroid();

    if (uuid.isEmpty || uuid == "") {
      throw ArgumentError("UUID must not be empty.");
    }

    if (Platform.isIOS && type == null) {
      throw ArgumentError("On iOS, both UUID and type are required to delete a record.");
    }

    Map<String, dynamic> args = {'uuid': uuid, 'dataTypeKey': type?.name};

    bool? success = await _channel.invokeMethod('deleteByUUID', args);
    return success ?? false;
  }

  Future<bool> deleteByClientRecordId({
    required HealthDataType dataTypeKey,
    required String clientRecordId,
    String? recordId,
  }) async {
    await _checkIfHealthConnectAvailableOnAndroid();

    Map<String, dynamic> args = {
      'dataTypeKey': dataTypeKey.name,
      'recordId': recordId,
      'clientRecordId': clientRecordId,
    };
    bool? success = await _channel.invokeMethod('deleteByClientRecordId', args);
    return success ?? false;
  }

  /// Saves a blood pressure record.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// Parameters:
  ///  * [systolic] - the systolic part of the blood pressure.
  ///  * [diastolic] - the diastolic part of the blood pressure.
  ///  * [startTime] - the start time when this [value] is measured.
  ///    Must be equal to or earlier than [endTime].
  ///  * [endTime] - the end time when this [value] is measured.
  ///    Must be equal to or later than [startTime].
  ///    Simply set [endTime] equal to [startTime] if the blood pressure is measured
  ///    only at a specific point in time. If omitted, [endTime] is set to [startTime].
  ///  * [recordingMethod] - the recording method of the data point.
  Future<bool> writeBloodPressure({
    required int systolic,
    required int diastolic,
    required DateTime startTime,
    String? clientRecordId,
    double? clientRecordVersion,
    DateTime? endTime,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    if (Platform.isIOS && [RecordingMethod.active, RecordingMethod.unknown].contains(recordingMethod)) {
      throw ArgumentError("recordingMethod must be manual or automatic on iOS");
    }

    endTime ??= startTime;
    if (startTime.isAfter(endTime)) {
      throw ArgumentError("startTime must be equal or earlier than endTime");
    }

    Map<String, dynamic> args = {
      'systolic': systolic,
      'diastolic': diastolic,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'recordingMethod': recordingMethod.toInt(),
      'clientRecordId': clientRecordId,
      'clientRecordVersion': clientRecordVersion,
    };
    return await _channel.invokeMethod('writeBloodPressure', args) == true;
  }

  /// Saves blood oxygen saturation record.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// Parameters:
  ///  * [saturation] - the saturation of the blood oxygen in percentage
  ///  * [startTime] - the start time when this [saturation] is measured.
  ///    Must be equal to or earlier than [endTime].
  ///  * [endTime] - the end time when this [saturation] is measured.
  ///    Must be equal to or later than [startTime].
  ///    Simply set [endTime] equal to [startTime] if the blood oxygen saturation
  ///    is measured only at a specific point in time (default).
  ///  * [recordingMethod] - the recording method of the data point.
  Future<bool> writeBloodOxygen({
    required double saturation,
    required DateTime startTime,
    DateTime? endTime,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    if (Platform.isIOS && [RecordingMethod.active, RecordingMethod.unknown].contains(recordingMethod)) {
      throw ArgumentError("recordingMethod must be manual or automatic on iOS");
    }

    endTime ??= startTime;
    if (startTime.isAfter(endTime)) {
      throw ArgumentError("startTime must be equal or earlier than endTime");
    }
    bool? success;

    if (Platform.isIOS) {
      final uuid = await writeHealthData(
        value: saturation,
        type: HealthDataType.BLOOD_OXYGEN,
        startTime: startTime,
        endTime: endTime,
        recordingMethod: recordingMethod,
      );
      success = uuid != null;
    } else if (Platform.isAndroid) {
      Map<String, dynamic> args = {
        'value': saturation,
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
        'dataTypeKey': HealthDataType.BLOOD_OXYGEN.name,
        'recordingMethod': recordingMethod.toInt(),
      };
      success = await _channel.invokeMethod('writeBloodOxygen', args);
    }
    return success ?? false;
  }

  /// Saves meal record into Apple Health or Health Connect.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// Parameters:
  ///  * [mealType] - the type of meal.
  ///  * [startTime] - the start time when the meal was consumed.
  ///    It must be equal to or earlier than [endTime].
  ///  * [endTime] - the end time when the meal was consumed.
  ///    It must be equal to or later than [startTime].
  ///  * [name] - optional name information about this meal.
  ///  * [caloriesConsumed] - total calories consumed with this meal.
  ///  * [carbohydrates] - optional carbohydrates information.
  ///  * [protein] - optional protein information.
  ///  * [fatTotal] - optional total fat information.
  ///  * [caffeine] - optional caffeine information.
  ///  * [vitaminA] - optional vitamin A information.
  ///  * [b1Thiamin] - optional vitamin B1 (thiamin) information.
  ///  * [b2Riboflavin] - optional vitamin B2 (riboflavin) information.
  ///  * [b3Niacin] - optional vitamin B3 (niacin) information.
  ///  * [b5PantothenicAcid] - optional vitamin B5 (pantothenic acid) information.
  ///  * [b6Pyridoxine] - optional vitamin B6 (pyridoxine) information.
  ///  * [b7Biotin] - optional vitamin B7 (biotin) information.
  ///  * [b9Folate] - optional vitamin B9 (folate) information.
  ///  * [b12Cobalamin] - optional vitamin B12 (cobalamin) information.
  ///  * [vitaminC] - optional vitamin C information.
  ///  * [vitaminD] - optional vitamin D information.
  ///  * [vitaminE] - optional vitamin E information.
  ///  * [vitaminK] - optional vitamin K information.
  ///  * [calcium] - optional calcium information.
  ///  * [cholesterol] - optional cholesterol information.
  ///  * [chloride] - optional chloride information.
  ///  * [chromium] - optional chromium information.
  ///  * [copper] - optional copper information.
  ///  * [fatUnsaturated] - optional unsaturated fat information.
  ///  * [fatMonounsaturated] - optional monounsaturated fat information.
  ///  * [fatPolyunsaturated] - optional polyunsaturated fat information.
  ///  * [fatSaturated] - optional saturated fat information.
  ///  * [fatTransMonoenoic] - optional trans-monoenoic fat information.
  ///  * [fiber] - optional fiber information.
  ///  * [iodine] - optional iodine information.
  ///  * [iron] - optional iron information.
  ///  * [magnesium] - optional magnesium information.
  ///  * [manganese] - optional manganese information.
  ///  * [molybdenum] - optional molybdenum information.
  ///  * [phosphorus] - optional phosphorus information.
  ///  * [potassium] - optional potassium information.
  ///  * [selenium] - optional selenium information.
  ///  * [sodium] - optional sodium information.
  ///  * [sugar] - optional sugar information.
  ///  * [water] - optional water information.
  ///  * [zinc] - optional zinc information.
  ///  * [recordingMethod] - the recording method of the data point.
  Future<bool> writeMeal({
    required MealType mealType,
    required DateTime startTime,
    required DateTime endTime,
    String? clientRecordId,
    double? clientRecordVersion,
    double? caloriesConsumed,
    double? carbohydrates,
    double? protein,
    double? fatTotal,
    String? name,
    double? caffeine,
    double? vitaminA,
    double? b1Thiamin,
    double? b2Riboflavin,
    double? b3Niacin,
    double? b5PantothenicAcid,
    double? b6Pyridoxine,
    double? b7Biotin,
    double? b9Folate,
    double? b12Cobalamin,
    double? vitaminC,
    double? vitaminD,
    double? vitaminE,
    double? vitaminK,
    double? calcium,
    double? cholesterol,
    double? chloride,
    double? chromium,
    double? copper,
    double? fatUnsaturated,
    double? fatMonounsaturated,
    double? fatPolyunsaturated,
    double? fatSaturated,
    double? fatTransMonoenoic,
    double? fiber,
    double? iodine,
    double? iron,
    double? magnesium,
    double? manganese,
    double? molybdenum,
    double? phosphorus,
    double? potassium,
    double? selenium,
    double? sodium,
    double? sugar,
    double? water,
    double? zinc,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    if (Platform.isIOS && [RecordingMethod.active, RecordingMethod.unknown].contains(recordingMethod)) {
      throw ArgumentError("recordingMethod must be manual or automatic on iOS");
    }

    if (startTime.isAfter(endTime)) {
      throw ArgumentError("startTime must be equal or earlier than endTime");
    }

    Map<String, dynamic> args = {
      'name': name,
      'meal_type': mealType.name,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime.millisecondsSinceEpoch,
      'clientRecordId': clientRecordId,
      'clientRecordVersion': clientRecordVersion,
      'calories': caloriesConsumed,
      'carbs': carbohydrates,
      'protein': protein,
      'fat': fatTotal,
      'caffeine': caffeine,
      'vitamin_a': vitaminA,
      'b1_thiamin': b1Thiamin,
      'b2_riboflavin': b2Riboflavin,
      'b3_niacin': b3Niacin,
      'b5_pantothenic_acid': b5PantothenicAcid,
      'b6_pyridoxine': b6Pyridoxine,
      'b7_biotin': b7Biotin,
      'b9_folate': b9Folate,
      'b12_cobalamin': b12Cobalamin,
      'vitamin_c': vitaminC,
      'vitamin_d': vitaminD,
      'vitamin_e': vitaminE,
      'vitamin_k': vitaminK,
      'calcium': calcium,
      'cholesterol': cholesterol,
      'chloride': chloride,
      'chromium': chromium,
      'copper': copper,
      'fat_unsaturated': fatUnsaturated,
      'fat_monounsaturated': fatMonounsaturated,
      'fat_polyunsaturated': fatPolyunsaturated,
      'fat_saturated': fatSaturated,
      'fat_trans_monoenoic': fatTransMonoenoic,
      'fiber': fiber,
      'iodine': iodine,
      'iron': iron,
      'magnesium': magnesium,
      'manganese': manganese,
      'molybdenum': molybdenum,
      'phosphorus': phosphorus,
      'potassium': potassium,
      'selenium': selenium,
      'sodium': sodium,
      'sugar': sugar,
      'water': water,
      'zinc': zinc,
      'recordingMethod': recordingMethod.toInt(),
    };
    bool? success = await _channel.invokeMethod('writeMeal', args);
    return success ?? false;
  }

  /// Save menstruation flow into Apple Health and Google Health Connect.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// Parameters:
  ///  * [flow] - the menstrual flow
  ///  * [startTime] - the start time when the menstrual flow is measured.
  ///  * [endTime] - the start time when the menstrual flow is measured.
  ///  * [isStartOfCycle] - A bool that indicates whether the sample represents
  ///    the start of a menstrual cycle.
  ///  * [recordingMethod] - the recording method of the data point.
  Future<bool> writeMenstruationFlow({
    required MenstrualFlow flow,
    required DateTime startTime,
    required DateTime endTime,
    required bool isStartOfCycle,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    if (Platform.isIOS && [RecordingMethod.active, RecordingMethod.unknown].contains(recordingMethod)) {
      throw ArgumentError("recordingMethod must be manual or automatic on iOS");
    }

    var value = Platform.isAndroid ? MenstrualFlow.toHealthConnect(flow) : flow.index;

    if (value == -1) {
      throw ArgumentError("$flow is not a valid menstrual flow value for $platformType");
    }

    Map<String, dynamic> args = {
      'value': value,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'isStartOfCycle': isStartOfCycle,
      'dataTypeKey': HealthDataType.MENSTRUATION_FLOW.name,
      'recordingMethod': recordingMethod.toInt(),
    };
    return await _channel.invokeMethod('writeMenstruationFlow', args) == true;
  }

  /// Saves audiogram into Apple Health. Not supported on Android.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// Parameters:
  ///   * [frequencies] - array of frequencies of the test
  ///   * [leftEarSensitivities] threshold in decibel for the left ear
  ///   * [rightEarSensitivities] threshold in decibel for the left ear
  ///   * [startTime] - the start time when the audiogram is measured.
  ///     It must be equal to or earlier than [endTime].
  ///   * [endTime] - the end time when the audiogram is measured.
  ///     It must be equal to or later than [startTime].
  ///     Simply set [endTime] equal to [startTime] if the audiogram is measured
  ///     only at a specific point in time (default).
  ///   * [metadata] - optional map of keys, both HKMetadataKeyExternalUUID
  ///     and HKMetadataKeyDeviceName are required
  Future<bool> writeAudiogram({
    required List<double> frequencies,
    required List<double> leftEarSensitivities,
    required List<double> rightEarSensitivities,
    required DateTime startTime,
    DateTime? endTime,
    Map<String, dynamic>? metadata,
  }) async {
    if (frequencies.isEmpty || leftEarSensitivities.isEmpty || rightEarSensitivities.isEmpty) {
      throw ArgumentError("frequencies, leftEarSensitivities and rightEarSensitivities can't be empty");
    }
    if (frequencies.length != leftEarSensitivities.length ||
        rightEarSensitivities.length != leftEarSensitivities.length) {
      throw ArgumentError("frequencies, leftEarSensitivities and rightEarSensitivities need to be of the same length");
    }
    endTime ??= startTime;
    if (startTime.isAfter(endTime)) {
      throw ArgumentError("startTime must be equal or earlier than endTime");
    }
    if (Platform.isAndroid) {
      throw UnsupportedError("writeAudiogram is not supported on Android");
    }

    Map<String, dynamic> args = {
      'frequencies': frequencies,
      'leftEarSensitivities': leftEarSensitivities,
      'rightEarSensitivities': rightEarSensitivities,
      'dataTypeKey': HealthDataType.AUDIOGRAM.name,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'metadata': metadata,
    };
    return await _channel.invokeMethod('writeAudiogram', args) == true;
  }

  /// Saves insulin delivery record into Apple Health.
  ///
  /// Returns true if successful, false otherwise.
  ///
  /// Parameters:
  ///  * [units] - the number of units of insulin taken.
  ///  * [reason] - the insulin reason, basal or bolus.
  ///  * [startTime] - the start time when the meal was consumed.
  ///    It must be equal to or earlier than [endTime].
  ///  * [endTime] - the end time when the meal was consumed.
  ///    It must be equal to or later than [startTime].
  Future<bool> writeInsulinDelivery(
    double units,
    InsulinDeliveryReason reason,
    DateTime startTime,
    DateTime endTime,
  ) async {
    if (startTime.isAfter(endTime)) {
      throw ArgumentError("startTime must be equal or earlier than endTime");
    }

    if (reason == InsulinDeliveryReason.NOT_SET) {
      throw ArgumentError("set a valid insulin delivery reason");
    }

    if (Platform.isAndroid) {
      throw UnsupportedError("writeInsulinDelivery is not supported on Android");
    }

    Map<String, dynamic> args = {
      'units': units,
      'reason': reason.index,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
    };

    bool? success = await _channel.invokeMethod('writeInsulinDelivery', args);
    return success ?? false;
  }

  /// [iOS only] Fetch a `HealthDataPoint` by `uuid` and `type`. Returns `null` if no matching record.
  ///
  /// Parameters:
  ///  * [uuid] - UUID of your saved health data point (e.g. A91A2F10-3D7B-486A-B140-5ADCD3C9C6D0)
  ///  * [type] - Data type of your saved health data point (e.g. HealthDataType.WORKOUT)
  ///
  /// Assuming above data are coming from your database.
  ///
  /// Note: this feature is only for iOS at this moment due to
  /// requires refactoring for Android.
  Future<HealthDataPoint?> getHealthDataByUUID({required String uuid, required HealthDataType type}) async {
    if (uuid.isEmpty) {
      throw HealthException(type, 'UUID is empty!');
    }

    await _checkIfHealthConnectAvailableOnAndroid();

    // Ask for device ID only once
    _deviceId ??= Platform.isAndroid
        ? (await _deviceInfo.androidInfo).id
        : (await _deviceInfo.iosInfo).identifierForVendor;

    // If not implemented on platform, throw an exception
    await _checkIfDataTypeAvailableOnDevice(type);
    if (!isDataTypeAvailable(type)) {
      throw HealthException(type, 'Not available on platform $platformType');
    }

    final result = await _dataQueryByUUID(uuid, type);

    debugPrint('data by UUID: ${result?.toString()}');

    return result;
  }

  /// Fetch a list of health data points based on [types].
  /// You can also specify the [recordingMethodsToFilter] to filter the data points.
  /// If not specified, all data points will be included.
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    List<HealthDataPoint> dataPoints = [];

    for (var type in types) {
      final result = await _prepareQuery(
        startTime,
        endTime,
        type,
        recordingMethodsToFilter,
        dataUnit: preferredUnits?[type],
      );
      dataPoints.addAll(result);
    }

    const int threshold = 100;
    if (dataPoints.length > threshold) {
      return compute(removeDuplicates, dataPoints);
    }

    return removeDuplicates(dataPoints);
  }

  /// Fetch a list of health data points based on [types].
  /// You can also specify the [recordingMethodsToFilter] to filter the data points.
  /// If not specified, all data points will be included.Vkk
  Future<List<HealthDataPoint>> getHealthIntervalDataFromTypes({
    required DateTime startDate,
    required DateTime endDate,
    required List<HealthDataType> types,
    required int interval,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    List<HealthDataPoint> dataPoints = [];

    for (var type in types) {
      final result = await _prepareIntervalQuery(startDate, endDate, type, interval, recordingMethodsToFilter);
      dataPoints.addAll(result);
    }

    return removeDuplicates(dataPoints);
  }

  /// Fetch a list of health data points based on [types].
  Future<List<HealthDataPoint>> getHealthAggregateDataFromTypes({
    required List<HealthDataType> types,
    required DateTime startDate,
    required DateTime endDate,
    int activitySegmentDuration = 1,
    bool includeManualEntry = true,
  }) async {
    await _checkIfHealthConnectAvailableOnAndroid();
    List<HealthDataPoint> dataPoints = [];

    final result = await _prepareAggregateQuery(startDate, endDate, types, activitySegmentDuration, includeManualEntry);
    dataPoints.addAll(result);

    return removeDuplicates(dataPoints);
  }

  /// Create a Health Connect changes token for the provided [types].
  ///
  /// Android only. Returns null on iOS or if an error occurs.
  Future<String?> getChangesToken({required List<HealthDataType> types}) async {
    if (Platform.isIOS) return null;

    await _checkIfHealthConnectAvailableOnAndroid();
    if (types.isEmpty) {
      throw ArgumentError('The list of [types] must not be empty.');
    }

    final normalizedTypes = _normalizeTypesForChanges(types);
    if (normalizedTypes.isEmpty) {
      throw ArgumentError('No supported types supplied for change token creation.');
    }

    for (final type in normalizedTypes) {
      await _checkIfDataTypeAvailableOnDevice(type);
      if (!isDataTypeAvailable(type)) {
        throw HealthException(type, 'Not available on platform $platformType');
      }
    }

    try {
      return await _channel.invokeMethod<String>('getChangesToken', {
        'types': normalizedTypes.map((type) => type.name).toList(),
      });
    } catch (e) {
      debugPrint('$runtimeType - Exception in getChangesToken(): $e');
      return null;
    }
  }

  /// Fetch the next page of changes for a previously created token.
  ///
  /// Android only. Returns null on iOS or if an error occurs.
  Future<HealthChangesResponse?> getChanges({required String changesToken, bool includeSelf = false}) async {
    if (Platform.isIOS) return null;

    await _checkIfHealthConnectAvailableOnAndroid();
    if (changesToken.isEmpty) {
      throw ArgumentError('The [changesToken] must not be empty.');
    }

    try {
      final response = await _channel.invokeMethod('getChanges', {
        'changesToken': changesToken,
        'includeSelf': includeSelf,
      });

      if (response is Map) {
        return HealthChangesResponse.fromMethodChannel(response);
      }
      return null;
    } catch (e) {
      debugPrint('$runtimeType - Exception in getChanges(): $e');
      return null;
    }
  }

  /// Prepares an interval query, i.e. checks if the types are available, etc.
  Future<List<HealthDataPoint>> _prepareQuery(
    DateTime startTime,
    DateTime endTime,
    HealthDataType dataType,
    List<RecordingMethod> recordingMethodsToFilter, {
    HealthDataUnit? dataUnit,
  }) async {
    // Ask for device ID only once
    _deviceId ??= Platform.isAndroid
        ? (await _deviceInfo.androidInfo).id
        : (await _deviceInfo.iosInfo).identifierForVendor;

    // If not implemented on platform, throw an exception
    await _checkIfDataTypeAvailableOnDevice(dataType);
    if (!isDataTypeAvailable(dataType)) {
      throw HealthException(dataType, 'Not available on platform $platformType');
    }

    // If BodyMassIndex is requested on Android, calculate this manually
    if (dataType == HealthDataType.BODY_MASS_INDEX && Platform.isAndroid) {
      return _computeAndroidBMI(startTime, endTime, recordingMethodsToFilter);
    }
    return await _dataQuery(startTime, endTime, dataType, recordingMethodsToFilter, dataUnit: dataUnit);
  }

  /// Prepares an interval query, i.e. checks if the types are available, etc.
  Future<List<HealthDataPoint>> _prepareIntervalQuery(
    DateTime startDate,
    DateTime endDate,
    HealthDataType dataType,
    int interval,
    List<RecordingMethod> recordingMethodsToFilter,
  ) async {
    // Ask for device ID only once
    _deviceId ??= Platform.isAndroid
        ? (await _deviceInfo.androidInfo).id
        : (await _deviceInfo.iosInfo).identifierForVendor;

    // If not implemented on platform, throw an exception
    await _checkIfDataTypeAvailableOnDevice(dataType);
    if (!isDataTypeAvailable(dataType)) {
      throw HealthException(dataType, 'Not available on platform $platformType');
    }

    return await _dataIntervalQuery(startDate, endDate, dataType, interval, recordingMethodsToFilter);
  }

  /// Prepares an aggregate query, i.e. checks if the types are available, etc.
  Future<List<HealthDataPoint>> _prepareAggregateQuery(
    DateTime startDate,
    DateTime endDate,
    List<HealthDataType> dataTypes,
    int activitySegmentDuration,
    bool includeManualEntry,
  ) async {
    // Ask for device ID only once
    _deviceId ??= Platform.isAndroid
        ? (await _deviceInfo.androidInfo).id
        : (await _deviceInfo.iosInfo).identifierForVendor;

    for (var type in dataTypes) {
      // If not implemented on platform, throw an exception
      await _checkIfDataTypeAvailableOnDevice(type);
      if (!isDataTypeAvailable(type)) {
        throw HealthException(type, 'Not available on platform $platformType');
      }
    }

    return await _dataAggregateQuery(startDate, endDate, dataTypes, activitySegmentDuration, includeManualEntry);
  }

  /// Fetches data points from Android/iOS native code.
  Future<List<HealthDataPoint>> _dataQuery(
    DateTime startTime,
    DateTime endTime,
    HealthDataType dataType,
    List<RecordingMethod> recordingMethodsToFilter, {
    HealthDataUnit? dataUnit,
  }) async {
    String? unit = dataUnit?.name ?? dataTypeToUnit[dataType]?.name;
    final args = <String, dynamic>{
      'dataTypeKey': dataType.name,
      'dataUnitKey': unit,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'recordingMethodsToFilter': recordingMethodsToFilter.map((e) => e.toInt()).toList(),
    };
    final fetchedDataPoints = await _channel.invokeMethod('getData', args);

    if (fetchedDataPoints != null && fetchedDataPoints is List) {
      final msg = <String, dynamic>{"dataType": dataType, "dataPoints": fetchedDataPoints, "unit": unit};
      const thresHold = 100;
      // If the no. of data points are larger than the threshold,
      // call the compute method to spawn an Isolate to do the parsing in a separate thread.
      if (fetchedDataPoints.length > thresHold) {
        return compute(_parse, msg);
      }
      return _parse(msg);
    } else {
      return <HealthDataPoint>[];
    }
  }

  /// Fetches single data point by `uuid` and `type` from Android/iOS native code.
  Future<HealthDataPoint?> _dataQueryByUUID(String uuid, HealthDataType dataType) async {
    final args = <String, dynamic>{
      'dataTypeKey': dataType.name,
      'dataUnitKey': dataTypeToUnit[dataType]!.name,
      'uuid': uuid,
    };

    final fetchedDataPoint = await _channel.invokeMethod('getDataByUUID', args);

    // fetchedDataPoint is Map<Object, Object>. // Must be converted to List first
    // so no need to recreate _parse() to handle single HealthDataPoint.

    if (fetchedDataPoint != null) {
      final msg = <String, dynamic>{
        "dataType": dataType,
        "dataPoints": [fetchedDataPoint],
      };

      // get single record of parsed fetchedDataPoints
      return _parse(msg).first;
    } else {
      return null;
    }
  }

  /// function for fetching statistic health data
  Future<List<HealthDataPoint>> _dataIntervalQuery(
    DateTime startDate,
    DateTime endDate,
    HealthDataType dataType,
    int interval,
    List<RecordingMethod> recordingMethodsToFilter,
  ) async {
    final args = <String, dynamic>{
      'dataTypeKey': dataType.name,
      'dataUnitKey': dataTypeToUnit[dataType]!.name,
      'startTime': startDate.millisecondsSinceEpoch,
      'endTime': endDate.millisecondsSinceEpoch,
      'interval': interval,
      'recordingMethodsToFilter': recordingMethodsToFilter.map((e) => e.toInt()).toList(),
    };

    final fetchedDataPoints = await _channel.invokeMethod('getIntervalData', args);
    if (fetchedDataPoints != null) {
      final msg = <String, dynamic>{"dataType": dataType, "dataPoints": fetchedDataPoints};
      return _parse(msg);
    }
    return <HealthDataPoint>[];
  }

  /// function for fetching statistic health data
  Future<List<HealthDataPoint>> _dataAggregateQuery(
    DateTime startDate,
    DateTime endDate,
    List<HealthDataType> dataTypes,
    int activitySegmentDuration,
    bool includeManualEntry,
  ) async {
    final args = <String, dynamic>{
      'dataTypeKeys': dataTypes.map((dataType) => dataType.name).toList(),
      'startTime': startDate.millisecondsSinceEpoch,
      'endTime': endDate.millisecondsSinceEpoch,
      'activitySegmentDuration': activitySegmentDuration,
      'includeManualEntry': includeManualEntry,
    };

    final fetchedDataPoints = await _channel.invokeMethod('getAggregateData', args);

    if (fetchedDataPoints != null) {
      final msg = <String, dynamic>{"dataType": HealthDataType.WORKOUT, "dataPoints": fetchedDataPoints};
      return _parse(msg);
    }
    return <HealthDataPoint>[];
  }

  List<HealthDataPoint> _parse(Map<String, dynamic> message) {
    final dataType = message["dataType"] as HealthDataType;
    final dataPoints = message["dataPoints"] as List;
    String? unit = message["unit"] as String?;

    return dataPoints
        .map<HealthDataPoint>((dataPoint) => HealthDataPoint.fromHealthDataPoint(dataType, dataPoint, unit))
        .toList();
  }

  /// Return a list of [HealthDataPoint] based on [points] with no duplicates.
  List<HealthDataPoint> removeDuplicates(List<HealthDataPoint> points) => LinkedHashSet.of(points).toList();

  /// Get the total number of steps within a specific time period.
  /// Returns null if not successful.
  Future<int?> getTotalStepsInInterval(DateTime startTime, DateTime endTime, {bool includeManualEntry = true}) async {
    final args = <String, dynamic>{
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'recordingMethodsToFilter': includeManualEntry ? <RecordingMethod>[] : [RecordingMethod.manual.toInt()],
    };
    final stepsCount = await _channel.invokeMethod<int?>('getTotalStepsInInterval', args);
    return stepsCount;
  }

  /// Assigns numbers to specific [HealthDataType]s.
  int _alignValue(HealthDataType type) => switch (type) {
    HealthDataType.SLEEP_IN_BED => 0,
    HealthDataType.SLEEP_ASLEEP => 1,
    HealthDataType.SLEEP_AWAKE => 2,
    HealthDataType.SLEEP_LIGHT => 3,
    HealthDataType.SLEEP_DEEP => 4,
    HealthDataType.SLEEP_REM => 5,
    HealthDataType.HEADACHE_UNSPECIFIED => 0,
    HealthDataType.HEADACHE_NOT_PRESENT => 1,
    HealthDataType.HEADACHE_MILD => 2,
    HealthDataType.HEADACHE_MODERATE => 3,
    HealthDataType.HEADACHE_SEVERE => 4,
    _ => throw HealthException(
      type,
      "HealthDataType was not aligned correctly - please report bug at https://github.com/carp-dk/carp-health-flutter/issues",
    ),
  };

  /// Write workout data to Apple Health or Google Health Connect.
  ///
  /// The type-specific client IDs and version identify one frozen logical
  /// export. Reuse them when reconciling an ambiguous submission.
  Future<HealthWorkoutWriteResult> writeWorkoutData({
    required String workoutClientRecordId,
    String? energyClientRecordId,
    required int clientRecordVersion,
    required HealthWorkoutActivityType activityType,
    required DateTime start,
    required DateTime end,
    required int startZoneOffsetSeconds,
    required int endZoneOffsetSeconds,
    double? activeEnergyKcal,
    required String title,
    required HealthRecordingProvenance recordingProvenance,
    required HealthRecordingDevice recordingDevice,
  }) async {
    _validateWorkoutIdentity(workoutClientRecordId, 'workoutClientRecordId');
    if (energyClientRecordId != null) {
      _validateWorkoutIdentity(energyClientRecordId, 'energyClientRecordId');
    }
    if (clientRecordVersion != 0) {
      throw ArgumentError.value(clientRecordVersion, 'clientRecordVersion', 'must be 0');
    }
    _validateWorkoutRange(start, end);
    _validateZoneOffsetSeconds(startZoneOffsetSeconds, 'startZoneOffsetSeconds');
    _validateZoneOffsetSeconds(endZoneOffsetSeconds, 'endZoneOffsetSeconds');
    if ((activeEnergyKcal == null) != (energyClientRecordId == null)) {
      throw ArgumentError('activeEnergyKcal and energyClientRecordId must be present together');
    }
    if (activeEnergyKcal != null && (!activeEnergyKcal.isFinite || activeEnergyKcal <= 0)) {
      throw ArgumentError.value(activeEnergyKcal, 'activeEnergyKcal', 'must be finite and positive');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must be nonblank');
    }
    if (!_isWorkoutActivitySupported(
      activityType,
      isIOS: _workoutPlatformIsIOS(),
      isAndroid: _workoutPlatformIsAndroid(),
    )) {
      throw HealthException(activityType, 'Workout activity type is not supported');
    }

    final value = await _channel.invokeMethod<Object?>('writeWorkoutData', {
      'workoutClientRecordId': workoutClientRecordId.trim(),
      'energyClientRecordId': energyClientRecordId?.trim(),
      'clientRecordVersion': clientRecordVersion,
      'activityType': activityType.name,
      'startTime': start.millisecondsSinceEpoch,
      'endTime': end.millisecondsSinceEpoch,
      'startZoneOffsetSeconds': startZoneOffsetSeconds,
      'endZoneOffsetSeconds': endZoneOffsetSeconds,
      'activeEnergyKcal': activeEnergyKcal,
      'title': title.trim(),
      'recordingProvenance': recordingProvenance.name,
      'recordingDevice': recordingDevice.name,
    });
    return HealthWorkoutWriteResult.fromMethodChannel(value);
  }

  /// Reconciles this app's independently stored workout and energy records.
  Future<HealthWorkoutLookupResult> lookupWorkoutData({
    required String workoutClientRecordId,
    String? energyClientRecordId,
    required DateTime start,
    required DateTime end,
  }) async {
    _validateWorkoutIdentity(workoutClientRecordId, 'workoutClientRecordId');
    if (energyClientRecordId != null) {
      _validateWorkoutIdentity(energyClientRecordId, 'energyClientRecordId');
    }
    _validateWorkoutRange(start, end);

    final value = await _channel.invokeMethod<Object?>('lookupWorkoutData', {
      'workoutClientRecordId': workoutClientRecordId.trim(),
      'energyClientRecordId': energyClientRecordId?.trim(),
      'startTime': start.millisecondsSinceEpoch,
      'endTime': end.millisecondsSinceEpoch,
    });
    return HealthWorkoutLookupResult.fromMethodChannel(value);
  }

  /// Start a new workout route recording session on iOS or Android.
  ///
  /// Returns a builder identifier that must be supplied in subsequent calls
  /// to [insertWorkoutRouteData], [finishWorkoutRoute], or
  /// [discardWorkoutRoute].
  Future<String> startWorkoutRoute() async {
    final identifier = await _channel.invokeMethod<String>('startWorkoutRoute');
    if (identifier == null) {
      throw PlatformException(code: 'ROUTE_ERROR', message: 'Failed to start workout route builder.');
    }
    return identifier;
  }

  /// Append a batch of [locations] to an active workout route builder.
  ///
  /// The [builderId] must come from [startWorkoutRoute]. Locations should
  /// be ordered by ascending timestamp to mirror HealthKit’s expectations.
  Future<bool> insertWorkoutRouteData({
    required String builderId,
    required List<WorkoutRouteLocation> locations,
  }) async {
    final args = <String, dynamic>{
      'builderId': builderId,
      'locations': locations.map(_serializeWorkoutRouteLocationForNative).toList(),
    };
    return await _channel.invokeMethod<bool>('insertWorkoutRouteData', args) == true;
  }

  /// Finalises the workout route and associates it with an existing workout.
  ///
  /// Provide the [builderId] from [startWorkoutRoute], the platform-specific
  /// [workoutUuid] (such as [HealthWorkoutWriteResult.workoutRecordId]),
  /// and optional [metadata] that will be stored on the resulting route.
  ///
  /// Returns the created route’s UUID string.
  Future<String> finishWorkoutRoute({
    required String builderId,
    required String workoutUuid,
    Map<String, dynamic>? metadata,
  }) async {
    final args = <String, dynamic>{
      'builderId': builderId,
      'workoutUUID': workoutUuid,
      if (metadata != null) 'metadata': Map<String, dynamic>.from(metadata),
    };
    final response = await _channel.invokeMapMethod<String, dynamic>('finishWorkoutRoute', args);
    final routeUuid = response?['uuid'] as String?;
    if (routeUuid == null) {
      throw PlatformException(code: 'ROUTE_ERROR', message: 'Workout route completion failed.');
    }
    return routeUuid;
  }

  /// Discards any progress for the specified workout route builder.
  ///
  /// Returns `true` if the builder existed and was discarded successfully.
  Future<bool> discardWorkoutRoute(String builderId) async {
    final args = <String, dynamic>{'builderId': builderId};
    return await _channel.invokeMethod<bool>('discardWorkoutRoute', args) == true;
  }

  /// Checks support using explicit platform flags so validation is testable.
  bool _isWorkoutActivitySupported(HealthWorkoutActivityType type, {required bool isIOS, required bool isAndroid}) =>
      (!isIOS || healthWorkoutActivityTypesIOS.contains(type)) &&
      (!isAndroid || healthWorkoutActivityTypesAndroid.contains(type));
}

Map<String, dynamic> _serializeWorkoutRouteLocationForNative(WorkoutRouteLocation location) {
  final map = <String, dynamic>{
    'latitude': location.latitude,
    'longitude': location.longitude,
    'timestamp': location.timestamp.toUtc().millisecondsSinceEpoch,
  };
  void addIfNotNull(String key, Object? value) {
    if (value != null) map[key] = value;
  }

  addIfNotNull('altitude', location.altitude);
  addIfNotNull('horizontalAccuracy', location.horizontalAccuracy);
  addIfNotNull('verticalAccuracy', location.verticalAccuracy);
  addIfNotNull('speed', location.speed);
  addIfNotNull('course', location.course);
  addIfNotNull('speedAccuracy', location.speedAccuracy);
  addIfNotNull('courseAccuracy', location.courseAccuracy);

  return map;
}
