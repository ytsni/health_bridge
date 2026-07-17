# Health Bridge testing

This repository tests the workout-export contract at four automated layers and
reserves store-level behavior for real-device verification.

## Dart API and example tests

From the package root:

```bash
flutter test
flutter test test/unit/health_workout_export_test.dart \
  test/unit/health_authorization_snapshot_test.dart

cd example
flutter test
```

These suites cover argument validation, method-channel payloads, strict result
decoding, legal status combinations, generic per-type authorization
snapshots, and the example's frozen two-ID export envelope. There is no
`example/integration_test` suite in this repository.

## Android native tests

```bash
cd example/android
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew :health_bridge:testDebugUnitTest
```

The Android suite uses fake Health Connect clients and permission state. It
checks exact write-permission preflight, app-origin-filtered lookup, pagination,
idempotency, partial energy permission, authorization snapshots, and exception
classification without touching a user's Health Connect store.

## Swift workout core tests

```bash
cd ios/health_bridge/HealthBridgeWorkoutCore
swift test
```

The Swift package exercises the HealthKit workout state machine through a
protocol fake, including save/lookup ordering, ambiguous submission,
workout-only success, locked-store behavior, and exact sharing authorization.

## iOS Runner channel-adapter tests

Build the current Flutter iOS wrapper before running Xcode tests. Use a full
simulator build rather than `--config-only`: Flutter updates the generated
Swift package's deployment target during the full build, which is required by
this plugin's iOS 14 package floor.

```bash
cd example
flutter build ios --simulator --no-codesign

cd ios
xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:RunnerTests/HealthWorkoutChannelHandlerTests
```

Substitute an installed simulator name when needed. These tests validate the
Runner method-channel adapter and strict native result maps. A simulator build
does not write to a real HealthKit store.

## Real-device release matrix

Automated fakes and simulators cannot establish that the platform permission UI
appears correctly, that records persist in the user's HealthKit/Health Connect
store, that iOS locked-device behavior matches production, or that another app
imports the records. Before release, exercise the permission-denied,
workout-only, full workout-plus-energy, retry/reconciliation, duplicate, and
locked-device paths on physical iOS and Android devices.

MyFitnessPal and other receiving apps control their own import and calorie
logic. Passing every Health Bridge suite and observing records in Apple Health
or Health Connect does not guarantee third-party ingestion or matching calorie
totals.

## Adding a Dart method-channel test

1. Copy a template from `test/templates` into `test/unit` and rename it to
   `*_test.dart`.
2. Create a `HealthTestContext`.
3. Stub native responses with `ctx.channel.when(...)` or a custom responder.
4. Call the API under test.
5. Assert on `ctx.channel.lastCallFor(...)` and the decoded typed result.

Keep platform-gated Dart tests focused on validation, arguments, and parsing.
Native semantics belong in the Android fake-client or Swift protocol-fake
suites. Workout-export coverage must include `writeWorkoutData`,
`lookupWorkoutData`, and `getAuthorizationSnapshot` for WORKOUT plus optional
ACTIVE_ENERGY_BURNED because ambiguous submission and per-component permission
state are part of the public contract. Generic snapshot coverage separately
proves scalar, sleep, unsupported, unavailable, revocation, and mixed requests.
