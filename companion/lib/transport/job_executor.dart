import 'package:flutter/services.dart';

import 'job_poller.dart';

/// Executes allowlisted companion jobs. Platform work stays on the method channel.
class JobExecutor {
  JobExecutor({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.allendior.private_agent_companion/jobs');

  final MethodChannel _channel;

  Future<JobExecutionResult> execute(
    String jobId,
    List<Map<String, dynamic>> actions,
  ) async {
    Map<String, String>? screen;
    final wantsScreen = actions.any((action) => action['type'] == 'read_current_screen');
    try {
      for (final action in actions) {
        final type = action['type'];
        if (type == 'open_app') {
          final package = action['package'];
          if (package is! String) {
            return JobExecutionResult(
              jobId: jobId,
              status: 'error',
              detail: 'invalid package',
            );
          }
          await _channel.invokeMethod('open_app', {'package': package});
          if (wantsScreen) {
            await Future<void>.delayed(const Duration(milliseconds: 800));
          }
        } else if (type == 'read_current_screen') {
          try {
            final raw = await _channel.invokeMethod<dynamic>('read_current_screen');
            if (raw is! Map) {
              return JobExecutionResult(
                jobId: jobId,
                status: 'error',
                detail: 'INVALID_SCREEN',
              );
            }
            final package = raw['package'];
            if (package is! String || package.isEmpty) {
              return JobExecutionResult(
                jobId: jobId,
                status: 'error',
                detail: 'INVALID_SCREEN',
              );
            }
            screen = {'package': package};
          } on PlatformException catch (e) {
            return JobExecutionResult(
              jobId: jobId,
              status: 'error',
              detail: e.code,
            );
          }
        } else if (type == 'device.status.get') {
          continue;
        } else {
          return JobExecutionResult(
            jobId: jobId,
            status: 'error',
            detail: 'unknown action: $type',
          );
        }
      }
      return JobExecutionResult(jobId: jobId, status: 'ok', screen: screen);
    } catch (e) {
      return JobExecutionResult(
        jobId: jobId,
        status: 'error',
        detail: e.toString(),
      );
    }
  }
}
