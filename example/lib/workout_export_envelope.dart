import 'dart:math';

typedef ExampleUuidFactory = String Function();

final Random _secureRandom = Random.secure();

final class ExampleWorkoutExportEnvelope {
  factory ExampleWorkoutExportEnvelope.fresh({
    required DateTime start,
    required DateTime end,
    ExampleUuidFactory uuidFactory = _uuidV4,
  }) {
    return ExampleWorkoutExportEnvelope._(
      workoutClientRecordId: uuidFactory(),
      energyClientRecordId: uuidFactory(),
      start: start,
      end: end,
      startZoneOffsetSeconds: start.timeZoneOffset.inSeconds,
      endZoneOffsetSeconds: end.timeZoneOffset.inSeconds,
    );
  }

  const ExampleWorkoutExportEnvelope._({
    required this.workoutClientRecordId,
    required this.energyClientRecordId,
    required this.start,
    required this.end,
    required this.startZoneOffsetSeconds,
    required this.endZoneOffsetSeconds,
  });

  final String workoutClientRecordId;
  final String energyClientRecordId;
  final int clientRecordVersion = 0;
  final DateTime start;
  final DateTime end;
  final int startZoneOffsetSeconds;
  final int endZoneOffsetSeconds;
}

String _uuidV4() {
  final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
