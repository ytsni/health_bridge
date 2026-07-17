import 'package:flutter_test/flutter_test.dart';
import 'package:health_bridge_example/workout_export_envelope.dart';

void main() {
  group('ExampleWorkoutExportEnvelope', () {
    test('owns distinct type IDs and one frozen time envelope', () {
      final ids = <String>[
        '018f8d7e-1111-4111-8111-111111111111',
        '018f8d7e-2222-4222-8222-222222222222',
      ].iterator;
      final start = DateTime.parse('2026-03-08T06:55:00-05:00');
      final end = DateTime.parse('2026-03-08T07:25:00-04:00');

      final envelope = ExampleWorkoutExportEnvelope.fresh(
        start: start,
        end: end,
        uuidFactory: () {
          ids.moveNext();
          return ids.current;
        },
      );

      expect(
        envelope.workoutClientRecordId,
        '018f8d7e-1111-4111-8111-111111111111',
      );
      expect(
        envelope.energyClientRecordId,
        '018f8d7e-2222-4222-8222-222222222222',
      );
      expect(
        envelope.energyClientRecordId,
        isNot(envelope.workoutClientRecordId),
      );
      expect(envelope.start, same(start));
      expect(envelope.end, same(end));
      expect(envelope.startZoneOffsetSeconds, start.timeZoneOffset.inSeconds);
      expect(envelope.endZoneOffsetSeconds, end.timeZoneOffset.inSeconds);
      expect(envelope.clientRecordVersion, 0);
    });

    test('generates a fresh UUID pair for every logical envelope', () {
      final start = DateTime.utc(2026, 1, 1, 10);
      final end = start.add(const Duration(hours: 1));

      final first = ExampleWorkoutExportEnvelope.fresh(start: start, end: end);
      final second = ExampleWorkoutExportEnvelope.fresh(start: start, end: end);

      final ids = <String>{
        first.workoutClientRecordId,
        first.energyClientRecordId,
        second.workoutClientRecordId,
        second.energyClientRecordId,
      };
      expect(ids, hasLength(4));
      expect(
        ids,
        everyElement(
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        ),
      );
    });
  });
}
