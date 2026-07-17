@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_bridge/health.dart';

void main() {
  test('README workout matrix exactly matches the Dart platform validators', () {
    final readme = File('README.md').readAsStringSync();
    final sectionStart = readme.indexOf('## Workout Types');
    final sectionEnd = readme.indexOf('\n## License', sectionStart);
    expect(sectionStart, isNonNegative);
    expect(sectionEnd, greaterThan(sectionStart));

    final rows = <String, _SupportRow>{};
    final rowPattern = RegExp(r'^\|\s*([A-Z][A-Z0-9_]*)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|$');
    for (final line in readme.substring(sectionStart, sectionEnd).split('\n')) {
      final match = rowPattern.firstMatch(line);
      if (match == null) continue;
      final name = match.group(1)!;
      expect(rows, isNot(contains(name)), reason: 'duplicate README workout row: $name');
      rows[name] = _SupportRow(
        ios: match.group(2)!.trim(),
        android: match.group(3)!.trim(),
        comment: match.group(4)!.trim(),
      );
    }

    final enumNames = HealthWorkoutActivityType.values.map((type) => type.name).toSet();
    expect(rows.keys.toSet(), enumNames);

    for (final type in HealthWorkoutActivityType.values) {
      final row = rows[type.name]!;
      expect(
        row.ios,
        healthWorkoutActivityTypesIOS.contains(type) ? 'yes' : isEmpty,
        reason: '${type.name} iOS support drifted',
      );
      expect(
        row.android,
        healthWorkoutActivityTypesAndroid.contains(type) ? 'yes' : isEmpty,
        reason: '${type.name} Android support drifted',
      );
    }

    expect(rows[HealthWorkoutActivityType.UNDERWATER_DIVING.name]!.comment, contains('iOS 17+'));
  });

  test('README documents generic per-type snapshots and honest iOS read state', () {
    final readme = File('README.md').readAsStringSync();
    final normalized = readme.replaceAll(RegExp(r'\s+'), ' ');

    expect(normalized, contains('accepts any nonempty, duplicate-free list of `HealthDataType` values'));
    expect(normalized, contains('mapped iOS reads as `requestedOrUnknown`'));
    expect(normalized, contains('unmapped platform types as `unsupported`'));
    expect(normalized, isNot(contains('only accepts `WORKOUT` and `ACTIVE_ENERGY_BURNED`')));
  });
}

final class _SupportRow {
  const _SupportRow({required this.ios, required this.android, required this.comment});

  final String ios;
  final String android;
  final String comment;
}
