part of '../health.dart';

/// The source-scoped availability of one body-mass record.
enum HealthBodyMassLookupStatus { present, absent, unavailable }

/// A typed response for an exact, app-owned body-mass lookup.
final class HealthBodyMassLookupResult {
  factory HealthBodyMassLookupResult({
    required HealthBodyMassLookupStatus status,
    String? recordId,
    String? platformCode,
  }) {
    _validateOptionalNonblankValue(recordId, 'recordId');
    _validateOptionalNonblankValue(platformCode, 'platformCode');
    if ((status == HealthBodyMassLookupStatus.present) != (recordId != null)) {
      throw const FormatException('recordId must exist only for a present body-mass lookup');
    }
    return HealthBodyMassLookupResult._(status: status, recordId: recordId, platformCode: platformCode);
  }

  const HealthBodyMassLookupResult._({required this.status, this.recordId, this.platformCode});

  final HealthBodyMassLookupStatus status;
  final String? recordId;
  final String? platformCode;

  factory HealthBodyMassLookupResult.fromMethodChannel(Object? value) {
    final map = _strictStringMap(value, 'HealthBodyMassLookupResult');
    const requiredKeys = <String>{'status', 'recordId', 'platformCode'};
    if (map.length != requiredKeys.length || !map.keys.toSet().containsAll(requiredKeys)) {
      throw const FormatException('body-mass lookup response must contain exactly status, recordId, and platformCode');
    }
    return HealthBodyMassLookupResult(
      status: _enumByName(HealthBodyMassLookupStatus.values, map['status'], 'status'),
      recordId: _optionalNonblankString(map, 'recordId'),
      platformCode: _optionalNonblankString(map, 'platformCode'),
    );
  }
}
