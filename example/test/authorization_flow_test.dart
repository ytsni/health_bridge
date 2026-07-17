import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_bridge/health.dart';
import 'package:health_bridge_example/authorization_flow.dart';

void main() {
  test(
    'every example authorization request is routed through the honest helper',
    () {
      final scriptDirectory = File.fromUri(Platform.script).parent;
      final candidates = [
        File('${scriptDirectory.parent.path}/lib/main.dart'),
        File('example/lib/main.dart'),
        File('lib/main.dart'),
      ];
      final sourceFile = candidates.firstWhere(
        (candidate) =>
            candidate.existsSync() &&
            candidate.readAsStringSync().contains('class HealthAppState'),
      );
      final source = sourceFile.readAsStringSync();
      final requestCount = source.split('.requestAuthorization(').length - 1;
      final helperCount =
          source.split('requestAndRecheckAuthorization(').length - 1;
      final precheckCount =
          source.split('precheck: () => health.hasPermissions').length - 1;

      if (requestCount != 3) {
        fail(
          'expected 3 requestAuthorization calls, found $requestCount; '
          'read ${sourceFile.absolute.path} from ${Directory.current.path}; '
          'source bytes ${source.length}',
        );
      }
      expect(helperCount, requestCount);
      expect(precheckCount, requestCount);
      expect(source, isNot(contains('= await health.requestAuthorization(')));
      expect(
        source.split('getAuthorizationSnapshot(').length - 1,
        greaterThanOrEqualTo(2),
      );
      expect(source, contains(r'${requestResult.readState.name}'));
      expect(
        source,
        isNot(contains(r'${HealthAuthorizationState.requestedOrUnknown.name}')),
      );
      expect(source, isNot(contains('Authorization not granted')));
      expect(source, contains('Steps read cannot be attempted'));
    },
  );

  test(
    'Android uses the exact recheck instead of request completion',
    () async {
      var recheckCount = 0;

      final result = await requestAndRecheckAuthorization(
        exactReadStateAvailable: true,
        precheck: () async => false,
        request: () async => true,
        recheck: () async {
          recheckCount += 1;
          return false;
        },
      );

      expect(result.requestCompleted, isTrue);
      expect(result.exactGranted, isFalse);
      expect(result.readState, HealthAuthorizationState.denied);
      expect(result.canAttemptAccess, isFalse);
      expect(recheckCount, 1);
    },
  );

  test(
    'Android rechecks even when the request callback reports failure',
    () async {
      final result = await requestAndRecheckAuthorization(
        exactReadStateAvailable: true,
        precheck: () async => false,
        request: () async => false,
        recheck: () async => true,
      );

      expect(result.requestCompleted, isFalse);
      expect(result.exactGranted, isTrue);
      expect(result.readState, HealthAuthorizationState.authorized);
      expect(result.canAttemptAccess, isTrue);
    },
  );

  test(
    'iOS keeps read authorization unknown and does not invent an exact recheck',
    () async {
      var rechecked = false;

      final result = await requestAndRecheckAuthorization(
        exactReadStateAvailable: false,
        precheck: () async => false,
        request: () async => true,
        recheck: () async {
          rechecked = true;
          return true;
        },
      );

      expect(result.requestCompleted, isTrue);
      expect(result.exactGranted, isNull);
      expect(result.readState, HealthAuthorizationState.requestedOrUnknown);
      expect(result.canAttemptAccess, isTrue);
      expect(result.summary, contains('requestedOrUnknown'));
      expect(result.summary, isNot(contains('granted')));
      expect(rechecked, isFalse);
    },
  );

  test(
    'iOS request failure remains separate from unknowable read state',
    () async {
      final result = await requestAndRecheckAuthorization(
        exactReadStateAvailable: false,
        precheck: () async => false,
        request: () async => false,
        recheck: () async => true,
      );

      expect(result.requestCompleted, isFalse);
      expect(result.readState, HealthAuthorizationState.requestedOrUnknown);
      expect(result.canAttemptAccess, isFalse);
      expect(result.summary, contains('request failed'));
    },
  );

  test('precheck failure does not claim that no request was needed', () async {
    var requestCalled = false;
    var recheckCalled = false;

    final result = await requestAndRecheckAuthorization(
      exactReadStateAvailable: true,
      precheck: () async => throw StateError('precheck failed'),
      request: () async {
        requestCalled = true;
        return true;
      },
      recheck: () async {
        recheckCalled = true;
        return true;
      },
    );

    expect(result.precheckError.toString(), contains('precheck failed'));
    expect(result.requestAttempted, isFalse);
    expect(result.requestCompleted, isFalse);
    expect(result.canAttemptAccess, isFalse);
    expect(result.summary, contains('precheck failed'));
    expect(result.summary, isNot(contains('No platform request was needed')));
    expect(requestCalled, isFalse);
    expect(recheckCalled, isFalse);
  });

  test(
    'platform request exception is reported separately from precheck',
    () async {
      var recheckCalled = false;

      final result = await requestAndRecheckAuthorization(
        exactReadStateAvailable: true,
        precheck: () async => false,
        request: () async => throw StateError('request crashed'),
        recheck: () async {
          recheckCalled = true;
          return true;
        },
      );

      expect(result.precheckError, isNull);
      expect(result.requestAttempted, isTrue);
      expect(result.requestCompleted, isFalse);
      expect(result.requestError.toString(), contains('request crashed'));
      expect(result.recheckError, isNull);
      expect(result.canAttemptAccess, isFalse);
      expect(result.summary, contains('request failed'));
      expect(recheckCalled, isFalse);
    },
  );

  test(
    'Android recheck failure preserves request completion without inferring access',
    () async {
      final result = await requestAndRecheckAuthorization(
        exactReadStateAvailable: true,
        precheck: () async => false,
        request: () async => true,
        recheck: () async => throw StateError('recheck failed'),
      );

      expect(result.requestAttempted, isTrue);
      expect(result.requestCompleted, isTrue);
      expect(result.recheckError.toString(), contains('recheck failed'));
      expect(result.exactGranted, isNull);
      expect(result.readState, HealthAuthorizationState.unavailable);
      expect(result.canAttemptAccess, isFalse);
      expect(result.summary, contains('request completed'));
      expect(result.summary, contains('recheck unavailable'));
    },
  );

  group('authorization follow-up diagnostics', () {
    test(
      'exact snapshot failure preserves a completed platform request',
      () async {
        var historyRequested = false;
        var backgroundRequested = false;

        final result = await runAuthorizationFollowUps<String>(
          requestCompleted: true,
          loadExactSnapshot: () async => throw StateError('snapshot failed'),
          requestHistory: () async => historyRequested = true,
          requestBackground: () async => backgroundRequested = true,
        );

        expect(result.requestCompleted, isTrue);
        expect(result.exactSnapshot, isNull);
        expect(result.failures.map((failure) => failure.operation), [
          'exact snapshot',
        ]);
        expect(
          result.failures.single.error.toString(),
          contains('snapshot failed'),
        );
        expect(historyRequested, isTrue);
        expect(backgroundRequested, isTrue);
      },
    );

    test('history failure preserves a completed platform request', () async {
      var backgroundRequested = false;

      final result = await runAuthorizationFollowUps<String>(
        requestCompleted: true,
        loadExactSnapshot: () async => 'snapshot',
        requestHistory: () async => throw StateError('history failed'),
        requestBackground: () async => backgroundRequested = true,
      );

      expect(result.requestCompleted, isTrue);
      expect(result.exactSnapshot, 'snapshot');
      expect(result.failures.map((failure) => failure.operation), [
        'history authorization',
      ]);
      expect(
        result.failures.single.error.toString(),
        contains('history failed'),
      );
      expect(backgroundRequested, isTrue);
    });

    test('background failure preserves a completed platform request', () async {
      final result = await runAuthorizationFollowUps<String>(
        requestCompleted: true,
        loadExactSnapshot: () async => 'snapshot',
        requestHistory: () async {},
        requestBackground: () async => throw StateError('background failed'),
      );

      expect(result.requestCompleted, isTrue);
      expect(result.exactSnapshot, 'snapshot');
      expect(result.failures.map((failure) => failure.operation), [
        'background authorization',
      ]);
      expect(
        result.failures.single.error.toString(),
        contains('background failed'),
      );
    });
  });
}
