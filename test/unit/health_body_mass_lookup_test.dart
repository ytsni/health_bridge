import 'package:flutter_test/flutter_test.dart';
import 'package:health_bridge/health.dart';

import '../support/health_test_context.dart';

const _clientRecordId = '018f8d7e-3333-7333-8333-333333333333';
final _measuredAt = DateTime.utc(2026, 7, 20, 12);

void main() {
  late HealthTestContext context;

  setUp(() async {
    context = HealthTestContext();
    await context.setUp();
  });

  tearDown(() => context.tearDown());

  group('lookupBodyMassData', () {
    test('sends exact identity and UTC instant', () async {
      context.channel.when('lookupBodyMassData', _response(status: 'present', recordId: 'native-weight'));

      final result = await context.health.lookupBodyMassData(clientRecordId: _clientRecordId, measuredAt: _measuredAt);

      expect(result.status, HealthBodyMassLookupStatus.present);
      expect(result.recordId, 'native-weight');
      final call = context.channel.lastCallFor('lookupBodyMassData');
      expect(call, isNotNull);
      expect(Map<String, Object?>.from(call!.arguments as Map), <String, Object?>{
        'clientRecordId': _clientRecordId,
        'measuredAt': _measuredAt.millisecondsSinceEpoch,
      });
    });

    test('normalizes a local instant to its UTC epoch milliseconds', () async {
      context.channel.when('lookupBodyMassData', _response(status: 'absent'));
      final localInstant = DateTime.parse('2026-07-20T08:00:00-04:00');

      await context.health.lookupBodyMassData(clientRecordId: _clientRecordId, measuredAt: localInstant);

      final arguments = Map<String, Object?>.from(context.channel.lastCallFor('lookupBodyMassData')!.arguments as Map);
      expect(arguments['measuredAt'], _measuredAt.millisecondsSinceEpoch);
    });

    for (final clientRecordId in <String>['', ' ', '\n\t']) {
      test('rejects blank client record ID ${clientRecordId.length}', () async {
        await expectLater(
          context.health.lookupBodyMassData(clientRecordId: clientRecordId, measuredAt: _measuredAt),
          throwsArgumentError,
        );
        expect(context.channel.lastCallFor('lookupBodyMassData'), isNull);
      });
    }

    test('rejects a measured instant that loses sub-millisecond identity', () async {
      await expectLater(
        context.health.lookupBodyMassData(
          clientRecordId: _clientRecordId,
          measuredAt: _measuredAt.add(const Duration(microseconds: 1)),
        ),
        throwsArgumentError,
      );
      expect(context.channel.lastCallFor('lookupBodyMassData'), isNull);
    });

    for (final testCase
        in <({String status, String? recordId, String? platformCode, HealthBodyMassLookupStatus expected})>[
          (
            status: 'present',
            recordId: 'native-weight',
            platformCode: null,
            expected: HealthBodyMassLookupStatus.present,
          ),
          (status: 'absent', recordId: null, platformCode: null, expected: HealthBodyMassLookupStatus.absent),
          (
            status: 'unavailable',
            recordId: null,
            platformCode: 'historyWindowUnavailable',
            expected: HealthBodyMassLookupStatus.unavailable,
          ),
        ]) {
      test('decodes ${testCase.status}', () {
        final result = HealthBodyMassLookupResult.fromMethodChannel(
          _response(status: testCase.status, recordId: testCase.recordId, platformCode: testCase.platformCode),
        );

        expect(result.status, testCase.expected);
        expect(result.recordId, testCase.recordId);
        expect(result.platformCode, testCase.platformCode);
      });
    }
  });

  group('HealthBodyMassLookupResult codec', () {
    test('rejects an unknown status', () {
      expect(
        () => HealthBodyMassLookupResult.fromMethodChannel(_response(status: 'futureStatus')),
        throwsA(isA<FormatException>()),
      );
    });

    for (final missingKey in <String>['status', 'recordId', 'platformCode']) {
      test('rejects a missing $missingKey key', () {
        final response = _response(status: 'absent')..remove(missingKey);

        expect(() => HealthBodyMassLookupResult.fromMethodChannel(response), throwsA(isA<FormatException>()));
      });
    }

    test('rejects an extra response key', () {
      expect(
        () => HealthBodyMassLookupResult.fromMethodChannel(<String, Object?>{
          ..._response(status: 'absent'),
          'unexpected': true,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a present result without a record ID', () {
      expect(
        () => HealthBodyMassLookupResult.fromMethodChannel(_response(status: 'present')),
        throwsA(isA<FormatException>()),
      );
    });

    for (final status in <String>['absent', 'unavailable']) {
      test('rejects a $status result with a record ID', () {
        expect(
          () => HealthBodyMassLookupResult.fromMethodChannel(_response(status: status, recordId: 'forbidden-id')),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('rejects blank optional fields when present', () {
      expect(
        () => HealthBodyMassLookupResult.fromMethodChannel(
          _response(status: 'present', recordId: ' ', platformCode: 'code'),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => HealthBodyMassLookupResult.fromMethodChannel(_response(status: 'unavailable', platformCode: '\t')),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Map<String, Object?> _response({required String status, String? recordId, String? platformCode}) => <String, Object?>{
  'status': status,
  'recordId': recordId,
  'platformCode': platformCode,
};
