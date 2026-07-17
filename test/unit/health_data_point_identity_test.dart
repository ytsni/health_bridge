import 'package:flutter_test/flutter_test.dart';
import 'package:health_bridge/health.dart';

void main() {
  HealthDataPoint point({String? clientRecordId = 'scale-reading-42', int? clientRecordVersion = 7}) => HealthDataPoint(
    uuid: 'native-record-id',
    clientRecordId: clientRecordId,
    clientRecordIdType: clientRecordId == null ? null : HealthClientRecordIdType.healthConnectClientRecordId,
    clientRecordVersion: clientRecordVersion,
    value: NumericHealthValue(numericValue: 80),
    type: HealthDataType.WEIGHT,
    unit: HealthDataUnit.KILOGRAM,
    dateFrom: DateTime.utc(2026, 7, 15, 12),
    dateTo: DateTime.utc(2026, 7, 15, 12),
    sourcePlatform: HealthPlatformType.googleHealthConnect,
    sourceDeviceId: 'device-id',
    sourceId: 'com.example.scale',
    sourceName: 'Example Scale',
  );

  test('JSON round trip preserves optional stable client identity', () {
    final original = point();

    final decoded = HealthDataPoint.fromJson(original.toJson());

    expect(decoded.clientRecordId, 'scale-reading-42');
    expect(decoded.clientRecordIdType, HealthClientRecordIdType.healthConnectClientRecordId);
    expect(decoded.clientRecordVersion, 7);
    expect(decoded, original);
    expect(decoded.hashCode, original.hashCode);
  });

  test('client identity remains optional for existing integrations', () {
    final original = point(clientRecordId: null, clientRecordVersion: null);
    final json = original.toJson();

    expect(json, isNot(contains('clientRecordId')));
    expect(json, isNot(contains('clientRecordIdType')));
    expect(json, isNot(contains('clientRecordVersion')));
    expect(HealthDataPoint.fromJson(json), original);
  });
}
