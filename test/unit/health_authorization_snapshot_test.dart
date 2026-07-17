import 'package:flutter_test/flutter_test.dart';
import 'package:health_bridge/health.dart';

import '../support/health_test_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HealthTestContext ctx;

  setUp(() async {
    ctx = HealthTestContext();
    // The snapshot API is platform-neutral and does not require device ID
    // configuration. Skipping configure also keeps its codec contract testable
    // in browsers, where dart:io Platform is unavailable.
    await ctx.setUp(configureHealth: false);
  });

  tearDown(() async {
    await ctx.tearDown();
  });

  group('getAuthorizationSnapshot', () {
    test('forwards mixed workout, scalar, and sleep types and decodes iOS unknown reads', () async {
      ctx.channel.when('getAuthorizationSnapshot', {
        'available': true,
        'types': [
          {'type': 'WORKOUT', 'read': 'requestedOrUnknown', 'write': 'denied'},
          {'type': 'ACTIVE_ENERGY_BURNED', 'read': 'requestedOrUnknown', 'write': 'authorized'},
          {'type': 'WEIGHT', 'read': 'requestedOrUnknown', 'write': 'authorized'},
          {'type': 'BODY_FAT_PERCENTAGE', 'read': 'requestedOrUnknown', 'write': 'notDetermined'},
          {'type': 'SLEEP_ASLEEP', 'read': 'requestedOrUnknown', 'write': 'denied'},
        ],
      });

      final snapshot = await ctx.health.getAuthorizationSnapshot([
        HealthDataType.WORKOUT,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.WEIGHT,
        HealthDataType.BODY_FAT_PERCENTAGE,
        HealthDataType.SLEEP_ASLEEP,
      ]);

      expect(snapshot.available, isTrue);
      expect(
        snapshot.forType(HealthDataType.WORKOUT),
        const HealthTypeAuthorization(
          type: HealthDataType.WORKOUT,
          read: HealthAuthorizationState.requestedOrUnknown,
          write: HealthAuthorizationState.denied,
        ),
      );
      expect(snapshot.forType(HealthDataType.ACTIVE_ENERGY_BURNED).write, HealthAuthorizationState.authorized);
      expect(snapshot.forType(HealthDataType.WEIGHT).write, HealthAuthorizationState.authorized);
      expect(snapshot.forType(HealthDataType.BODY_FAT_PERCENTAGE).write, HealthAuthorizationState.notDetermined);
      expect(snapshot.forType(HealthDataType.SLEEP_ASLEEP).read, HealthAuthorizationState.requestedOrUnknown);
      expect(ctx.channel.calls.map((call) => call.method), ['getAuthorizationSnapshot']);
      expect(Map<String, Object?>.from(ctx.channel.lastCallFor('getAuthorizationSnapshot')!.arguments as Map), {
        'types': ['WORKOUT', 'ACTIVE_ENERGY_BURNED', 'WEIGHT', 'BODY_FAT_PERCENTAGE', 'SLEEP_ASLEEP'],
      });
    });

    test('decodes Android exact grants and not-determined writes', () async {
      ctx.channel.when('getAuthorizationSnapshot', {
        'available': true,
        'types': [
          {'type': 'WORKOUT', 'read': 'authorized', 'write': 'authorized'},
          {'type': 'ACTIVE_ENERGY_BURNED', 'read': 'denied', 'write': 'notDetermined'},
        ],
      });

      final snapshot = await ctx.health.getAuthorizationSnapshot([
        HealthDataType.WORKOUT,
        HealthDataType.ACTIVE_ENERGY_BURNED,
      ]);

      expect(snapshot.forType(HealthDataType.WORKOUT).read, HealthAuthorizationState.authorized);
      expect(snapshot.forType(HealthDataType.ACTIVE_ENERGY_BURNED).read, HealthAuthorizationState.denied);
      expect(snapshot.forType(HealthDataType.ACTIVE_ENERGY_BURNED).write, HealthAuthorizationState.notDetermined);
    });

    test('decodes an unavailable service with every component unavailable', () async {
      ctx.channel.when('getAuthorizationSnapshot', {
        'available': false,
        'platformCode': 'sdk_unavailable',
        'types': [
          {'type': 'WORKOUT', 'read': 'unavailable', 'write': 'unavailable'},
        ],
      });

      final snapshot = await ctx.health.getAuthorizationSnapshot([HealthDataType.WORKOUT]);

      expect(snapshot.available, isFalse);
      expect(snapshot.platformCode, 'sdk_unavailable');
      expect(snapshot.forType(HealthDataType.WORKOUT).write, HealthAuthorizationState.unavailable);
    });

    test('decodes unsupported per-type states while service is available', () async {
      ctx.channel.when('getAuthorizationSnapshot', {
        'available': true,
        'types': [
          {'type': 'WORKOUT', 'read': 'unsupported', 'write': 'unsupported'},
        ],
      });

      final snapshot = await ctx.health.getAuthorizationSnapshot([HealthDataType.WORKOUT]);

      expect(snapshot.forType(HealthDataType.WORKOUT).read, HealthAuthorizationState.unsupported);
    });

    test('rejects an empty request before invoking the channel', () async {
      await expectLater(ctx.health.getAuthorizationSnapshot(const []), throwsArgumentError);
      expect(ctx.channel.calls, isEmpty);
    });

    test('rejects duplicate requested types before invoking the channel', () async {
      await expectLater(
        ctx.health.getAuthorizationSnapshot(const [HealthDataType.WORKOUT, HealthDataType.WORKOUT]),
        throwsArgumentError,
      );
      expect(ctx.channel.calls, isEmpty);
    });

    test('forwards a known Dart type even when the platform reports it unsupported', () async {
      ctx.channel.when('getAuthorizationSnapshot', {
        'available': true,
        'types': [
          {'type': 'STEPS', 'read': 'unsupported', 'write': 'unsupported'},
        ],
      });

      final snapshot = await ctx.health.getAuthorizationSnapshot(const [HealthDataType.STEPS]);

      expect(snapshot.forType(HealthDataType.STEPS).read, HealthAuthorizationState.unsupported);
      expect(Map<String, Object?>.from(ctx.channel.lastCallFor('getAuthorizationSnapshot')!.arguments as Map), {
        'types': ['STEPS'],
      });
    });

    test('accepts every HealthDataType in one exact request', () async {
      final requested = HealthDataType.values;
      ctx.channel.when('getAuthorizationSnapshot', {
        'available': true,
        'types': [
          for (final type in requested) {'type': type.name, 'read': 'unsupported', 'write': 'unsupported'},
        ],
      });

      final snapshot = await ctx.health.getAuthorizationSnapshot(requested);

      expect(snapshot.types.map((entry) => entry.type), requested);
      expect(Map<String, Object?>.from(ctx.channel.lastCallFor('getAuthorizationSnapshot')!.arguments as Map), {
        'types': requested.map((type) => type.name).toList(growable: false),
      });
    });
  });

  group('HealthAuthorizationSnapshot decoding', () {
    test('accepts native entries in a different order from the requested set', () {
      final snapshot = HealthAuthorizationSnapshot.fromMethodChannel(
        {
          'available': true,
          'types': [
            _authorizationEntry(HealthDataType.WORKOUT),
            _authorizationEntry(HealthDataType.ACTIVE_ENERGY_BURNED),
          ],
        },
        {HealthDataType.WORKOUT, HealthDataType.ACTIVE_ENERGY_BURNED},
      );

      expect(snapshot.types.map((entry) => entry.type), [HealthDataType.ACTIVE_ENERGY_BURNED, HealthDataType.WORKOUT]);
    });

    test('rejects an empty decoded snapshot even for an empty requested set', () {
      expect(
        () => HealthAuthorizationSnapshot.fromMethodChannel({
          'available': false,
          'types': const <Object?>[],
        }, <HealthDataType>{}),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate native entries', () {
      expect(
        () => HealthAuthorizationSnapshot.fromMethodChannel(
          {
            'available': true,
            'types': [_authorizationEntry(HealthDataType.WORKOUT), _authorizationEntry(HealthDataType.WORKOUT)],
          },
          {HealthDataType.WORKOUT},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a missing requested entry', () {
      expect(
        () => HealthAuthorizationSnapshot.fromMethodChannel(
          {
            'available': true,
            'types': [_authorizationEntry(HealthDataType.WORKOUT)],
          },
          {HealthDataType.WORKOUT, HealthDataType.ACTIVE_ENERGY_BURNED},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an extra unrequested entry', () {
      expect(
        () => HealthAuthorizationSnapshot.fromMethodChannel(
          {
            'available': true,
            'types': [
              _authorizationEntry(HealthDataType.WORKOUT),
              _authorizationEntry(HealthDataType.ACTIVE_ENERGY_BURNED),
            ],
          },
          {HealthDataType.WORKOUT},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an unknown authorization state', () {
      expect(
        () => HealthAuthorizationSnapshot.fromMethodChannel(
          {
            'available': true,
            'types': [
              {'type': 'WORKOUT', 'read': 'grantedForever', 'write': 'authorized'},
            ],
          },
          {HealthDataType.WORKOUT},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an unknown native health data type', () {
      expect(
        () => HealthAuthorizationSnapshot.fromMethodChannel(
          {
            'available': true,
            'types': [
              {'type': 'FUTURE_UNKNOWN_TYPE', 'read': 'unsupported', 'write': 'unsupported'},
            ],
          },
          {HealthDataType.WORKOUT},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a non-list types payload', () {
      expect(
        () => HealthAuthorizationSnapshot.fromMethodChannel(
          {'available': true, 'types': 'WORKOUT'},
          {HealthDataType.WORKOUT},
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HealthAuthorizationSnapshot construction', () {
    const workoutAuthorized = HealthTypeAuthorization(
      type: HealthDataType.WORKOUT,
      read: HealthAuthorizationState.authorized,
      write: HealthAuthorizationState.authorized,
    );
    const energyDenied = HealthTypeAuthorization(
      type: HealthDataType.ACTIVE_ENERGY_BURNED,
      read: HealthAuthorizationState.requestedOrUnknown,
      write: HealthAuthorizationState.denied,
    );
    const workoutUnavailable = HealthTypeAuthorization(
      type: HealthDataType.WORKOUT,
      read: HealthAuthorizationState.unavailable,
      write: HealthAuthorizationState.unavailable,
    );

    test('defensively copies and exposes an unmodifiable type list', () {
      final source = <HealthTypeAuthorization>[workoutAuthorized];

      final snapshot = HealthAuthorizationSnapshot(available: true, types: source);
      source.add(energyDenied);

      expect(snapshot.types, [workoutAuthorized]);
      expect(() => snapshot.types.add(energyDenied), throwsUnsupportedError);
    });

    test('rejects duplicate type entries', () {
      expect(
        () => HealthAuthorizationSnapshot(available: true, types: const [workoutAuthorized, workoutAuthorized]),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts scalar and sleep type entries', () {
      final snapshot = HealthAuthorizationSnapshot(
        available: true,
        types: const [
          HealthTypeAuthorization(
            type: HealthDataType.WEIGHT,
            read: HealthAuthorizationState.requestedOrUnknown,
            write: HealthAuthorizationState.authorized,
          ),
          HealthTypeAuthorization(
            type: HealthDataType.SLEEP_ASLEEP,
            read: HealthAuthorizationState.requestedOrUnknown,
            write: HealthAuthorizationState.denied,
          ),
        ],
      );

      expect(snapshot.types.map((entry) => entry.type), [HealthDataType.WEIGHT, HealthDataType.SLEEP_ASLEEP]);
    });

    test('rejects an empty direct snapshot even when unavailable', () {
      expect(() => HealthAuthorizationSnapshot(available: false, types: const []), throwsA(isA<FormatException>()));
    });

    test('rejects a blank platform code', () {
      expect(
        () => HealthAuthorizationSnapshot(available: true, types: const [workoutAuthorized], platformCode: ' '),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires every state unavailable when service is unavailable', () {
      expect(
        () => HealthAuthorizationSnapshot(available: false, types: const [workoutAuthorized]),
        throwsA(isA<FormatException>()),
      );
    });

    test('forbids unavailable states when service is available', () {
      expect(
        () => HealthAuthorizationSnapshot(available: true, types: const [workoutUnavailable]),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts unavailable states only with an unavailable service', () {
      final snapshot = HealthAuthorizationSnapshot(available: false, types: const [workoutUnavailable]);

      expect(snapshot.available, isFalse);
    });

    test('uses structural equality and hash codes for type entries', () {
      const equalEntry = HealthTypeAuthorization(
        type: HealthDataType.WORKOUT,
        read: HealthAuthorizationState.authorized,
        write: HealthAuthorizationState.authorized,
      );

      expect(workoutAuthorized, equalEntry);
      expect(workoutAuthorized.hashCode, equalEntry.hashCode);
      expect(workoutAuthorized, isNot(energyDenied));
    });

    test('uses structural equality and hash codes for snapshots', () {
      final first = HealthAuthorizationSnapshot(
        available: true,
        types: const [workoutAuthorized, energyDenied],
        platformCode: 'ok',
      );
      final second = HealthAuthorizationSnapshot(
        available: true,
        types: const [energyDenied, workoutAuthorized],
        platformCode: 'ok',
      );

      expect(first.types.map((entry) => entry.type), [HealthDataType.ACTIVE_ENERGY_BURNED, HealthDataType.WORKOUT]);
      expect(second.types.map((entry) => entry.type), [HealthDataType.ACTIVE_ENERGY_BURNED, HealthDataType.WORKOUT]);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(HealthAuthorizationSnapshot(available: true, types: const [workoutAuthorized], platformCode: 'ok')),
      );
    });
  });
}

Map<String, Object?> _authorizationEntry(HealthDataType type) => {
  'type': type.name,
  'read': 'authorized',
  'write': 'authorized',
};
