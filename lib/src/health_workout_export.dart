part of '../health.dart';

final RegExp _opaqueUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

void _validateWorkoutIdentity(String value, String name) {
  if (!_opaqueUuid.hasMatch(value.trim())) {
    throw ArgumentError.value(value, name, 'must be a UUID string');
  }
}

void _validateWorkoutRange(DateTime start, DateTime end) {
  if (!end.isAfter(start)) {
    throw ArgumentError('end must be after start');
  }
}

void _validateZoneOffsetSeconds(int value, String name) {
  if (value < -64800 || value > 64800) {
    throw ArgumentError.value(value, name, 'must be between -64800 and 64800 seconds');
  }
}

enum HealthRecordingProvenance { activelyRecorded, manualEntry }

enum HealthRecordingDevice { phone, watch }

enum HealthWorkoutWriteStatus {
  written,
  alreadyPresent,
  writtenWithoutEnergy,
  blockedWorkoutPermission,
  verificationRequired,
  inconsistentNativeState,
  transientFailure,
  invalidInput,
  unavailable,
}

enum HealthEnergyWriteStatus {
  notExpected,
  written,
  alreadyPresent,
  omittedPermission,
  absent,
  notSubmitted,
  verificationRequired,
}

enum HealthSubmissionCertainty { notSubmitted, mayHaveSubmitted, submitted }

enum HealthRecordLookupStatus { present, absent, unavailable, notExpected }

enum HealthWorkoutLookupStatus { present, workoutOnly, absent, unavailable, inconsistent }

enum HealthAuthorizationState { authorized, denied, notDetermined, requestedOrUnknown, unavailable, unsupported }

/// Platform-reported read and write authorization state for one health type.
final class HealthTypeAuthorization {
  const HealthTypeAuthorization({required this.type, required this.read, required this.write});

  final HealthDataType type;
  final HealthAuthorizationState read;
  final HealthAuthorizationState write;

  @override
  bool operator ==(Object other) =>
      other is HealthTypeAuthorization && type == other.type && read == other.read && write == other.write;

  @override
  int get hashCode => Object.hash(type, read, write);
}

/// An immutable exact authorization snapshot for requested health data types.
final class HealthAuthorizationSnapshot {
  factory HealthAuthorizationSnapshot({
    required bool available,
    required List<HealthTypeAuthorization> types,
    String? platformCode,
  }) {
    _validateOptionalNonblankValue(platformCode, 'platformCode');
    final copiedTypes = List<HealthTypeAuthorization>.of(types);
    if (copiedTypes.isEmpty) {
      throw const FormatException('authorization types must be nonempty');
    }
    if (copiedTypes.map((entry) => entry.type).toSet().length != copiedTypes.length) {
      throw const FormatException('authorization types must be unique');
    }
    copiedTypes.sort((first, second) => first.type.index.compareTo(second.type.index));
    final canonicalTypes = List<HealthTypeAuthorization>.unmodifiable(copiedTypes);

    final hasUnavailableState = canonicalTypes.any(
      (entry) =>
          entry.read == HealthAuthorizationState.unavailable || entry.write == HealthAuthorizationState.unavailable,
    );
    final allStatesUnavailable = canonicalTypes.every(
      (entry) =>
          entry.read == HealthAuthorizationState.unavailable && entry.write == HealthAuthorizationState.unavailable,
    );
    if (available && hasUnavailableState) {
      throw const FormatException('available snapshots require non-unavailable component states');
    }
    if (!available && !allStatesUnavailable) {
      throw const FormatException('unavailable snapshots require every component state unavailable');
    }

    return HealthAuthorizationSnapshot._(available: available, types: canonicalTypes, platformCode: platformCode);
  }

  const HealthAuthorizationSnapshot._({required this.available, required this.types, this.platformCode});

  final bool available;
  final List<HealthTypeAuthorization> types;
  final String? platformCode;

  HealthTypeAuthorization forType(HealthDataType type) => types.singleWhere((entry) => entry.type == type);

  factory HealthAuthorizationSnapshot.fromMethodChannel(Object? value, Set<HealthDataType> requestedTypes) {
    final map = _strictStringMap(value, 'HealthAuthorizationSnapshot');
    final rawTypes = map['types'];
    if (rawTypes is! List) {
      throw const FormatException('types must be a list');
    }
    final decoded = rawTypes
        .map((raw) {
          final entry = _strictStringMap(raw, 'HealthTypeAuthorization');
          return HealthTypeAuthorization(
            type: _enumByName(HealthDataType.values, entry['type'], 'type'),
            read: _enumByName(HealthAuthorizationState.values, entry['read'], 'read'),
            write: _enumByName(HealthAuthorizationState.values, entry['write'], 'write'),
          );
        })
        .toList(growable: false);
    final actualTypes = decoded.map((entry) => entry.type).toSet();
    if (actualTypes.length != decoded.length ||
        !actualTypes.containsAll(requestedTypes) ||
        !requestedTypes.containsAll(actualTypes)) {
      throw const FormatException('authorization types must exactly match request');
    }
    return HealthAuthorizationSnapshot(
      available: _requiredBool(map, 'available'),
      types: decoded,
      platformCode: _optionalNonblankString(map, 'platformCode'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HealthAuthorizationSnapshot &&
      available == other.available &&
      listEquals(types, other.types) &&
      platformCode == other.platformCode;

  @override
  int get hashCode => Object.hash(available, Object.hashAll(types), platformCode);
}

/// The complete native outcome of one workout export attempt.
final class HealthWorkoutWriteResult {
  factory HealthWorkoutWriteResult({
    required HealthWorkoutWriteStatus status,
    required HealthEnergyWriteStatus energyStatus,
    required bool retryable,
    required HealthSubmissionCertainty submissionCertainty,
    String? workoutRecordId,
    String? energyRecordId,
    String? platformCode,
  }) {
    _validateOptionalNonblankValue(workoutRecordId, 'workoutRecordId');
    _validateOptionalNonblankValue(energyRecordId, 'energyRecordId');
    _validateOptionalNonblankValue(platformCode, 'platformCode');
    final result = HealthWorkoutWriteResult._(
      status: status,
      workoutRecordId: workoutRecordId,
      energyRecordId: energyRecordId,
      energyStatus: energyStatus,
      retryable: retryable,
      submissionCertainty: submissionCertainty,
      platformCode: platformCode,
    );
    result._validateCombination();
    return result;
  }

  const HealthWorkoutWriteResult._({
    required this.status,
    required this.energyStatus,
    required this.retryable,
    required this.submissionCertainty,
    this.workoutRecordId,
    this.energyRecordId,
    this.platformCode,
  });

  final HealthWorkoutWriteStatus status;
  final String? workoutRecordId;
  final String? energyRecordId;
  final HealthEnergyWriteStatus energyStatus;
  final bool retryable;
  final HealthSubmissionCertainty submissionCertainty;
  final String? platformCode;

  factory HealthWorkoutWriteResult.fromMethodChannel(Object? value) {
    final map = _strictStringMap(value, 'HealthWorkoutWriteResult');
    return HealthWorkoutWriteResult(
      status: _enumByName(HealthWorkoutWriteStatus.values, map['status'], 'status'),
      workoutRecordId: _optionalNonblankString(map, 'workoutRecordId'),
      energyRecordId: _optionalNonblankString(map, 'energyRecordId'),
      energyStatus: _enumByName(HealthEnergyWriteStatus.values, map['energyStatus'], 'energyStatus'),
      retryable: _requiredBool(map, 'retryable'),
      submissionCertainty: _enumByName(
        HealthSubmissionCertainty.values,
        map['submissionCertainty'],
        'submissionCertainty',
      ),
      platformCode: _optionalNonblankString(map, 'platformCode'),
    );
  }

  void _validateCombination() {
    final hasWorkoutId = workoutRecordId != null;
    final hasEnergyId = energyRecordId != null;

    if (!_isAllowedWriteStatusPair(status, energyStatus)) {
      throw FormatException('${status.name} cannot pair with ${energyStatus.name}');
    }

    switch (energyStatus) {
      case HealthEnergyWriteStatus.written:
      case HealthEnergyWriteStatus.alreadyPresent:
        if (!hasEnergyId) {
          throw const FormatException('energyRecordId is required for present energy');
        }
      case HealthEnergyWriteStatus.notExpected:
      case HealthEnergyWriteStatus.omittedPermission:
      case HealthEnergyWriteStatus.absent:
      case HealthEnergyWriteStatus.notSubmitted:
      case HealthEnergyWriteStatus.verificationRequired:
        if (hasEnergyId) {
          throw const FormatException('energyRecordId is forbidden when energy is not confirmed present');
        }
    }

    switch (status) {
      case HealthWorkoutWriteStatus.written:
      case HealthWorkoutWriteStatus.writtenWithoutEnergy:
      case HealthWorkoutWriteStatus.alreadyPresent:
        if (!hasWorkoutId) {
          throw FormatException('workoutRecordId is required for ${status.name}');
        }
        if (submissionCertainty != HealthSubmissionCertainty.submitted) {
          throw FormatException('${status.name} must be submitted');
        }
      case HealthWorkoutWriteStatus.blockedWorkoutPermission:
      case HealthWorkoutWriteStatus.invalidInput:
      case HealthWorkoutWriteStatus.unavailable:
        if (hasWorkoutId || hasEnergyId) {
          throw FormatException('${status.name} cannot contain record IDs');
        }
        if (submissionCertainty != HealthSubmissionCertainty.notSubmitted) {
          throw FormatException('${status.name} must be notSubmitted');
        }
      case HealthWorkoutWriteStatus.verificationRequired:
        if (hasWorkoutId || hasEnergyId) {
          throw const FormatException('verificationRequired cannot contain confirmed record IDs');
        }
        if (submissionCertainty != HealthSubmissionCertainty.mayHaveSubmitted) {
          throw const FormatException('verificationRequired must be mayHaveSubmitted');
        }
      case HealthWorkoutWriteStatus.inconsistentNativeState:
        if (hasWorkoutId || !hasEnergyId) {
          throw const FormatException('inconsistentNativeState requires energy without a workout');
        }
        if (submissionCertainty != HealthSubmissionCertainty.submitted) {
          throw const FormatException('inconsistentNativeState must be submitted');
        }
      case HealthWorkoutWriteStatus.transientFailure:
        if (hasWorkoutId || hasEnergyId) {
          throw const FormatException('transientFailure cannot contain record IDs');
        }
        if (submissionCertainty != HealthSubmissionCertainty.notSubmitted) {
          throw const FormatException('transientFailure must be notSubmitted');
        }
    }
  }
}

bool _isAllowedWriteStatusPair(HealthWorkoutWriteStatus status, HealthEnergyWriteStatus energyStatus) =>
    switch (status) {
      HealthWorkoutWriteStatus.written => switch (energyStatus) {
        HealthEnergyWriteStatus.notExpected || HealthEnergyWriteStatus.written => true,
        HealthEnergyWriteStatus.alreadyPresent ||
        HealthEnergyWriteStatus.omittedPermission ||
        HealthEnergyWriteStatus.absent ||
        HealthEnergyWriteStatus.notSubmitted ||
        HealthEnergyWriteStatus.verificationRequired => false,
      },
      HealthWorkoutWriteStatus.alreadyPresent => switch (energyStatus) {
        HealthEnergyWriteStatus.notExpected ||
        HealthEnergyWriteStatus.alreadyPresent ||
        HealthEnergyWriteStatus.absent => true,
        HealthEnergyWriteStatus.written ||
        HealthEnergyWriteStatus.omittedPermission ||
        HealthEnergyWriteStatus.notSubmitted ||
        HealthEnergyWriteStatus.verificationRequired => false,
      },
      HealthWorkoutWriteStatus.writtenWithoutEnergy => switch (energyStatus) {
        HealthEnergyWriteStatus.omittedPermission => true,
        HealthEnergyWriteStatus.notExpected ||
        HealthEnergyWriteStatus.written ||
        HealthEnergyWriteStatus.alreadyPresent ||
        HealthEnergyWriteStatus.absent ||
        HealthEnergyWriteStatus.notSubmitted ||
        HealthEnergyWriteStatus.verificationRequired => false,
      },
      HealthWorkoutWriteStatus.blockedWorkoutPermission => switch (energyStatus) {
        HealthEnergyWriteStatus.notExpected || HealthEnergyWriteStatus.notSubmitted => true,
        HealthEnergyWriteStatus.written ||
        HealthEnergyWriteStatus.alreadyPresent ||
        HealthEnergyWriteStatus.omittedPermission ||
        HealthEnergyWriteStatus.absent ||
        HealthEnergyWriteStatus.verificationRequired => false,
      },
      HealthWorkoutWriteStatus.verificationRequired => switch (energyStatus) {
        HealthEnergyWriteStatus.notExpected ||
        HealthEnergyWriteStatus.omittedPermission ||
        HealthEnergyWriteStatus.verificationRequired => true,
        HealthEnergyWriteStatus.written ||
        HealthEnergyWriteStatus.alreadyPresent ||
        HealthEnergyWriteStatus.absent ||
        HealthEnergyWriteStatus.notSubmitted => false,
      },
      HealthWorkoutWriteStatus.inconsistentNativeState => switch (energyStatus) {
        HealthEnergyWriteStatus.alreadyPresent => true,
        HealthEnergyWriteStatus.notExpected ||
        HealthEnergyWriteStatus.written ||
        HealthEnergyWriteStatus.omittedPermission ||
        HealthEnergyWriteStatus.absent ||
        HealthEnergyWriteStatus.notSubmitted ||
        HealthEnergyWriteStatus.verificationRequired => false,
      },
      HealthWorkoutWriteStatus.transientFailure => switch (energyStatus) {
        HealthEnergyWriteStatus.notExpected || HealthEnergyWriteStatus.notSubmitted => true,
        HealthEnergyWriteStatus.written ||
        HealthEnergyWriteStatus.alreadyPresent ||
        HealthEnergyWriteStatus.omittedPermission ||
        HealthEnergyWriteStatus.absent ||
        HealthEnergyWriteStatus.verificationRequired => false,
      },
      HealthWorkoutWriteStatus.invalidInput => switch (energyStatus) {
        HealthEnergyWriteStatus.notExpected || HealthEnergyWriteStatus.notSubmitted => true,
        HealthEnergyWriteStatus.written ||
        HealthEnergyWriteStatus.alreadyPresent ||
        HealthEnergyWriteStatus.omittedPermission ||
        HealthEnergyWriteStatus.absent ||
        HealthEnergyWriteStatus.verificationRequired => false,
      },
      HealthWorkoutWriteStatus.unavailable => switch (energyStatus) {
        HealthEnergyWriteStatus.notExpected || HealthEnergyWriteStatus.notSubmitted => true,
        HealthEnergyWriteStatus.written ||
        HealthEnergyWriteStatus.alreadyPresent ||
        HealthEnergyWriteStatus.omittedPermission ||
        HealthEnergyWriteStatus.absent ||
        HealthEnergyWriteStatus.verificationRequired => false,
      },
    };

/// The lookup state of one independently persisted native health record.
final class HealthRecordLookup {
  factory HealthRecordLookup({required HealthRecordLookupStatus status, String? recordId}) {
    _validateOptionalNonblankValue(recordId, 'recordId');
    if ((status == HealthRecordLookupStatus.present) != (recordId != null)) {
      throw const FormatException('recordId must exist only for present lookup');
    }
    return HealthRecordLookup._(status: status, recordId: recordId);
  }

  const HealthRecordLookup._({required this.status, this.recordId});

  final HealthRecordLookupStatus status;
  final String? recordId;

  factory HealthRecordLookup.fromMethodChannel(Object? value) {
    final map = _strictStringMap(value, 'HealthRecordLookup');
    final status = _enumByName(HealthRecordLookupStatus.values, map['status'], 'status');
    final recordId = _optionalNonblankString(map, 'recordId');
    return HealthRecordLookup(status: status, recordId: recordId);
  }
}

/// A source-scoped lookup of the workout and its independent energy record.
final class HealthWorkoutLookupResult {
  factory HealthWorkoutLookupResult({
    required HealthRecordLookup workout,
    required HealthRecordLookup energy,
    required HealthWorkoutLookupStatus derivedStatus,
    String? platformCode,
  }) {
    _validateOptionalNonblankValue(platformCode, 'platformCode');
    if (workout.status == HealthRecordLookupStatus.notExpected) {
      throw const FormatException('workout lookup cannot be notExpected');
    }
    final expected = _deriveLookupStatus(workout.status, energy.status);
    if (derivedStatus != expected) {
      throw FormatException('derivedStatus ${derivedStatus.name} does not match ${expected.name}');
    }
    return HealthWorkoutLookupResult._(
      workout: workout,
      energy: energy,
      derivedStatus: derivedStatus,
      platformCode: platformCode,
    );
  }

  const HealthWorkoutLookupResult._({
    required this.workout,
    required this.energy,
    required this.derivedStatus,
    this.platformCode,
  });

  final HealthRecordLookup workout;
  final HealthRecordLookup energy;
  final HealthWorkoutLookupStatus derivedStatus;
  final String? platformCode;

  factory HealthWorkoutLookupResult.fromMethodChannel(Object? value) {
    final map = _strictStringMap(value, 'HealthWorkoutLookupResult');
    final workout = HealthRecordLookup.fromMethodChannel(map['workout']);
    final energy = HealthRecordLookup.fromMethodChannel(map['energy']);
    final derived = _enumByName(HealthWorkoutLookupStatus.values, map['derivedStatus'], 'derivedStatus');
    return HealthWorkoutLookupResult(
      workout: workout,
      energy: energy,
      derivedStatus: derived,
      platformCode: _optionalNonblankString(map, 'platformCode'),
    );
  }
}

HealthWorkoutLookupStatus _deriveLookupStatus(HealthRecordLookupStatus workout, HealthRecordLookupStatus energy) =>
    switch ((workout, energy)) {
      (HealthRecordLookupStatus.unavailable, _) ||
      (_, HealthRecordLookupStatus.unavailable) => HealthWorkoutLookupStatus.unavailable,
      (HealthRecordLookupStatus.absent, HealthRecordLookupStatus.present) => HealthWorkoutLookupStatus.inconsistent,
      (HealthRecordLookupStatus.absent, HealthRecordLookupStatus.absent) ||
      (HealthRecordLookupStatus.absent, HealthRecordLookupStatus.notExpected) => HealthWorkoutLookupStatus.absent,
      (HealthRecordLookupStatus.present, HealthRecordLookupStatus.present) => HealthWorkoutLookupStatus.present,
      (HealthRecordLookupStatus.present, HealthRecordLookupStatus.absent) ||
      (HealthRecordLookupStatus.present, HealthRecordLookupStatus.notExpected) => HealthWorkoutLookupStatus.workoutOnly,
      (HealthRecordLookupStatus.notExpected, _) => throw const FormatException('workout lookup cannot be notExpected'),
    };

Map<String, Object?> _strictStringMap(Object? value, String context) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$context must be a map');
  }

  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$context keys must be strings');
    }
    result[key] = entry.value;
  }
  return result;
}

T _enumByName<T extends Enum>(List<T> values, Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field must be a string');
  }
  for (final candidate in values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  throw FormatException('Unknown $field: $value');
}

bool _requiredBool(Map<String, Object?> map, String field) {
  final value = map[field];
  if (!map.containsKey(field) || value is! bool) {
    throw FormatException('$field must be a bool');
  }
  return value;
}

String? _optionalNonblankString(Map<String, Object?> map, String field) {
  if (!map.containsKey(field) || map[field] == null) {
    return null;
  }
  final value = map[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a nonblank string when present');
  }
  return value;
}

void _validateOptionalNonblankValue(String? value, String field) {
  if (value != null && value.trim().isEmpty) {
    throw FormatException('$field must be a nonblank string when present');
  }
}
