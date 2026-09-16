import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/transport/job_executor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.allendior.private_agent_companion/jobs');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('read_current_screen reports foreground package', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'read_current_screen');
          return {'package': 'com.google.android.youtube'};
        });

    final result = await JobExecutor().execute('job-1', [
      {'type': 'read_current_screen'},
    ]);

    expect(result.status, 'ok');
    expect(result.screen, {'package': 'com.google.android.youtube'});
    expect(result.toJson()['screen']['package'], 'com.google.android.youtube');
  });

  test('read_current_screen fails closed without usage access', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'USAGE_ACCESS_REQUIRED');
        });

    final result = await JobExecutor().execute('job-1', [
      {'type': 'read_current_screen'},
    ]);

    expect(result.status, 'error');
    expect(result.detail, 'USAGE_ACCESS_REQUIRED');
    expect(result.screen, isNull);
  });

  test('tap_label invokes the platform channel', () async {
    String? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          seen = call.method;
          expect(call.arguments, {'label': 'Search'});
          return null;
        });

    final result = await JobExecutor().execute('job-2', [
      {'type': 'tap_label', 'label': 'Search'},
    ]);

    expect(result.status, 'ok');
    expect(seen, 'tap_label');
  });

  test('tap_label fails closed without accessibility', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'ACCESSIBILITY_REQUIRED');
        });

    final result = await JobExecutor().execute('job-3', [
      {'type': 'tap_label', 'label': 'Search'},
    ]);

    expect(result.status, 'error');
    expect(result.detail, 'ACCESSIBILITY_REQUIRED');
  });

  test(
    'set_alarm invokes the native alarm bridge with typed arguments',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'set_alarm');
            expect(call.arguments, {
              'hour': 6,
              'minute': 30,
              'label': 'Doraemon wake-up',
            });
            return {'scheduled': true};
          });

      final result = await JobExecutor().execute('job-alarm', [
        {
          'type': 'set_alarm',
          'hour': 6,
          'minute': 30,
          'label': 'Doraemon wake-up',
        },
      ]);

      expect(result.status, 'ok');
    },
  );

  test(
    'set_alarm rejects invalid typed arguments before native execution',
    () async {
      var nativeCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeCalled = true;
            return null;
          });

      final result = await JobExecutor().execute('job-alarm', [
        {'type': 'set_alarm', 'hour': 24, 'minute': 30, 'label': 'Wake up'},
      ]);

      expect(result.status, 'error');
      expect(result.detail, 'invalid alarm');
      expect(nativeCalled, isFalse);
    },
  );
}
