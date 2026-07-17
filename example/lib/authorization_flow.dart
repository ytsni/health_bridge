import 'package:health_bridge/health.dart';

final class ExampleAuthorizationResult {
  const ExampleAuthorizationResult({
    required this.requestAttempted,
    required this.requestCompleted,
    required this.exactGranted,
    required this.readState,
    this.precheckError,
    this.requestError,
    this.recheckError,
  });

  final bool requestAttempted;
  final bool requestCompleted;
  final bool? exactGranted;
  final HealthAuthorizationState readState;
  final Object? precheckError;
  final Object? requestError;
  final Object? recheckError;

  bool get canAttemptAccess {
    if (precheckError != null || requestError != null || recheckError != null) {
      return false;
    }
    final exact = exactGranted;
    if (exact != null) return exact;
    return readState == HealthAuthorizationState.requestedOrUnknown &&
        (!requestAttempted || requestCompleted);
  }

  String get requestSummary {
    if (precheckError != null) {
      return 'Authorization precheck failed; no platform request was attempted.';
    }
    if (!requestAttempted) return 'No platform request was needed.';
    if (requestError != null) {
      return 'Platform request failed before completion could be reported.';
    }
    return 'Platform request ${requestCompleted ? 'completed' : 'failed'}.';
  }

  String get summary {
    final request = requestSummary;
    if (recheckError != null) {
      return '$request Exact authorization recheck unavailable.';
    }
    final exact = exactGranted;
    if (exact != null) {
      return '$request Exact authorization ${exact ? 'authorized' : 'denied'}.';
    }
    return '$request HealthKit read authorization ${readState.name}.';
  }
}

/// Prechecks and requests generic health access without conflating any stage.
/// Android supplies an exact aggregate recheck; HealthKit deliberately keeps
/// generic read access unknown.
Future<ExampleAuthorizationResult> requestAndRecheckAuthorization({
  required bool exactReadStateAvailable,
  required Future<bool?> Function() precheck,
  required Future<bool> Function() request,
  required Future<bool?> Function() recheck,
}) async {
  bool? existingAuthorization;
  try {
    existingAuthorization = await precheck();
  } catch (error) {
    return ExampleAuthorizationResult(
      requestAttempted: false,
      requestCompleted: false,
      exactGranted: null,
      readState: HealthAuthorizationState.unavailable,
      precheckError: error,
    );
  }

  if (existingAuthorization == true) {
    return ExampleAuthorizationResult(
      requestAttempted: false,
      requestCompleted: true,
      exactGranted: exactReadStateAvailable ? true : null,
      readState: exactReadStateAvailable
          ? HealthAuthorizationState.authorized
          : HealthAuthorizationState.requestedOrUnknown,
    );
  }

  bool requestCompleted;
  try {
    requestCompleted = await request();
  } catch (error) {
    return ExampleAuthorizationResult(
      requestAttempted: true,
      requestCompleted: false,
      exactGranted: null,
      readState: HealthAuthorizationState.unavailable,
      requestError: error,
    );
  }

  if (!exactReadStateAvailable) {
    return ExampleAuthorizationResult(
      requestAttempted: true,
      requestCompleted: requestCompleted,
      exactGranted: null,
      readState: HealthAuthorizationState.requestedOrUnknown,
    );
  }

  bool exactGranted;
  try {
    exactGranted = await recheck() == true;
  } catch (error) {
    return ExampleAuthorizationResult(
      requestAttempted: true,
      requestCompleted: requestCompleted,
      exactGranted: null,
      readState: HealthAuthorizationState.unavailable,
      recheckError: error,
    );
  }

  return ExampleAuthorizationResult(
    requestAttempted: true,
    requestCompleted: requestCompleted,
    exactGranted: exactGranted,
    readState: exactGranted
        ? HealthAuthorizationState.authorized
        : HealthAuthorizationState.denied,
  );
}

final class ExampleAuthorizationFollowUpFailure {
  const ExampleAuthorizationFollowUpFailure({
    required this.operation,
    required this.error,
  });

  final String operation;
  final Object error;
}

final class ExampleAuthorizationFollowUpResult<T> {
  ExampleAuthorizationFollowUpResult({
    required this.requestCompleted,
    required this.exactSnapshot,
    required List<ExampleAuthorizationFollowUpFailure> failures,
  }) : failures = List.unmodifiable(failures);

  final bool requestCompleted;
  final T? exactSnapshot;
  final List<ExampleAuthorizationFollowUpFailure> failures;
}

/// Runs independent post-request diagnostics without rewriting whether the
/// platform authorization request itself completed.
Future<ExampleAuthorizationFollowUpResult<T>> runAuthorizationFollowUps<T>({
  required bool requestCompleted,
  required Future<T> Function() loadExactSnapshot,
  required Future<void> Function() requestHistory,
  required Future<void> Function() requestBackground,
}) async {
  final failures = <ExampleAuthorizationFollowUpFailure>[];
  T? exactSnapshot;

  try {
    exactSnapshot = await loadExactSnapshot();
  } catch (error) {
    failures.add(
      ExampleAuthorizationFollowUpFailure(
        operation: 'exact snapshot',
        error: error,
      ),
    );
  }

  if (requestCompleted) {
    try {
      await requestHistory();
    } catch (error) {
      failures.add(
        ExampleAuthorizationFollowUpFailure(
          operation: 'history authorization',
          error: error,
        ),
      );
    }

    try {
      await requestBackground();
    } catch (error) {
      failures.add(
        ExampleAuthorizationFollowUpFailure(
          operation: 'background authorization',
          error: error,
        ),
      );
    }
  }

  return ExampleAuthorizationFollowUpResult<T>(
    requestCompleted: requestCompleted,
    exactSnapshot: exactSnapshot,
    failures: failures,
  );
}
