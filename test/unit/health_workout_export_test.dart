import 'package:flutter_test/flutter_test.dart';
import 'package:health_bridge/health.dart';

import '../support/health_test_context.dart';

const _workoutClientId = '018f8d7e-1111-7111-8111-111111111111';
const _energyClientId = '018f8d7e-2222-7222-8222-222222222222';
final _workoutStart = DateTime.parse('2026-03-08T06:55:00Z');
final _workoutEnd = DateTime.parse('2026-03-08T07:25:00Z');

const _androidSupportedWorkoutActivities = <HealthWorkoutActivityType>{
  HealthWorkoutActivityType.AMERICAN_FOOTBALL,
  HealthWorkoutActivityType.AUSTRALIAN_FOOTBALL,
  HealthWorkoutActivityType.BADMINTON,
  HealthWorkoutActivityType.BASEBALL,
  HealthWorkoutActivityType.BASKETBALL,
  HealthWorkoutActivityType.BIKING,
  HealthWorkoutActivityType.BIKING_STATIONARY,
  HealthWorkoutActivityType.BOXING,
  HealthWorkoutActivityType.CALISTHENICS,
  HealthWorkoutActivityType.CARDIO_DANCE,
  HealthWorkoutActivityType.CRICKET,
  HealthWorkoutActivityType.CROSS_COUNTRY_SKIING,
  HealthWorkoutActivityType.DANCING,
  HealthWorkoutActivityType.DOWNHILL_SKIING,
  HealthWorkoutActivityType.ELLIPTICAL,
  HealthWorkoutActivityType.FENCING,
  HealthWorkoutActivityType.FRISBEE_DISC,
  HealthWorkoutActivityType.GOLF,
  HealthWorkoutActivityType.GUIDED_BREATHING,
  HealthWorkoutActivityType.GYMNASTICS,
  HealthWorkoutActivityType.HANDBALL,
  HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING,
  HealthWorkoutActivityType.HIKING,
  HealthWorkoutActivityType.HOCKEY,
  HealthWorkoutActivityType.ICE_SKATING,
  HealthWorkoutActivityType.MARTIAL_ARTS,
  HealthWorkoutActivityType.OTHER,
  HealthWorkoutActivityType.PARAGLIDING,
  HealthWorkoutActivityType.PILATES,
  HealthWorkoutActivityType.RACQUETBALL,
  HealthWorkoutActivityType.ROCK_CLIMBING,
  HealthWorkoutActivityType.ROWING,
  HealthWorkoutActivityType.ROWING_MACHINE,
  HealthWorkoutActivityType.RUGBY,
  HealthWorkoutActivityType.RUNNING,
  HealthWorkoutActivityType.RUNNING_TREADMILL,
  HealthWorkoutActivityType.SAILING,
  HealthWorkoutActivityType.SCUBA_DIVING,
  HealthWorkoutActivityType.SKATING,
  HealthWorkoutActivityType.SKIING,
  HealthWorkoutActivityType.SNOWBOARDING,
  HealthWorkoutActivityType.SNOWSHOEING,
  HealthWorkoutActivityType.SOCCER,
  HealthWorkoutActivityType.SOCIAL_DANCE,
  HealthWorkoutActivityType.SOFTBALL,
  HealthWorkoutActivityType.SQUASH,
  HealthWorkoutActivityType.STAIR_CLIMBING,
  HealthWorkoutActivityType.STAIR_CLIMBING_MACHINE,
  HealthWorkoutActivityType.STRENGTH_TRAINING,
  HealthWorkoutActivityType.SURFING,
  HealthWorkoutActivityType.SWIMMING_OPEN_WATER,
  HealthWorkoutActivityType.SWIMMING_POOL,
  HealthWorkoutActivityType.TABLE_TENNIS,
  HealthWorkoutActivityType.TENNIS,
  HealthWorkoutActivityType.VOLLEYBALL,
  HealthWorkoutActivityType.WALKING,
  HealthWorkoutActivityType.WALKING_TREADMILL,
  HealthWorkoutActivityType.WATER_POLO,
  HealthWorkoutActivityType.WEIGHTLIFTING,
  HealthWorkoutActivityType.WHEELCHAIR,
  HealthWorkoutActivityType.WHEELCHAIR_RUN_PACE,
  HealthWorkoutActivityType.WHEELCHAIR_WALK_PACE,
  HealthWorkoutActivityType.YOGA,
};

const _allowedWriteStatusPairs = <(HealthWorkoutWriteStatus, HealthEnergyWriteStatus)>{
  (HealthWorkoutWriteStatus.written, HealthEnergyWriteStatus.written),
  (HealthWorkoutWriteStatus.written, HealthEnergyWriteStatus.notExpected),
  (HealthWorkoutWriteStatus.alreadyPresent, HealthEnergyWriteStatus.alreadyPresent),
  (HealthWorkoutWriteStatus.alreadyPresent, HealthEnergyWriteStatus.absent),
  (HealthWorkoutWriteStatus.alreadyPresent, HealthEnergyWriteStatus.notExpected),
  (HealthWorkoutWriteStatus.writtenWithoutEnergy, HealthEnergyWriteStatus.omittedPermission),
  (HealthWorkoutWriteStatus.blockedWorkoutPermission, HealthEnergyWriteStatus.notSubmitted),
  (HealthWorkoutWriteStatus.blockedWorkoutPermission, HealthEnergyWriteStatus.notExpected),
  (HealthWorkoutWriteStatus.verificationRequired, HealthEnergyWriteStatus.verificationRequired),
  (HealthWorkoutWriteStatus.verificationRequired, HealthEnergyWriteStatus.omittedPermission),
  (HealthWorkoutWriteStatus.verificationRequired, HealthEnergyWriteStatus.notExpected),
  (HealthWorkoutWriteStatus.inconsistentNativeState, HealthEnergyWriteStatus.alreadyPresent),
  (HealthWorkoutWriteStatus.transientFailure, HealthEnergyWriteStatus.notSubmitted),
  (HealthWorkoutWriteStatus.transientFailure, HealthEnergyWriteStatus.notExpected),
  (HealthWorkoutWriteStatus.invalidInput, HealthEnergyWriteStatus.notSubmitted),
  (HealthWorkoutWriteStatus.invalidInput, HealthEnergyWriteStatus.notExpected),
  (HealthWorkoutWriteStatus.unavailable, HealthEnergyWriteStatus.notSubmitted),
  (HealthWorkoutWriteStatus.unavailable, HealthEnergyWriteStatus.notExpected),
};

void main() {
  group('HealthWorkoutWriteResult codec', () {
    test('decodes a full submitted write', () {
      final result = HealthWorkoutWriteResult.fromMethodChannel({
        'status': 'written',
        'workoutRecordId': 'workout-native-id',
        'energyRecordId': 'energy-native-id',
        'energyStatus': 'written',
        'retryable': false,
        'submissionCertainty': 'submitted',
      });

      expect(result.status, HealthWorkoutWriteStatus.written);
      expect(result.workoutRecordId, 'workout-native-id');
      expect(result.energyRecordId, 'energy-native-id');
    });

    test('rejects the old boolean response', () {
      expect(() => HealthWorkoutWriteResult.fromMethodChannel(true), throwsA(isA<FormatException>()));
    });

    test('rejects verification without mayHaveSubmitted certainty', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel({
          'status': 'verificationRequired',
          'energyStatus': 'verificationRequired',
          'retryable': true,
          'submissionCertainty': 'notSubmitted',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    final validCases =
        <
          ({
            String name,
            Map<String, Object?> payload,
            HealthWorkoutWriteStatus expectedStatus,
            HealthEnergyWriteStatus expectedEnergyStatus,
            HealthSubmissionCertainty expectedCertainty,
          })
        >[
          (
            name: 'written without expected energy',
            payload: _writePayload(
              status: 'written',
              workoutRecordId: 'workout-id',
              energyStatus: 'notExpected',
              certainty: 'submitted',
            ),
            expectedStatus: HealthWorkoutWriteStatus.written,
            expectedEnergyStatus: HealthEnergyWriteStatus.notExpected,
            expectedCertainty: HealthSubmissionCertainty.submitted,
          ),
          (
            name: 'already present with both native records',
            payload: _writePayload(
              status: 'alreadyPresent',
              workoutRecordId: 'workout-id',
              energyRecordId: 'energy-id',
              energyStatus: 'alreadyPresent',
              certainty: 'submitted',
            ),
            expectedStatus: HealthWorkoutWriteStatus.alreadyPresent,
            expectedEnergyStatus: HealthEnergyWriteStatus.alreadyPresent,
            expectedCertainty: HealthSubmissionCertainty.submitted,
          ),
          (
            name: 'written without energy permission',
            payload: _writePayload(
              status: 'writtenWithoutEnergy',
              workoutRecordId: 'workout-id',
              energyStatus: 'omittedPermission',
              certainty: 'submitted',
            ),
            expectedStatus: HealthWorkoutWriteStatus.writtenWithoutEnergy,
            expectedEnergyStatus: HealthEnergyWriteStatus.omittedPermission,
            expectedCertainty: HealthSubmissionCertainty.submitted,
          ),
          (
            name: 'blocked workout permission',
            payload: _writePayload(
              status: 'blockedWorkoutPermission',
              energyStatus: 'notSubmitted',
              certainty: 'notSubmitted',
            ),
            expectedStatus: HealthWorkoutWriteStatus.blockedWorkoutPermission,
            expectedEnergyStatus: HealthEnergyWriteStatus.notSubmitted,
            expectedCertainty: HealthSubmissionCertainty.notSubmitted,
          ),
          (
            name: 'verification required after ambiguous dispatch',
            payload: _writePayload(
              status: 'verificationRequired',
              energyStatus: 'verificationRequired',
              certainty: 'mayHaveSubmitted',
              retryable: true,
            ),
            expectedStatus: HealthWorkoutWriteStatus.verificationRequired,
            expectedEnergyStatus: HealthEnergyWriteStatus.verificationRequired,
            expectedCertainty: HealthSubmissionCertainty.mayHaveSubmitted,
          ),
          (
            name: 'inconsistent native state with energy only',
            payload: _writePayload(
              status: 'inconsistentNativeState',
              energyRecordId: 'energy-id',
              energyStatus: 'alreadyPresent',
              certainty: 'submitted',
            ),
            expectedStatus: HealthWorkoutWriteStatus.inconsistentNativeState,
            expectedEnergyStatus: HealthEnergyWriteStatus.alreadyPresent,
            expectedCertainty: HealthSubmissionCertainty.submitted,
          ),
          (
            name: 'proven transient failure',
            payload: _writePayload(
              status: 'transientFailure',
              energyStatus: 'notSubmitted',
              certainty: 'notSubmitted',
              retryable: true,
            ),
            expectedStatus: HealthWorkoutWriteStatus.transientFailure,
            expectedEnergyStatus: HealthEnergyWriteStatus.notSubmitted,
            expectedCertainty: HealthSubmissionCertainty.notSubmitted,
          ),
          (
            name: 'native invalid input',
            payload: _writePayload(status: 'invalidInput', energyStatus: 'notSubmitted', certainty: 'notSubmitted'),
            expectedStatus: HealthWorkoutWriteStatus.invalidInput,
            expectedEnergyStatus: HealthEnergyWriteStatus.notSubmitted,
            expectedCertainty: HealthSubmissionCertainty.notSubmitted,
          ),
          (
            name: 'native health service unavailable',
            payload: _writePayload(
              status: 'unavailable',
              energyStatus: 'notSubmitted',
              certainty: 'notSubmitted',
              retryable: true,
            ),
            expectedStatus: HealthWorkoutWriteStatus.unavailable,
            expectedEnergyStatus: HealthEnergyWriteStatus.notSubmitted,
            expectedCertainty: HealthSubmissionCertainty.notSubmitted,
          ),
          (
            name: 'already present workout with absent energy',
            payload: _writePayload(
              status: 'alreadyPresent',
              workoutRecordId: 'workout-id',
              energyStatus: 'absent',
              certainty: 'submitted',
            ),
            expectedStatus: HealthWorkoutWriteStatus.alreadyPresent,
            expectedEnergyStatus: HealthEnergyWriteStatus.absent,
            expectedCertainty: HealthSubmissionCertainty.submitted,
          ),
        ];

    for (final testCase in validCases) {
      test('decodes ${testCase.name}', () {
        final result = HealthWorkoutWriteResult.fromMethodChannel(testCase.payload);

        expect(result.status, testCase.expectedStatus);
        expect(result.energyStatus, testCase.expectedEnergyStatus);
        expect(result.submissionCertainty, testCase.expectedCertainty);
        expect(result.retryable, testCase.payload['retryable']);
      });
    }

    group('status and energy coherence matrix', () {
      for (final status in HealthWorkoutWriteStatus.values) {
        for (final energyStatus in HealthEnergyWriteStatus.values) {
          final pair = (status, energyStatus);
          if (_allowedWriteStatusPairs.contains(pair)) {
            test('accepts ${status.name} with ${energyStatus.name}', () {
              final result = HealthWorkoutWriteResult.fromMethodChannel(_writePayloadForPair(status, energyStatus));

              expect(result.status, status);
              expect(result.energyStatus, energyStatus);
            });
          } else {
            test('rejects ${status.name} with ${energyStatus.name}', () {
              expect(
                () => HealthWorkoutWriteResult.fromMethodChannel(_writePayloadForPair(status, energyStatus)),
                throwsA(isA<FormatException>().having((error) => error.message, 'message', contains('cannot pair'))),
              );
            });
          }
        }
      }
    });

    test('decodes an optional platform code', () {
      final result = HealthWorkoutWriteResult.fromMethodChannel(
        _writePayload(
          status: 'unavailable',
          energyStatus: 'notSubmitted',
          certainty: 'notSubmitted',
          platformCode: 'health_connect_unavailable',
        ),
      );

      expect(result.platformCode, 'health_connect_unavailable');
    });

    test('accepts a method-channel map with dynamic string keys', () {
      final response = <dynamic, dynamic>{
        'status': 'unavailable',
        'energyStatus': 'notSubmitted',
        'retryable': false,
        'submissionCertainty': 'notSubmitted',
      };

      expect(HealthWorkoutWriteResult.fromMethodChannel(response).status, HealthWorkoutWriteStatus.unavailable);
    });

    test('rejects non-string method-channel keys', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel(<dynamic, dynamic>{
          'status': 'unavailable',
          'energyStatus': 'notSubmitted',
          'retryable': false,
          'submissionCertainty': 'notSubmitted',
          1: 'unexpected',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    for (final value in <Object?>[null, 1, 'written', <Object?>[]]) {
      test('rejects non-map response ${value.runtimeType}', () {
        expect(() => HealthWorkoutWriteResult.fromMethodChannel(value), throwsA(isA<FormatException>()));
      });
    }

    for (final field in <String>['status', 'energyStatus', 'retryable', 'submissionCertainty']) {
      test('rejects missing required $field', () {
        final payload = _writePayload(status: 'unavailable', energyStatus: 'notSubmitted', certainty: 'notSubmitted')
          ..remove(field);

        expect(() => HealthWorkoutWriteResult.fromMethodChannel(payload), throwsA(isA<FormatException>()));
      });
    }

    test('rejects unknown write status', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel(
          _writePayload(status: 'futureWriteStatus', energyStatus: 'notSubmitted', certainty: 'notSubmitted'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unknown energy status', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel(
          _writePayload(status: 'unavailable', energyStatus: 'futureEnergyStatus', certainty: 'notSubmitted'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unknown submission certainty', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel(
          _writePayload(status: 'unavailable', energyStatus: 'notSubmitted', certainty: 'futureCertainty'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-boolean retryable', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel({
          ..._writePayload(status: 'unavailable', energyStatus: 'notSubmitted', certainty: 'notSubmitted'),
          'retryable': 1,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    for (final field in <String>['workoutRecordId', 'energyRecordId', 'platformCode']) {
      test('rejects blank optional $field', () {
        expect(
          () => HealthWorkoutWriteResult.fromMethodChannel({
            ..._writePayload(status: 'unavailable', energyStatus: 'notSubmitted', certainty: 'notSubmitted'),
            field: '  ',
          }),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects non-string optional $field', () {
        expect(
          () => HealthWorkoutWriteResult.fromMethodChannel({
            ..._writePayload(status: 'unavailable', energyStatus: 'notSubmitted', certainty: 'notSubmitted'),
            field: 7,
          }),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('rejects written without a workout record ID', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel(
          _writePayload(status: 'written', energyStatus: 'notExpected', certainty: 'submitted'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects writtenWithoutEnergy without a workout record ID', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel(
          _writePayload(status: 'writtenWithoutEnergy', energyStatus: 'omittedPermission', certainty: 'submitted'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    for (final status in <String>['blockedWorkoutPermission', 'invalidInput', 'unavailable']) {
      test('rejects IDs for $status', () {
        expect(
          () => HealthWorkoutWriteResult.fromMethodChannel(
            _writePayload(
              status: status,
              workoutRecordId: 'workout-id',
              energyStatus: 'notSubmitted',
              certainty: 'notSubmitted',
            ),
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects submitted certainty for $status', () {
        expect(
          () => HealthWorkoutWriteResult.fromMethodChannel(
            _writePayload(status: status, energyStatus: 'notSubmitted', certainty: 'submitted'),
          ),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('rejects transient failure without notSubmitted certainty', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel(
          _writePayload(status: 'transientFailure', energyStatus: 'notSubmitted', certainty: 'mayHaveSubmitted'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects submitted certainty mismatch for written result', () {
      expect(
        () => HealthWorkoutWriteResult.fromMethodChannel(
          _writePayload(
            status: 'written',
            workoutRecordId: 'workout-id',
            energyStatus: 'notExpected',
            certainty: 'mayHaveSubmitted',
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    for (final energyStatus in <String>['written', 'alreadyPresent']) {
      test('rejects $energyStatus energy without an energy record ID', () {
        final status = energyStatus == 'written' ? 'written' : 'alreadyPresent';
        expect(
          () => HealthWorkoutWriteResult.fromMethodChannel(
            _writePayload(
              status: status,
              workoutRecordId: 'workout-id',
              energyStatus: energyStatus,
              certainty: 'submitted',
            ),
          ),
          throwsA(isA<FormatException>()),
        );
      });
    }

    for (final energyStatus in <String>[
      'notExpected',
      'omittedPermission',
      'absent',
      'notSubmitted',
      'verificationRequired',
    ]) {
      test('rejects an energy record ID for $energyStatus energy', () {
        final status = switch (energyStatus) {
          'notExpected' => HealthWorkoutWriteStatus.written,
          'omittedPermission' => HealthWorkoutWriteStatus.writtenWithoutEnergy,
          'absent' => HealthWorkoutWriteStatus.alreadyPresent,
          'notSubmitted' => HealthWorkoutWriteStatus.blockedWorkoutPermission,
          'verificationRequired' => HealthWorkoutWriteStatus.verificationRequired,
          _ => throw StateError('Unhandled test energy status $energyStatus'),
        };
        final payload = _writePayloadForPair(status, HealthEnergyWriteStatus.values.byName(energyStatus));
        expect(
          () => HealthWorkoutWriteResult.fromMethodChannel({...payload, 'energyRecordId': 'energy-id'}),
          throwsA(isA<FormatException>()),
        );
      });
    }
  });

  group('public construction validation', () {
    test('constructs a valid write result with named arguments', () {
      final result = HealthWorkoutWriteResult(
        status: HealthWorkoutWriteStatus.written,
        workoutRecordId: 'workout-id',
        energyRecordId: 'energy-id',
        energyStatus: HealthEnergyWriteStatus.written,
        retryable: false,
        submissionCertainty: HealthSubmissionCertainty.submitted,
        platformCode: 'native-success',
      );

      expect(result.workoutRecordId, 'workout-id');
      expect(result.energyRecordId, 'energy-id');
      expect(result.platformCode, 'native-success');
    });

    final writeIdCases =
        <
          ({
            String name,
            HealthWorkoutWriteStatus status,
            String? workoutRecordId,
            String? energyRecordId,
            HealthEnergyWriteStatus energyStatus,
            HealthSubmissionCertainty certainty,
          })
        >[
          (
            name: 'written missing its workout ID',
            status: HealthWorkoutWriteStatus.written,
            workoutRecordId: null,
            energyRecordId: null,
            energyStatus: HealthEnergyWriteStatus.notExpected,
            certainty: HealthSubmissionCertainty.submitted,
          ),
          (
            name: 'alreadyPresent missing its workout ID',
            status: HealthWorkoutWriteStatus.alreadyPresent,
            workoutRecordId: null,
            energyRecordId: null,
            energyStatus: HealthEnergyWriteStatus.absent,
            certainty: HealthSubmissionCertainty.submitted,
          ),
          (
            name: 'writtenWithoutEnergy missing its workout ID',
            status: HealthWorkoutWriteStatus.writtenWithoutEnergy,
            workoutRecordId: null,
            energyRecordId: null,
            energyStatus: HealthEnergyWriteStatus.omittedPermission,
            certainty: HealthSubmissionCertainty.submitted,
          ),
          (
            name: 'blockedWorkoutPermission carrying a workout ID',
            status: HealthWorkoutWriteStatus.blockedWorkoutPermission,
            workoutRecordId: 'forbidden-workout-id',
            energyRecordId: null,
            energyStatus: HealthEnergyWriteStatus.notSubmitted,
            certainty: HealthSubmissionCertainty.notSubmitted,
          ),
          (
            name: 'verificationRequired carrying a workout ID',
            status: HealthWorkoutWriteStatus.verificationRequired,
            workoutRecordId: 'forbidden-workout-id',
            energyRecordId: null,
            energyStatus: HealthEnergyWriteStatus.verificationRequired,
            certainty: HealthSubmissionCertainty.mayHaveSubmitted,
          ),
          (
            name: 'inconsistentNativeState carrying a workout ID',
            status: HealthWorkoutWriteStatus.inconsistentNativeState,
            workoutRecordId: 'forbidden-workout-id',
            energyRecordId: 'energy-id',
            energyStatus: HealthEnergyWriteStatus.alreadyPresent,
            certainty: HealthSubmissionCertainty.submitted,
          ),
          (
            name: 'transientFailure carrying a workout ID',
            status: HealthWorkoutWriteStatus.transientFailure,
            workoutRecordId: 'forbidden-workout-id',
            energyRecordId: null,
            energyStatus: HealthEnergyWriteStatus.notSubmitted,
            certainty: HealthSubmissionCertainty.notSubmitted,
          ),
          (
            name: 'invalidInput carrying a workout ID',
            status: HealthWorkoutWriteStatus.invalidInput,
            workoutRecordId: 'forbidden-workout-id',
            energyRecordId: null,
            energyStatus: HealthEnergyWriteStatus.notSubmitted,
            certainty: HealthSubmissionCertainty.notSubmitted,
          ),
          (
            name: 'unavailable carrying a workout ID',
            status: HealthWorkoutWriteStatus.unavailable,
            workoutRecordId: 'forbidden-workout-id',
            energyRecordId: null,
            energyStatus: HealthEnergyWriteStatus.notSubmitted,
            certainty: HealthSubmissionCertainty.notSubmitted,
          ),
        ];

    for (final testCase in writeIdCases) {
      test('rejects ${testCase.name}', () {
        expect(
          () => HealthWorkoutWriteResult(
            status: testCase.status,
            workoutRecordId: testCase.workoutRecordId,
            energyRecordId: testCase.energyRecordId,
            energyStatus: testCase.energyStatus,
            retryable: false,
            submissionCertainty: testCase.certainty,
          ),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('write factory rejects an incoherent status pair', () {
      expect(
        () => HealthWorkoutWriteResult(
          status: HealthWorkoutWriteStatus.written,
          workoutRecordId: 'workout-id',
          energyStatus: HealthEnergyWriteStatus.verificationRequired,
          retryable: true,
          submissionCertainty: HealthSubmissionCertainty.submitted,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('write factory rejects invalid certainty', () {
      expect(
        () => HealthWorkoutWriteResult(
          status: HealthWorkoutWriteStatus.alreadyPresent,
          workoutRecordId: 'workout-id',
          energyStatus: HealthEnergyWriteStatus.absent,
          retryable: false,
          submissionCertainty: HealthSubmissionCertainty.notSubmitted,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('write factory rejects blank optional strings', () {
      expect(
        () => HealthWorkoutWriteResult(
          status: HealthWorkoutWriteStatus.written,
          workoutRecordId: ' ',
          energyStatus: HealthEnergyWriteStatus.notExpected,
          retryable: false,
          submissionCertainty: HealthSubmissionCertainty.submitted,
          platformCode: '',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('constructs a valid record lookup', () {
      final lookup = HealthRecordLookup(status: HealthRecordLookupStatus.present, recordId: 'record-id');

      expect(lookup.recordId, 'record-id');
    });

    test('record lookup factory requires an ID for present', () {
      expect(() => HealthRecordLookup(status: HealthRecordLookupStatus.present), throwsA(isA<FormatException>()));
    });

    test('record lookup factory forbids an ID for a non-present status', () {
      expect(
        () => HealthRecordLookup(status: HealthRecordLookupStatus.absent, recordId: 'forbidden-id'),
        throwsA(isA<FormatException>()),
      );
    });

    test('record lookup factory rejects a blank present ID', () {
      expect(
        () => HealthRecordLookup(status: HealthRecordLookupStatus.present, recordId: ' '),
        throwsA(isA<FormatException>()),
      );
    });

    test('constructs a valid workout lookup result', () {
      final result = HealthWorkoutLookupResult(
        workout: HealthRecordLookup(status: HealthRecordLookupStatus.present, recordId: 'workout-id'),
        energy: HealthRecordLookup(status: HealthRecordLookupStatus.absent),
        derivedStatus: HealthWorkoutLookupStatus.workoutOnly,
        platformCode: 'lookup-complete',
      );

      expect(result.derivedStatus, HealthWorkoutLookupStatus.workoutOnly);
      expect(result.platformCode, 'lookup-complete');
    });

    test('workout lookup factory rejects a mismatched derived status', () {
      expect(
        () => HealthWorkoutLookupResult(
          workout: HealthRecordLookup(status: HealthRecordLookupStatus.present, recordId: 'workout-id'),
          energy: HealthRecordLookup(status: HealthRecordLookupStatus.absent),
          derivedStatus: HealthWorkoutLookupStatus.present,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('workout lookup factory rejects workout notExpected', () {
      expect(
        () => HealthWorkoutLookupResult(
          workout: HealthRecordLookup(status: HealthRecordLookupStatus.notExpected),
          energy: HealthRecordLookup(status: HealthRecordLookupStatus.notExpected),
          derivedStatus: HealthWorkoutLookupStatus.absent,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('workout lookup factory rejects a blank platform code', () {
      expect(
        () => HealthWorkoutLookupResult(
          workout: HealthRecordLookup(status: HealthRecordLookupStatus.absent),
          energy: HealthRecordLookup(status: HealthRecordLookupStatus.notExpected),
          derivedStatus: HealthWorkoutLookupStatus.absent,
          platformCode: ' ',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Health workout channel API', () {
    late HealthTestContext ctx;

    setUp(() async {
      ctx = HealthTestContext();
      await ctx.setUp();
    });

    tearDown(() async {
      await ctx.tearDown();
    });

    group('writeWorkoutData', () {
      test('forwards the complete frozen workout envelope', () async {
        ctx.channel.when('writeWorkoutData', {
          'status': 'written',
          'workoutRecordId': 'native-workout',
          'energyRecordId': 'native-energy',
          'energyStatus': 'written',
          'retryable': false,
          'submissionCertainty': 'submitted',
        });

        final result = await _writeValidWorkout(ctx.health);

        expect(result.status, HealthWorkoutWriteStatus.written);
        expect(result.workoutRecordId, 'native-workout');
        expect(result.energyRecordId, 'native-energy');
        final call = ctx.channel.lastCallFor('writeWorkoutData');
        expect(call, isNotNull);
        expect(Map<String, Object?>.from(call!.arguments as Map), <String, Object?>{
          'workoutClientRecordId': _workoutClientId,
          'energyClientRecordId': _energyClientId,
          'clientRecordVersion': 0,
          'activityType': 'STRENGTH_TRAINING',
          'startTime': _workoutStart.millisecondsSinceEpoch,
          'endTime': _workoutEnd.millisecondsSinceEpoch,
          'startZoneOffsetSeconds': -18000,
          'endZoneOffsetSeconds': -14400,
          'activeEnergyKcal': 123.0,
          'title': 'Plates Workout',
          'recordingProvenance': 'activelyRecorded',
          'recordingDevice': 'phone',
        });
        expect(ctx.channel.calls.map((call) => call.method), <String>['writeWorkoutData']);
      });

      test('forwards a no-energy workout with explicit nulls', () async {
        ctx.channel.when('writeWorkoutData', {
          'status': 'written',
          'workoutRecordId': 'native-workout',
          'energyStatus': 'notExpected',
          'retryable': false,
          'submissionCertainty': 'submitted',
        });

        final result = await _writeValidWorkout(ctx.health, energyClientRecordId: null, activeEnergyKcal: null);

        expect(result.energyStatus, HealthEnergyWriteStatus.notExpected);
        final args = Map<String, Object?>.from(ctx.channel.lastCallFor('writeWorkoutData')!.arguments as Map);
        expect(args['energyClientRecordId'], isNull);
        expect(args['activeEnergyKcal'], isNull);
      });

      test('trims opaque IDs and title before forwarding', () async {
        ctx.channel.when('writeWorkoutData', {
          'status': 'written',
          'workoutRecordId': 'native-workout',
          'energyRecordId': 'native-energy',
          'energyStatus': 'written',
          'retryable': false,
          'submissionCertainty': 'submitted',
        });

        await _writeValidWorkout(
          ctx.health,
          workoutClientRecordId: '  $_workoutClientId  ',
          energyClientRecordId: '\t$_energyClientId\n',
          title: '  Plates Workout  ',
        );

        final args = Map<String, Object?>.from(ctx.channel.lastCallFor('writeWorkoutData')!.arguments as Map);
        expect(args['workoutClientRecordId'], _workoutClientId);
        expect(args['energyClientRecordId'], _energyClientId);
        expect(args['title'], 'Plates Workout');
      });

      test('accepts both zone-offset boundary values', () async {
        ctx.channel.when('writeWorkoutData', {
          'status': 'written',
          'workoutRecordId': 'native-workout',
          'energyRecordId': 'native-energy',
          'energyStatus': 'written',
          'retryable': false,
          'submissionCertainty': 'submitted',
        });

        await _writeValidWorkout(ctx.health, startZoneOffsetSeconds: -64800, endZoneOffsetSeconds: 64800);

        final args = Map<String, Object?>.from(ctx.channel.lastCallFor('writeWorkoutData')!.arguments as Map);
        expect(args['startZoneOffsetSeconds'], -64800);
        expect(args['endZoneOffsetSeconds'], 64800);
      });

      test('rejects an Android-only activity on iOS', () async {
        final iosHealth = Health(
          deviceInfo: ctx.deviceInfo,
          workoutPlatformIsIOS: () => true,
          workoutPlatformIsAndroid: () => false,
        );

        await expectLater(
          _writeValidWorkout(iosHealth, activityType: HealthWorkoutActivityType.BIKING_STATIONARY),
          throwsA(isA<HealthException>()),
        );
        expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
      });

      test('rejects an iOS-only activity on Android', () async {
        final androidHealth = Health(
          deviceInfo: ctx.deviceInfo,
          workoutPlatformIsIOS: () => false,
          workoutPlatformIsAndroid: () => true,
        );

        await expectLater(
          _writeValidWorkout(androidHealth, activityType: HealthWorkoutActivityType.BARRE),
          throwsA(isA<HealthException>()),
        );
        expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
      });

      group('matches the exact Android native activity support set', () {
        for (final activityType in HealthWorkoutActivityType.values) {
          final isSupported = _androidSupportedWorkoutActivities.contains(activityType);

          test('${isSupported ? 'accepts' : 'rejects'} ${activityType.name}', () async {
            final androidHealth = Health(
              deviceInfo: ctx.deviceInfo,
              workoutPlatformIsIOS: () => false,
              workoutPlatformIsAndroid: () => true,
            );

            if (isSupported) {
              ctx.channel.when('writeWorkoutData', {
                'status': 'written',
                'workoutRecordId': 'native-workout',
                'energyRecordId': 'native-energy',
                'energyStatus': 'written',
                'retryable': false,
                'submissionCertainty': 'submitted',
              });

              await _writeValidWorkout(androidHealth, activityType: activityType);

              final arguments = Map<String, Object?>.from(
                ctx.channel.lastCallFor('writeWorkoutData')!.arguments as Map,
              );
              expect(arguments['activityType'], activityType.name);
            } else {
              await expectLater(
                _writeValidWorkout(androidHealth, activityType: activityType),
                throwsA(isA<HealthException>()),
              );
              expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
            }
          });
        }
      });

      test('requires energy and energy ID together', () async {
        await expectLater(_writeValidWorkout(ctx.health, energyClientRecordId: null), throwsArgumentError);
        expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
      });

      test('requires energy ID and energy together', () async {
        await expectLater(_writeValidWorkout(ctx.health, activeEnergyKcal: null), throwsArgumentError);
        expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
      });

      final invalidRanges = <({String name, DateTime start, DateTime end})>[
        (name: 'equal times', start: _workoutStart, end: _workoutStart),
        (name: 'reversed times', start: _workoutEnd, end: _workoutStart),
      ];
      for (final testCase in invalidRanges) {
        test('rejects ${testCase.name}', () async {
          await expectLater(
            _writeValidWorkout(ctx.health, start: testCase.start, end: testCase.end),
            throwsArgumentError,
          );
          expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
        });
      }

      for (final title in <String>['', ' \t\n']) {
        test('rejects blank title ${title.length}', () async {
          await expectLater(_writeValidWorkout(ctx.health, title: title), throwsArgumentError);
          expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
        });
      }

      for (final id in <String>['', ' ', 'not-a-uuid']) {
        test('rejects invalid workout ID ${id.length}', () async {
          await expectLater(_writeValidWorkout(ctx.health, workoutClientRecordId: id), throwsArgumentError);
          expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
        });

        test('rejects invalid energy ID ${id.length}', () async {
          await expectLater(_writeValidWorkout(ctx.health, energyClientRecordId: id), throwsArgumentError);
          expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
        });
      }

      for (final version in <int>[-1, 1]) {
        test('rejects client record version $version', () async {
          await expectLater(_writeValidWorkout(ctx.health, clientRecordVersion: version), throwsArgumentError);
          expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
        });
      }

      for (final energy in <double>[0, -1, double.nan, double.infinity, double.negativeInfinity]) {
        test('rejects invalid energy ${energy.toString()}', () async {
          await expectLater(_writeValidWorkout(ctx.health, activeEnergyKcal: energy), throwsArgumentError);
          expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
        });
      }

      final invalidOffsets = <({String name, int startOffset, int endOffset})>[
        (name: 'start below lower bound', startOffset: -64801, endOffset: 0),
        (name: 'start above upper bound', startOffset: 64801, endOffset: 0),
        (name: 'end below lower bound', startOffset: 0, endOffset: -64801),
        (name: 'end above upper bound', startOffset: 0, endOffset: 64801),
      ];
      for (final testCase in invalidOffsets) {
        test('rejects ${testCase.name}', () async {
          await expectLater(
            _writeValidWorkout(
              ctx.health,
              startZoneOffsetSeconds: testCase.startOffset,
              endZoneOffsetSeconds: testCase.endOffset,
            ),
            throwsArgumentError,
          );
          expect(ctx.channel.lastCallFor('writeWorkoutData'), isNull);
        });
      }

      test('rejects an impossible native write result', () async {
        ctx.channel.when('writeWorkoutData', {
          'status': 'written',
          'workoutRecordId': 'native-workout',
          'energyStatus': 'verificationRequired',
          'retryable': true,
          'submissionCertainty': 'submitted',
        });

        await expectLater(_writeValidWorkout(ctx.health), throwsA(isA<FormatException>()));
        expect(ctx.channel.lastCallFor('writeWorkoutData'), isNotNull);
      });
    });

    group('lookupWorkoutData', () {
      test('forwards the frozen lookup envelope and decodes records', () async {
        ctx.channel.when('lookupWorkoutData', {
          'workout': {'status': 'present', 'recordId': 'native-workout'},
          'energy': {'status': 'present', 'recordId': 'native-energy'},
          'derivedStatus': 'present',
        });

        final result = await _lookupValidWorkout(ctx.health);

        expect(result.derivedStatus, HealthWorkoutLookupStatus.present);
        expect(result.workout.recordId, 'native-workout');
        expect(result.energy.recordId, 'native-energy');
        final call = ctx.channel.lastCallFor('lookupWorkoutData');
        expect(call, isNotNull);
        expect(Map<String, Object?>.from(call!.arguments as Map), <String, Object?>{
          'workoutClientRecordId': _workoutClientId,
          'energyClientRecordId': _energyClientId,
          'startTime': _workoutStart.millisecondsSinceEpoch,
          'endTime': _workoutEnd.millisecondsSinceEpoch,
        });
      });

      test('decodes notExpected when no energy ID was frozen', () async {
        ctx.channel.when('lookupWorkoutData', {
          'workout': {'status': 'absent'},
          'energy': {'status': 'notExpected'},
          'derivedStatus': 'absent',
        });

        final result = await _lookupValidWorkout(ctx.health, energyClientRecordId: null);

        expect(result.energy.status, HealthRecordLookupStatus.notExpected);
        final args = Map<String, Object?>.from(ctx.channel.lastCallFor('lookupWorkoutData')!.arguments as Map);
        expect(args['energyClientRecordId'], isNull);
      });

      test('trims lookup IDs before forwarding', () async {
        ctx.channel.when('lookupWorkoutData', {
          'workout': {'status': 'absent'},
          'energy': {'status': 'absent'},
          'derivedStatus': 'absent',
        });

        await _lookupValidWorkout(
          ctx.health,
          workoutClientRecordId: ' $_workoutClientId ',
          energyClientRecordId: '\t$_energyClientId\n',
        );

        final args = Map<String, Object?>.from(ctx.channel.lastCallFor('lookupWorkoutData')!.arguments as Map);
        expect(args['workoutClientRecordId'], _workoutClientId);
        expect(args['energyClientRecordId'], _energyClientId);
      });

      final invalidRanges = <({String name, DateTime start, DateTime end})>[
        (name: 'equal times', start: _workoutStart, end: _workoutStart),
        (name: 'reversed times', start: _workoutEnd, end: _workoutStart),
      ];
      for (final testCase in invalidRanges) {
        test('rejects ${testCase.name}', () async {
          await expectLater(
            _lookupValidWorkout(ctx.health, start: testCase.start, end: testCase.end),
            throwsArgumentError,
          );
          expect(ctx.channel.lastCallFor('lookupWorkoutData'), isNull);
        });
      }

      for (final id in <String>['', ' ', 'not-a-uuid']) {
        test('rejects invalid workout ID ${id.length}', () async {
          await expectLater(_lookupValidWorkout(ctx.health, workoutClientRecordId: id), throwsArgumentError);
          expect(ctx.channel.lastCallFor('lookupWorkoutData'), isNull);
        });

        test('rejects invalid energy ID ${id.length}', () async {
          await expectLater(_lookupValidWorkout(ctx.health, energyClientRecordId: id), throwsArgumentError);
          expect(ctx.channel.lastCallFor('lookupWorkoutData'), isNull);
        });
      }

      test('rejects an impossible native lookup result', () async {
        ctx.channel.when('lookupWorkoutData', {
          'workout': {'status': 'absent'},
          'energy': {'status': 'present', 'recordId': 'native-energy'},
          'derivedStatus': 'present',
        });

        await expectLater(_lookupValidWorkout(ctx.health), throwsA(isA<FormatException>()));
        expect(ctx.channel.lastCallFor('lookupWorkoutData'), isNotNull);
      });
    });
  });

  group('HealthWorkoutLookupResult codec', () {
    test('decodes workout-only', () {
      final result = HealthWorkoutLookupResult.fromMethodChannel({
        'workout': {'status': 'present', 'recordId': 'workout-native-id'},
        'energy': {'status': 'absent'},
        'derivedStatus': 'workoutOnly',
      });
      expect(result.derivedStatus, HealthWorkoutLookupStatus.workoutOnly);
    });

    test('rejects energy present without inconsistent derived status', () {
      expect(
        () => HealthWorkoutLookupResult.fromMethodChannel({
          'workout': {'status': 'absent'},
          'energy': {'status': 'present', 'recordId': 'energy-native-id'},
          'derivedStatus': 'present',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    final derivations =
        <
          ({
            String name,
            Map<String, Object?> workout,
            Map<String, Object?> energy,
            String derived,
            HealthWorkoutLookupStatus expected,
          })
        >[
          (
            name: 'unavailable workout dominates present energy',
            workout: const {'status': 'unavailable'},
            energy: const {'status': 'present', 'recordId': 'energy-id'},
            derived: 'unavailable',
            expected: HealthWorkoutLookupStatus.unavailable,
          ),
          (
            name: 'unavailable expected energy keeps absent workout unresolved',
            workout: const {'status': 'absent'},
            energy: const {'status': 'unavailable'},
            derived: 'unavailable',
            expected: HealthWorkoutLookupStatus.unavailable,
          ),
          (
            name: 'energy without workout is inconsistent',
            workout: const {'status': 'absent'},
            energy: const {'status': 'present', 'recordId': 'energy-id'},
            derived: 'inconsistent',
            expected: HealthWorkoutLookupStatus.inconsistent,
          ),
          (
            name: 'both expected records absent',
            workout: const {'status': 'absent'},
            energy: const {'status': 'absent'},
            derived: 'absent',
            expected: HealthWorkoutLookupStatus.absent,
          ),
          (
            name: 'present workout with unavailable energy is unresolved',
            workout: const {'status': 'present', 'recordId': 'workout-id'},
            energy: const {'status': 'unavailable'},
            derived: 'unavailable',
            expected: HealthWorkoutLookupStatus.unavailable,
          ),
          (
            name: 'both expected records present',
            workout: const {'status': 'present', 'recordId': 'workout-id'},
            energy: const {'status': 'present', 'recordId': 'energy-id'},
            derived: 'present',
            expected: HealthWorkoutLookupStatus.present,
          ),
          (
            name: 'present workout with absent energy is workout-only',
            workout: const {'status': 'present', 'recordId': 'workout-id'},
            energy: const {'status': 'absent'},
            derived: 'workoutOnly',
            expected: HealthWorkoutLookupStatus.workoutOnly,
          ),
          (
            name: 'absent workout with unexpected energy is absent',
            workout: const {'status': 'absent'},
            energy: const {'status': 'notExpected'},
            derived: 'absent',
            expected: HealthWorkoutLookupStatus.absent,
          ),
          (
            name: 'present workout with unexpected energy is workout-only',
            workout: const {'status': 'present', 'recordId': 'workout-id'},
            energy: const {'status': 'notExpected'},
            derived: 'workoutOnly',
            expected: HealthWorkoutLookupStatus.workoutOnly,
          ),
        ];

    for (final testCase in derivations) {
      test('derives ${testCase.name}', () {
        final result = HealthWorkoutLookupResult.fromMethodChannel({
          'workout': testCase.workout,
          'energy': testCase.energy,
          'derivedStatus': testCase.derived,
        });

        expect(result.derivedStatus, testCase.expected);
      });
    }

    test('decodes optional platform code', () {
      final result = HealthWorkoutLookupResult.fromMethodChannel({
        'workout': {'status': 'unavailable'},
        'energy': {'status': 'unavailable'},
        'derivedStatus': 'unavailable',
        'platformCode': 'read_permission_denied',
      });

      expect(result.platformCode, 'read_permission_denied');
    });

    for (final value in <Object?>[null, true, 1, 'present', <Object?>[]]) {
      test('rejects non-map lookup response ${value.runtimeType}', () {
        expect(() => HealthWorkoutLookupResult.fromMethodChannel(value), throwsA(isA<FormatException>()));
      });
    }

    test('rejects missing workout component', () {
      expect(
        () => HealthWorkoutLookupResult.fromMethodChannel({
          'energy': {'status': 'notExpected'},
          'derivedStatus': 'absent',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects missing energy component', () {
      expect(
        () => HealthWorkoutLookupResult.fromMethodChannel({
          'workout': {'status': 'absent'},
          'derivedStatus': 'absent',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects unknown derived status', () {
      expect(
        () => HealthWorkoutLookupResult.fromMethodChannel({
          'workout': {'status': 'absent'},
          'energy': {'status': 'notExpected'},
          'derivedStatus': 'futureLookupStatus',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    final energyLookups = <Map<String, Object?>>[
      {'status': 'present', 'recordId': 'energy-id'},
      {'status': 'absent'},
      {'status': 'unavailable'},
      {'status': 'notExpected'},
    ];
    for (final energy in energyLookups) {
      test('rejects workout notExpected with energy ${energy['status']}', () {
        expect(
          () => HealthWorkoutLookupResult.fromMethodChannel({
            'workout': {'status': 'notExpected'},
            'energy': energy,
            'derivedStatus': 'unavailable',
          }),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('rejects blank lookup platform code', () {
      expect(
        () => HealthWorkoutLookupResult.fromMethodChannel({
          'workout': {'status': 'absent'},
          'energy': {'status': 'notExpected'},
          'derivedStatus': 'absent',
          'platformCode': '',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HealthRecordLookup codec', () {
    test('decodes present with a record ID', () {
      final lookup = HealthRecordLookup.fromMethodChannel({'status': 'present', 'recordId': 'native-id'});

      expect(lookup.status, HealthRecordLookupStatus.present);
      expect(lookup.recordId, 'native-id');
    });

    for (final status in <String>['absent', 'unavailable', 'notExpected']) {
      test('decodes $status without a record ID', () {
        final lookup = HealthRecordLookup.fromMethodChannel({'status': status});

        expect(lookup.recordId, isNull);
      });
    }

    test('rejects present without an ID', () {
      expect(() => HealthRecordLookup.fromMethodChannel({'status': 'present'}), throwsA(isA<FormatException>()));
    });

    for (final status in <String>['absent', 'unavailable', 'notExpected']) {
      test('rejects an ID for $status', () {
        expect(
          () => HealthRecordLookup.fromMethodChannel({'status': status, 'recordId': 'forbidden-id'}),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('rejects a blank present ID', () {
      expect(
        () => HealthRecordLookup.fromMethodChannel({'status': 'present', 'recordId': ' '}),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an unknown component status', () {
      expect(() => HealthRecordLookup.fromMethodChannel({'status': 'futureStatus'}), throwsA(isA<FormatException>()));
    });

    test('rejects a non-map component', () {
      expect(() => HealthRecordLookup.fromMethodChannel(false), throwsA(isA<FormatException>()));
    });
  });
}

Map<String, Object?> _writePayload({
  required String status,
  required String energyStatus,
  required String certainty,
  String? workoutRecordId,
  String? energyRecordId,
  bool retryable = false,
  String? platformCode,
}) => <String, Object?>{
  'status': status,
  'workoutRecordId': workoutRecordId,
  'energyRecordId': energyRecordId,
  'energyStatus': energyStatus,
  'retryable': retryable,
  'submissionCertainty': certainty,
  'platformCode': platformCode,
};

Map<String, Object?> _writePayloadForPair(HealthWorkoutWriteStatus status, HealthEnergyWriteStatus energyStatus) {
  final workoutRecordId = switch (status) {
    HealthWorkoutWriteStatus.written ||
    HealthWorkoutWriteStatus.alreadyPresent ||
    HealthWorkoutWriteStatus.writtenWithoutEnergy => 'workout-id',
    HealthWorkoutWriteStatus.blockedWorkoutPermission ||
    HealthWorkoutWriteStatus.verificationRequired ||
    HealthWorkoutWriteStatus.inconsistentNativeState ||
    HealthWorkoutWriteStatus.transientFailure ||
    HealthWorkoutWriteStatus.invalidInput ||
    HealthWorkoutWriteStatus.unavailable => null,
  };
  final energyRecordId = switch (energyStatus) {
    HealthEnergyWriteStatus.written || HealthEnergyWriteStatus.alreadyPresent => 'energy-id',
    HealthEnergyWriteStatus.notExpected ||
    HealthEnergyWriteStatus.omittedPermission ||
    HealthEnergyWriteStatus.absent ||
    HealthEnergyWriteStatus.notSubmitted ||
    HealthEnergyWriteStatus.verificationRequired => null,
  };
  final certainty = switch (status) {
    HealthWorkoutWriteStatus.written ||
    HealthWorkoutWriteStatus.alreadyPresent ||
    HealthWorkoutWriteStatus.writtenWithoutEnergy ||
    HealthWorkoutWriteStatus.inconsistentNativeState => 'submitted',
    HealthWorkoutWriteStatus.verificationRequired => 'mayHaveSubmitted',
    HealthWorkoutWriteStatus.blockedWorkoutPermission ||
    HealthWorkoutWriteStatus.transientFailure ||
    HealthWorkoutWriteStatus.invalidInput ||
    HealthWorkoutWriteStatus.unavailable => 'notSubmitted',
  };

  return _writePayload(
    status: status.name,
    workoutRecordId: workoutRecordId,
    energyRecordId: energyRecordId,
    energyStatus: energyStatus.name,
    certainty: certainty,
  );
}

Future<HealthWorkoutWriteResult> _writeValidWorkout(
  Health health, {
  String workoutClientRecordId = _workoutClientId,
  String? energyClientRecordId = _energyClientId,
  int clientRecordVersion = 0,
  HealthWorkoutActivityType activityType = HealthWorkoutActivityType.STRENGTH_TRAINING,
  DateTime? start,
  DateTime? end,
  int startZoneOffsetSeconds = -18000,
  int endZoneOffsetSeconds = -14400,
  double? activeEnergyKcal = 123,
  String title = 'Plates Workout',
  HealthRecordingProvenance recordingProvenance = HealthRecordingProvenance.activelyRecorded,
  HealthRecordingDevice recordingDevice = HealthRecordingDevice.phone,
}) => health.writeWorkoutData(
  workoutClientRecordId: workoutClientRecordId,
  energyClientRecordId: energyClientRecordId,
  clientRecordVersion: clientRecordVersion,
  activityType: activityType,
  start: start ?? _workoutStart,
  end: end ?? _workoutEnd,
  startZoneOffsetSeconds: startZoneOffsetSeconds,
  endZoneOffsetSeconds: endZoneOffsetSeconds,
  activeEnergyKcal: activeEnergyKcal,
  title: title,
  recordingProvenance: recordingProvenance,
  recordingDevice: recordingDevice,
);

Future<HealthWorkoutLookupResult> _lookupValidWorkout(
  Health health, {
  String workoutClientRecordId = _workoutClientId,
  String? energyClientRecordId = _energyClientId,
  DateTime? start,
  DateTime? end,
}) => health.lookupWorkoutData(
  workoutClientRecordId: workoutClientRecordId,
  energyClientRecordId: energyClientRecordId,
  start: start ?? _workoutStart,
  end: end ?? _workoutEnd,
);
