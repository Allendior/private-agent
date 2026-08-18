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
}
