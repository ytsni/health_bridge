# health_bridge

A maintained fork of [`health`](https://pub.dev/packages/health) (carp-dk/carp-health-flutter v13.3.1). The upstream package has been inactive since early 2026 with 18 unmerged PRs and multiple production-breaking bugs. This fork applies those fixes and adds new features.

## Changes from upstream

- Removed `carp_serializable` dependency (inlined)
- Fixed iOS SIGABRT crash on TOTAL_CALORIES_BURNED
- Fixed Android ANRs (coroutine dispatchers, parallel workout queries)
- Fixed silent empty workout list when missing optional permissions
- Fixed `workoutSummary` always null on Android (camelCase/snake_case mismatch)
- Fixed outdoor run mapped to RUNNING_TREADMILL on iOS
- Deduplicated workout metrics to prevent double-counting from multiple sources
- `writeHealthData` exposes the created record UUID when available; workout
  export now returns a structured write result with source-scoped lookup and
  per-type authorization snapshots
- Added VO2 Max, Cycling Power, Cycling Cadence, Mindfulness (Android) data types
- Added WorkoutMetadata support for iOS (brand name, indoor/outdoor, coached, etc.)
- AGP 9.x compatibility
- Swift Package Manager support (CocoaPods still works)

---

The plugin supports:

- handling permissions to access health data using the `hasPermissions`, `requestAuthorization`, `revokePermissions` methods.
- reading health data using the `getHealthDataFromTypes` method.
- writing health data using the `writeHealthData` method.
- writing workouts using the `writeWorkoutData` method.
- writing workout routes on iOS and Android using the `startWorkoutRoute` / `insertWorkoutRouteData` / `finishWorkoutRoute` methods.
- writing meals on iOS (Apple Health) & Android using the `writeMeal` method.
- writing audiograms on iOS using the `writeAudiogram` method.
- writing blood pressure data using the `writeBloodPressure` method.
- accessing total step counts using the `getTotalStepsInInterval` method.
- cleaning up duplicate data points via the `removeDuplicates` method.
- removing data of a given type in a selected period of time using the `delete` method.

Note that for Android, the target phone **needs** to have the [Health Connect](https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata&hl=en) app installed (which is currently in beta) and have access to the internet.

See the tables below for supported health and workout data types.

## Setup

### Apple Health (iOS)

First, add the following 2 entries to the `Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>We will sync your data with the Apple Health app to give you better insights</string>
<key>NSHealthUpdateUsageDescription</key>
<string>We will sync your data with the Apple Health app to give you better insights</string>
```

Then, open your Flutter project in Xcode by right clicking on the "ios" folder and selecting "Open in Xcode". Next, enable "HealthKit" by adding a capability inside the "Signing & Capabilities" tab of the Runner target's settings.

That capability must add the HealthKit entitlement to the app:

```xml
<key>com.apple.developer.healthkit</key>
<true/>
```

HealthKit reports exact sharing (write) authorization, but deliberately does
not disclose exact read authorization. `getAuthorizationSnapshot` therefore
reports mapped iOS reads as `requestedOrUnknown`, never as a confirmed grant.
It accepts any nonempty, duplicate-free list of `HealthDataType` values.
Mapped types receive exact HealthKit write state; unmapped platform types are
reported as `unsupported` without weakening the response-set contract.

#### Authorization snapshot support matrix

Every snapshot result contains exactly the requested type set (native entry
order is not significant):

| Platform state | Read state | Write state |
| --- | --- | --- |
| iOS, mapped HealthKit type | `requestedOrUnknown` | Exact `authorizationStatus(for:)` mapping: `authorized`, `denied`, or `notDetermined` |
| Android, mapped Health Connect record | `authorized` when the read grant is present, otherwise `denied` | `authorized` when the write grant is present, otherwise `denied` |
| Either platform, unmapped type | `unsupported` | `unsupported` |
| Health service unavailable | `unavailable` | `unavailable` |

Android captures the granted-permission set once per snapshot, so mixed entries
describe one coherent instant. A later call reflects permission revocation.

### Google Health Connect (Android)

Health Connect requires the following lines in the `AndroidManifest.xml` file (see also the example app):

```xml
<!-- Check whether Health Connect is installed or not -->
<queries>
  <package android:name="com.google.android.apps.healthdata" />
  <intent>
    <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
  </intent>
</queries>
```

In the Health Connect permissions activity there is a link to your privacy policy. You need to grant the Health Connect app access in order to link back to your privacy policy. In the example below, you should either replace `.MainActivity` with an activity that presents the privacy policy or have the Main Activity route the user to the policy. This step may be required to pass Google app review when requesting access to sensitive permissions.

```xml
<activity-alias
     android:name="ViewPermissionUsageActivity"
     android:exported="true"
     android:targetActivity=".MainActivity"
     android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
        <intent-filter>
            <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
            <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
        </intent-filter>
</activity-alias>
```

For each data type you want to access, the READ and WRITE permissions need to be added to the `AndroidManifest.xml` file. The list of [permissions](https://developer.android.com/health-and-fitness/guides/health-connect/plan/data-types#permissions) can be found here on the [data types](https://developer.android.com/health-and-fitness/guides/health-connect/plan/data-types) page.

An example of asking for permission to read and write heart rate data is shown below and more examples can also be found in the example app.

```xml
<uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
<uses-permission android:name="android.permission.health.WRITE_HEART_RATE"/>
```

For workout export, request only the permissions for the records being
written:

```xml
<uses-permission android:name="android.permission.health.WRITE_EXERCISE"/>
<!-- Add only when exporting estimated active energy. -->
<uses-permission android:name="android.permission.health.WRITE_ACTIVE_CALORIES_BURNED"/>
```

`WRITE_EXERCISE` is always required. `WRITE_ACTIVE_CALORIES_BURNED` is required
only when `energyClientRecordId` and `activeEnergyKcal` are supplied. V2
reconciliation checks the matching write grant and filters every query to
`DataOrigin(packageName)`; it does not request per-type exercise or active-
calorie read access. The example manifest declares additional read permissions
because other example screens demonstrate general health-data reads.

If you plan to read or write Activity Intensity records (the `HealthDataType.ACTIVITY_INTENSITY` type), be sure to add the corresponding Health Connect permissions introduced with that data type:

```xml
<uses-permission android:name="android.permission.health.READ_ACTIVITY_INTENSITY"/>
<uses-permission android:name="android.permission.health.WRITE_ACTIVITY_INTENSITY"/>
```

By default, Health Connect restricts read data to 30 days from when permission has been granted.

You can check and request access to historical data using the `isHealthDataHistoryAuthorized` and `requestHealthDataHistoryAuthorization` methods, respectively.

The above methods require the following permission to be declared:

```xml
<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_HISTORY"/>
```

Accessing fitness data (e.g. Steps) requires permission to access the "Activity Recognition" API. To set it add the following line to your `AndroidManifest.xml` file.

```xml
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
```

Additionally, for workouts, if the distance of a workout is requested then the location permissions below are needed.

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

Because this is labeled as a `dangerous` protection level, the permission system will not grant it automatically and it requires the user's action.
You can prompt the user for it using the [permission_handler](https://pub.dev/packages/permission_handler) plugin.
Follow the plugin setup instructions and add the following line before requesting the data:

```dart
await Permission.activityRecognition.request();
await Permission.location.request();
```

Finally, an `intent-filter` needs to be added to the `.MainActivity` activity.

```xml
<activity
  android:name=".MainActivity"
  android:exported="true"

  ....

  <!-- Intention to show Permissions screen for Health Connect API -->
  <intent-filter>
    <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
  </intent-filter>
</activity>
```

There's a `debug`, `main` and `profile` version which are chosen depending on how you start your app. In general, it's sufficient to add permission only to the `main` version.

#### Android 14

This plugin uses the new `registerForActivityResult` when requesting permissions from Health Connect.
In order for that to work, the Main app's activity should extend `FlutterFragmentActivity` instead of `FlutterActivity`.
This adjustment allows casting from `Activity` to `ComponentActivity` for accessing `registerForActivityResult`.

In your MainActivity.kt file, update the `MainActivity` class so that it extends `FlutterFragmentActivity` instead of the default `FlutterActivity`:

```kotlin
...
import io.flutter.embedding.android.FlutterFragmentActivity
...

class MainActivity: FlutterFragmentActivity() {
...
}
```

#### Android X

Replace the content of the `android/gradle.properties` file with the following lines:

```bash
org.gradle.jvmargs=-Xmx1536M
android.enableJetifier=true
android.useAndroidX=true
```

## Usage

See the example app for detailed examples of how to use the Health API.

A instance of the Health plugin is create using the `Health()` constructor and is subsequently configured calling the `configure` method. Once configured, the plugin can be used for handling permissions and getting and adding data to Apple Health or Google Health Connect.
Below is a simplified flow of how to use the plugin.

```dart
  import 'package:health_bridge/health.dart';

  // Global Health instance
  final health = Health();

  // configure the health plugin before use.
  await health.configure();


  // define the types to get
  var types = [
    HealthDataType.STEPS,
    HealthDataType.BLOOD_GLUCOSE,
  ];

  // Requesting access starts the platform flow. A true result means the
  // request completed, not that every requested permission was granted.
  bool requestCompleted = await health.requestAuthorization(types);
  // Re-query generic permissions after the prompt. Android returns exact
  // aggregate state; HealthKit generic reads remain null/unknown by design.
  bool? aggregateAuthorization = await health.hasPermissions(types);

  var now = DateTime.now();

  // fetch health data from the last 24 hours
  List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
    types: types,
    startTime: now.subtract(const Duration(days: 1)),
    endTime: now,
  );

  // request permissions to write steps and blood glucose
  types = [HealthDataType.STEPS, HealthDataType.BLOOD_GLUCOSE];
  var permissions = [
      HealthDataAccess.READ_WRITE,
      HealthDataAccess.READ_WRITE
  ];
  await health.requestAuthorization(types, permissions: permissions);

  // write steps and blood glucose — these methods return the new record's
  // String? UUID (null if the write failed), not a bool
  String? stepsUuid = await health.writeHealthData(
    value: 10, type: HealthDataType.STEPS, startTime: now, endTime: now);
  String? glucoseUuid = await health.writeHealthData(
    value: 3.1, type: HealthDataType.BLOOD_GLUCOSE, startTime: now, endTime: now);

  // you can also specify the recording method to store in the metadata (default is RecordingMethod.automatic)
  // on iOS only `RecordingMethod.automatic` and `RecordingMethod.manual` are supported
  // Android additionally supports `RecordingMethod.active` and `RecordingMethod.unknown`
  await health.writeHealthData(
    value: 10,
    type: HealthDataType.STEPS,
    startTime: now,
    endTime: now,
    recordingMethod: RecordingMethod.manual,
  );

  // get the number of steps for today
  var midnight = DateTime(now.year, now.month, now.day);
  int? steps = await health.getTotalStepsInInterval(midnight, now);
```

### Workout export V2

Version 2 replaces the legacy nullable-UUID workout write with a structured,
idempotent export contract. A logical export is one immutable envelope. Before
the first native call, generate and persist:

- a UUID for `workoutClientRecordId`;
- a different UUID for `energyClientRecordId` when exporting active energy;
- `clientRecordVersion: 0`;
- the start/end instants and each endpoint's UTC offset; and
- the activity, title, energy, provenance, and recording device.

Reuse that exact envelope when reconciling or retrying the same logical sample.
Do not regenerate IDs, timestamps, offsets, or values for a transport retry.
New IDs mean a new logical sample and can create a duplicate.

```dart
// These values come from an envelope that the app persisted before the call.
// A workout export needs these two entries; other health types can be queried
// in the same snapshot when the surrounding feature also depends on them.
final HealthAuthorizationSnapshot authorization =
    await health.getAuthorizationSnapshot(const [
  HealthDataType.WORKOUT,
  HealthDataType.ACTIVE_ENERGY_BURNED,
]);

final HealthWorkoutWriteResult result = await health.writeWorkoutData(
  workoutClientRecordId: workoutClientId,
  energyClientRecordId: energyClientId,
  clientRecordVersion: 0,
  activityType: HealthWorkoutActivityType.WALKING,
  start: frozenStart,
  end: frozenEnd,
  startZoneOffsetSeconds: frozenStartOffsetSeconds,
  endZoneOffsetSeconds: frozenEndOffsetSeconds,
  activeEnergyKcal: 120,
  title: 'Morning walk',
  recordingProvenance: HealthRecordingProvenance.activelyRecorded,
  recordingDevice: HealthRecordingDevice.phone,
);

if (result.submissionCertainty ==
    HealthSubmissionCertainty.mayHaveSubmitted) {
  final HealthWorkoutLookupResult lookup = await health.lookupWorkoutData(
    workoutClientRecordId: workoutClientId,
    energyClientRecordId: energyClientId,
    start: frozenStart,
    end: frozenEnd,
  );

  // Retry only when lookup.derivedStatus is conclusively `absent`, and then
  // reuse this same persisted envelope. `unavailable` is not `absent`.
}
```

`HealthWorkoutWriteResult.status` is one of:

- `written`, `alreadyPresent`, or `writtenWithoutEnergy` for confirmed workout
  success;
- `blockedWorkoutPermission`, `invalidInput`, or `unavailable` when native
  submission did not occur;
- `transientFailure` for a retryable failure known to be pre-submission;
- `verificationRequired` when native submission may have occurred and lookup
  is mandatory before any retry; or
- `inconsistentNativeState` when energy is present without its workout and the
  caller must surface/reconcile the inconsistency rather than submit blindly.

`HealthEnergyWriteStatus` independently reports `notExpected`, `written`,
`alreadyPresent`, `omittedPermission`, `absent`, `notSubmitted`, or
`verificationRequired`. In particular, `writtenWithoutEnergy` together with
`omittedPermission` is intentional workout-only success: the workout is
present, the energy sample is absent, and the result contains only the workout
record ID. It is not an all-or-nothing failure.

Submission certainty is exactly `notSubmitted`, `mayHaveSubmitted`, or
`submitted`. Never infer certainty from `retryable` or from a platform error
string. A `mayHaveSubmitted` result requires `lookupWorkoutData` with the same
IDs and frozen time range. Lookup reports each component as `present`,
`absent`, `unavailable`, or (for optional energy only) `notExpected`; its
derived status is `present`, `workoutOnly`, `absent`, `unavailable`, or
`inconsistent`. After a `mayHaveSubmitted` result, only derived `absent`
proves that resubmission is safe.

Permission requests have similarly explicit semantics. A `true` result from
`requestAuthorization` means the platform request completed without a plugin
error; it is not proof that the user granted every permission.
`getAuthorizationSnapshot` accepts any nonempty, duplicate-free list of
`HealthDataType` values and returns exactly that type set. Entries report read
and write state as `authorized`, `denied`, `notDetermined`,
`requestedOrUnknown`, `unavailable`, or `unsupported`. Android reports exact
read/write grants for mapped Health Connect records from one captured
permission set. HealthKit reports exact sharing/write state from
`HKHealthStore.authorizationStatus(for:)`, while mapped iOS reads remain
`requestedOrUnknown` by Apple's privacy design. Either platform reports
unmapped platform types as `unsupported`; an unavailable health service reports
every requested read and write as `unavailable`.

The automated suites validate Dart envelopes and codecs, Android Health
Connect behavior against fakes, the Swift HealthKit state machine against a
protocol fake, the Runner channel adapter, and clean platform compilation.
They cannot prove the real permission UI, persistence in the user's health
store, locked-device behavior, or another app's ingestion. Verify those on
physical iOS and Android devices before release. Exporting a workout and active
energy to Apple Health or Health Connect does **not** guarantee that
MyFitnessPal—or any other third-party app—will import it or calculate matching
calories; that remains controlled by the receiving app.

### Writing workout routes (iOS & Android)

1. Request share/read permissions for both `HealthDataType.WORKOUT` and `HealthDataType.WORKOUT_ROUTE`, and ensure location permissions are granted (iOS: Core Location permissions; Android: `ACCESS_FINE_LOCATION` or `ACCESS_COARSE_LOCATION`).
2. When the workout session starts, open a builder with `final builderId = await health.startWorkoutRoute();`.
3. Collect GPS samples using `CLLocationManager` (or an equivalent service) and periodically push ordered batches of `WorkoutRouteLocation` values via `insertWorkoutRouteData`.
4. Save the workout itself with `writeWorkoutData`. Use
   `HealthWorkoutWriteResult.workoutRecordId` only for a confirmed submitted
   result. If submission certainty is `mayHaveSubmitted`, run the mandatory
   source-scoped lookup before deciding whether the same envelope may be
   retried.
5. Call `finishWorkoutRoute(builderId: builderId, workoutUuid: workoutRecordId, metadata: {...})`
   with that confirmed workout ID to commit the route, or
   `discardWorkoutRoute(builderId)` if the session is cancelled.

> **Health Connect note:** Android only surfaces routes while your app is in the foreground, and
> other apps' routes may return a `ConsentRequired` flag. Today (Health Connect 1.1.0) the system
> does **not** expose the `ExerciseRouteRequestContract` documented by Google, so the only way to
> read third-party routes is to have the user manually grant "Always allow" for *Exercise routes*
> inside the Health Connect app (`Health Connect → App permissions → Your app → Exercise routes`).
> Also remember to declare the following permissions in your Android manifest:
> - `<uses-permission android:name="android.permission.health.READ_EXERCISE_ROUTE"/>`
> - `<uses-permission android:name="android.permission.health.WRITE_EXERCISE_ROUTE"/>`
> - `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>` (or `ACCESS_COARSE_LOCATION`)

### Health Data

A [`HealthDataPoint`](lib/src/health_data_point.dart) object contains the following data fields:

```dart
String uuid;
HealthValue value;
HealthDataType type;
HealthDataUnit unit;
DateTime dateFrom;
DateTime dateTo;
HealthPlatformType sourcePlatform;
String sourceDeviceId;
String sourceId;
String sourceName;
RecordingMethod recordingMethod;
WorkoutSummary? workoutSummary;
```

where a [`HealthValue`](lib/src/health_value_types.dart) can be any type of `AudiogramHealthValue`, `ElectrocardiogramHealthValue`, `ElectrocardiogramVoltageValue`, `NumericHealthValue`, `NutritionHealthValue`, or `WorkoutHealthValue`.

A `HealthDataPoint` object can be serialized to and from JSON using the `toJson()` and `fromJson()` methods. JSON serialization is using camel_case notation. Null values are not serialized. For example;

```json
{
  "value": {
    "__type": "NumericHealthValue",
    "numeric_value": 141.0
  },
  "type": "STEPS",
  "unit": "COUNT",
  "date_from": "2024-04-03T10:06:57.736",
  "date_to": "2024-04-03T10:12:51.724",
  "source_platform": "appleHealth",
  "source_device_id": "F74938B9-C011-4DE4-AA5E-CF41B60B96E7",
  "source_id": "com.apple.health.81AE7156-EC05-47E3-AC93-2D6F65C717DF",
  "source_name": "iPhone12.bardram.net",
  "recording_method": 2
}
```

### Fetch health data

See the example app for a showcasing of how it's done.

**Note** On iOS the device must be unlocked before health data can be requested. Otherwise an error will be thrown:

```bash
flutter: Health Plugin Error:
flutter:  PlatformException(FlutterHealth, Results are null, Optional(Error Domain=com.apple.healthkit Code=6 "Protected health data is inaccessible" UserInfo={NSLocalizedDescription=Protected health data is inaccessible}))
```

### Fetch single health data by UUID

In order to retrieve a single record, it is required to provide `String uuid` and `HealthDataType type`.

Please see example below:
```dart
HealthDataPoint? healthPoint = await health.getHealthDataByUUID(
  uuid: 'random-uuid-string',
  type: HealthDataType.STEPS,
);
```
```
I/FLUTTER_HEALTH( 9161): Success: {uuid=random-uuid-string, value=12, date_from=1742259061009, date_to=1742259092888, source_id=, source_name=com.google.android.apps.fitness, recording_method=0}
```
> Assuming that the `uuid` and `type` are coming from your database.

### Filtering by recording method

Google Health Connect and Apple HealthKit both provide ways to distinguish samples collected "automatically" and manually entered data by the user.

- Android provides an enum with 4 variations: <https://developer.android.com/reference/kotlin/androidx/health/connect/client/records/metadata/Metadata#summary>
- iOS has a boolean value: <https://developer.apple.com/documentation/healthkit/hkmetadatakeywasuserentered>

As such, when fetching data you have the option to filter the fetched data by recording method as such:

```dart
List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
  types: types,
  startTime: yesterday,
  endTime: now,
  recordingMethodsToFilter: [RecordingMethod.manual, RecordingMethod.unknown],
);
```

**Note that for this to work, the information needs to have been provided when writing the data to Health Connect or Apple Health**. For example, steps added manually through the Apple Health App will set `HKWasUserEntered` to true (corresponding to `RecordingMethod.manual`), however it seems that adding steps manually to Google Fit does not write the data with the `RecordingMethod.manual` in the metadata, instead it shows up as `RecordingMethod.unknown`. This is an open issue, and as such filtering manual entries when querying step count on Android with `getTotalStepsInInterval(includeManualEntries: false)` does not necessarily filter out manual steps.

**NOTE**: On iOS, you can only filter by `RecordingMethod.automatic` and `RecordingMethod.manual` as it is stored `HKMetadataKeyWasUserEntered` is a boolean value in the metadata.

### Filtering out duplicates

If the same data is requested multiple times and saved in the same array duplicates will occur.

A single data point can be compared to each other with the == operator, i.e.

```dart
HealthDataPoint p1 = ...;
HealthDataPoint p2 = ...;
bool same = p1 == p2;
```

If you have a list of data points, duplicates can be removed with:

```dart
List<HealthDataPoint> points = ...;
points = health.removeDuplicates(points);
```

### Android: Reading Health Data in Background
Currently health connect allows apps to read health data in the background. In order to achieve this add the following permission to your `AndroidManifest.XML`:
```XML
<!-- For reading data in background -->
<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"/>
```
Furthermore, the plugin now exposes three new functions to help you check and request access to read data in the background:
1. `isHealthDataInBackgroundAvailable()`: Checks if the Health Data in Background feature is available
2. `isHealthDataInBackgroundAuthorized()`: Checks the current status of the Health Data in Background permission
3. `requestHealthDataInBackgroundAuthorization()`: Requests the Health Data in Background permission.

## Data Types

The plugin supports the following [`HealthDataType`](lib/src/heath_data_types.dart).

| **Data Type**                | **Unit**                | **Apple Health** | **Google Health Connect** | **Comments**                                                                                                                       |
| ---------------------------- | ----------------------- | ---------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| ACTIVE_ENERGY_BURNED         | CALORIES                | yes              | yes                       |                                                                                                                                    |
| ATRIAL_FIBRILLATION_BURDEN   | PERCENTAGE              | yes              |                           |                                                                                                                                    |
| BASAL_ENERGY_BURNED          | CALORIES                | yes              | yes                       |                                                                                                                                    |
| BLOOD_GLUCOSE                | MILLIGRAM_PER_DECILITER | yes              | yes                       |                                                                                                                                    |
| BLOOD_OXYGEN                 | PERCENTAGE              | yes              | yes                       |                                                                                                                                    |
| BLOOD_PRESSURE_DIASTOLIC     | MILLIMETER_OF_MERCURY   | yes              | yes                       |                                                                                                                                    |
| BLOOD_PRESSURE_SYSTOLIC      | MILLIMETER_OF_MERCURY   | yes              | yes                       |                                                                                                                                    |
| BODY_FAT_PERCENTAGE          | PERCENTAGE              | yes              | yes                       |                                                                                                                                    |
| BODY_MASS_INDEX              | NO_UNIT                 | yes              | yes                       |                                                                                                                                    |
| BODY_TEMPERATURE             | DEGREE_CELSIUS          | yes              | yes                       |                                                                                                                                    |
| BODY_WATER_MASS              | KILOGRAMS               |                  | yes                       |                                                                                                                                    |
| ELECTRODERMAL_ACTIVITY       | SIEMENS                 | yes              |                           |                                                                                                                                    |
| HEART_RATE                   | BEATS_PER_MINUTE        | yes              | yes                       |                                                                                                                                    |
| HEIGHT                       | METERS                  | yes              | yes                       |                                                                                                                                    |
| RESTING_HEART_RATE           | BEATS_PER_MINUTE        | yes              | yes                       |                                                                                                                                    |
| RESPIRATORY_RATE             | RESPIRATIONS_PER_MINUTE | yes              | yes                       |                                                                                                                                    |
| PERIPHERAL_PERFUSION_INDEX   | PERCENTAGE              | yes              |                           |                                                                                                                                    |
| STEPS                        | COUNT                   | yes              | yes                       |                                                                                                                                    |
| WAIST_CIRCUMFERENCE          | METERS                  | yes              |                           |                                                                                                                                    |
| WALKING_HEART_RATE           | BEATS_PER_MINUTE        | yes              |                           |                                                                                                                                    |
| WEIGHT                       | KILOGRAMS               | yes              | yes                       |                                                                                                                                    |
| DISTANCE_WALKING_RUNNING     | METERS                  | yes              |                           |                                                                                                                                    |
| FLIGHTS_CLIMBED              | COUNT                   | yes              | yes                       |                                                                                                                                    |
| DISTANCE_DELTA               | METERS                  |                  | yes                       |                                                                                                                                    |
| MINDFULNESS                  | MINUTES                 | yes              |                           |                                                                                                                                    |
| SLEEP_ASLEEP                 | MINUTES                 | yes              | yes                       | on iOS, this refers to asleepUnspecified, and on Android this refers to STAGE_TYPE_SLEEPING (asleep but specific stage is unknown) |
| SLEEP_AWAKE                  | MINUTES                 | yes              | yes                       |                                                                                                                                    |
| SLEEP_AWAKE_IN_BED           | MINUTES                 |                  | yes                       |                                                                                                                                    |
| SLEEP_DEEP                   | MINUTES                 | yes              | yes                       |                                                                                                                                    |
| SLEEP_IN_BED                 | MINUTES                 | yes              |                           |                                                                                                                                    |
| SLEEP_LIGHT                  | MINUTES                 | yes              | yes                       | on iOS, this refers to asleepCore                                                                                                  |
| SLEEP_OUT_OF_BED             | MINUTES                 |                  | yes                       |                                                                                                                                    |
| SLEEP_REM                    | MINUTES                 | yes              | yes                       |                                                                                                                                    |
| SLEEP_UNKNOWN                | MINUTES                 |                  | yes                       |                                                                                                                                    |
| SLEEP_SESSION                | MINUTES                 |                  | yes                       |                                                                                                                                    |
| WATER                        | LITER                   | yes              | yes                       |                                                                                                                                    |
| EXERCISE_TIME                | MINUTES                 | yes              |                           |                                                                                                                                    |
| WORKOUT                      | NO_UNIT                 | yes              | yes                       | See table below                                                                                                                    |
| WORKOUT_ROUTE                | NO_UNIT                 | yes              | yes                       | iOS 11+ and Android (as Exercise Route); use the workout route builder APIs described in the [Writing workout routes](#writing-workout-routes-ios--android) section above. |
| HIGH_HEART_RATE_EVENT        | NO_UNIT                 | yes              |                           | Requires Apple Watch to write the data                                                                                             |
| LOW_HEART_RATE_EVENT         | NO_UNIT                 | yes              |                           | Requires Apple Watch to write the data                                                                                             |
| IRREGULAR_HEART_RATE_EVENT   | NO_UNIT                 | yes              |                           | Requires Apple Watch to write the data                                                                                             |
| HEART_RATE_VARIABILITY_RMSSD | MILLISECONDS            |                  | yes                       |                                                                                                                                    |
| HEART_RATE_VARIABILITY_SDNN  | MILLISECONDS            | yes              |                           | Requires Apple Watch to write the data                                                                                             |
| HEADACHE_NOT_PRESENT         | MINUTES                 | yes              |                           |                                                                                                                                    |
| HEADACHE_MILD                | MINUTES                 | yes              |                           |                                                                                                                                    |
| HEADACHE_MODERATE            | MINUTES                 | yes              |                           |                                                                                                                                    |
| HEADACHE_SEVERE              | MINUTES                 | yes              |                           |                                                                                                                                    |
| HEADACHE_UNSPECIFIED         | MINUTES                 | yes              |                           |                                                                                                                                    |
| AUDIOGRAM                    | DECIBEL_HEARING_LEVEL   | yes              |                           |                                                                                                                                    |
| ELECTROCARDIOGRAM            | VOLT                    | yes              |                           | Requires Apple Watch to write the data                                                                                             |
| NUTRITION                    | NO_UNIT                 | yes              | yes                       |                                                                                                                                    |
| INSULIN_DELIVERY             | INTERNATIONAL_UNIT      | yes              |                           |                                                                                                                                    |
| MENSTRUATION_FLOW            | NO_UNIT                 | yes              | yes                       |                                                                                                                                    |
| WATER_TEMPERATURE            | DEGREE_CELSIUS          | yes              |                           | Related to/Requires Apple Watch Ultra's Underwater Diving Workout                                                                  |
| SLEEP_WRIST_TEMPERATURE      | DEGREE_CELSIUS          | yes              |                           | READ Only - `appleSleepingWristTemperature`                                                                                        |
| SKIN_TEMPERATURE             | DEGREE_CELSIUS          |                  | yes                       | Must check health connect for availability                                                                                         |
| UNDERWATER_DEPTH             | METER                   | yes              |                           | Related to/Requires Apple Watch Ultra's Underwater Diving Workout                                                                  |
| UV_INDEX                     | COUNT                   | yes              |                           |                                                                                                                                    |
| LEAN_BODY_MASS               | KILOGRAMS               | yes              | yes                       |                                                                                                                                    |
| WALKING_SPEED                | METER_PER_SECOND        | yes              | (yes)                     | On Android this will be recorded as `SPEED` with similar unit                                                                      |
| APPLE_MOVE_TIME              | SECOND                  | yes              |                           | READ Only                                                                                                                          |
| APPLE_STAND_HOUR             | HOUR                    | yes              |                           | READ Only                                                                                                                          |

## Workout Types

The plugin accepts the following [`HealthWorkoutActivityType`](lib/src/heath_data_types.dart) values. A `yes` means the Dart platform validator accepts that exact enum value; blank means it rejects it.

| **Workout Type** | **Apple Health** | **Google Health Connect** | **Comments** |
| --- | --- | --- | --- |
| AMERICAN_FOOTBALL | yes | yes |  |
| ARCHERY | yes |  |  |
| AUSTRALIAN_FOOTBALL | yes | yes |  |
| BADMINTON | yes | yes |  |
| BASEBALL | yes | yes |  |
| BASKETBALL | yes | yes |  |
| BIKING | yes | yes |  |
| BOXING | yes | yes |  |
| CARDIO_DANCE | yes | yes |  |
| CRICKET | yes | yes |  |
| CROSS_COUNTRY_SKIING | yes | yes |  |
| CURLING | yes |  |  |
| DOWNHILL_SKIING | yes | yes |  |
| ELLIPTICAL | yes | yes |  |
| FENCING | yes | yes |  |
| GOLF | yes | yes |  |
| GYMNASTICS | yes | yes |  |
| HANDBALL | yes | yes |  |
| HIGH_INTENSITY_INTERVAL_TRAINING | yes | yes |  |
| HIKING | yes | yes |  |
| HOCKEY | yes | yes |  |
| JUMP_ROPE | yes |  |  |
| KICKBOXING | yes |  |  |
| MARTIAL_ARTS | yes | yes |  |
| PILATES | yes | yes |  |
| RACQUETBALL | yes | yes |  |
| ROWING | yes | yes |  |
| RUGBY | yes | yes |  |
| RUNNING | yes | yes |  |
| SAILING | yes | yes |  |
| SKATING | yes | yes |  |
| SNOWBOARDING | yes | yes |  |
| SOCCER | yes | yes |  |
| SOFTBALL | yes | yes |  |
| SQUASH | yes | yes |  |
| STAIR_CLIMBING | yes | yes |  |
| SWIMMING | yes |  |  |
| TABLE_TENNIS | yes | yes |  |
| TENNIS | yes | yes |  |
| VOLLEYBALL | yes | yes |  |
| WALKING | yes | yes |  |
| WATER_POLO | yes | yes |  |
| YOGA | yes | yes |  |
| BARRE | yes |  |  |
| BOWLING | yes |  |  |
| CLIMBING | yes |  |  |
| COOLDOWN | yes |  |  |
| CORE_TRAINING | yes |  |  |
| CROSS_TRAINING | yes |  |  |
| DISC_SPORTS | yes |  |  |
| EQUESTRIAN_SPORTS | yes |  |  |
| FISHING | yes |  |  |
| FITNESS_GAMING | yes |  |  |
| FLEXIBILITY | yes |  |  |
| FUNCTIONAL_STRENGTH_TRAINING | yes |  |  |
| HAND_CYCLING | yes |  |  |
| HUNTING | yes |  |  |
| LACROSSE | yes |  |  |
| MIND_AND_BODY | yes |  |  |
| MIXED_CARDIO | yes |  |  |
| PADDLE_SPORTS | yes |  |  |
| PICKLEBALL | yes |  |  |
| PLAY | yes |  |  |
| PREPARATION_AND_RECOVERY | yes |  |  |
| SNOW_SPORTS | yes |  |  |
| SOCIAL_DANCE | yes | yes |  |
| STAIRS | yes |  |  |
| STEP_TRAINING | yes |  |  |
| SURFING | yes | yes |  |
| TAI_CHI | yes |  |  |
| TRACK_AND_FIELD | yes |  |  |
| TRADITIONAL_STRENGTH_TRAINING | yes |  |  |
| WATER_FITNESS | yes |  |  |
| WATER_SPORTS | yes |  |  |
| WHEELCHAIR_RUN_PACE | yes | yes |  |
| WHEELCHAIR_WALK_PACE | yes | yes |  |
| WRESTLING | yes |  |  |
| UNDERWATER_DIVING | yes |  | Requires iOS 17+ |
| BIKING_STATIONARY |  | yes |  |
| CALISTHENICS |  | yes |  |
| DANCING |  | yes |  |
| FRISBEE_DISC |  | yes |  |
| GUIDED_BREATHING |  | yes |  |
| ICE_SKATING |  | yes |  |
| PARAGLIDING |  | yes |  |
| ROCK_CLIMBING |  | yes |  |
| ROWING_MACHINE |  | yes |  |
| RUNNING_TREADMILL |  | yes |  |
| SCUBA_DIVING |  | yes |  |
| SKIING |  | yes |  |
| SNOWSHOEING |  | yes |  |
| STAIR_CLIMBING_MACHINE |  | yes |  |
| STRENGTH_TRAINING |  | yes |  |
| SWIMMING_OPEN_WATER | yes | yes |  |
| SWIMMING_POOL | yes | yes |  |
| WALKING_TREADMILL |  | yes |  |
| WEIGHTLIFTING |  | yes |  |
| WHEELCHAIR |  | yes |  |
| OTHER | yes | yes |  |

## License

`health_bridge` is a fork of the [`health`](https://github.com/carp-dk/carp-health-flutter) plugin, copyright (c) the [Technical University of Denmark (DTU)](https://www.dtu.dk) and part of the [Copenhagen Research Platform](https://carp.cachet.dk/). Fork modifications are copyright (c) Michael Ryan.
This software is available 'as-is' under a [MIT license](LICENSE).
