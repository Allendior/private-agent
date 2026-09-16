import 'package:flutter/services.dart';

import 'job_poller.dart';

/// Executes allowlisted companion jobs. Platform work stays on the method channel.
class JobExecutor {
  JobExecutor({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.allendior.private_agent_companion/jobs');

  final MethodChannel _channel;

  Future<JobExecutionResult> execute(
    String jobId,
    List<Map<String, dynamic>> actions,
  ) async {
    Map<String, String>? screen;
    final wantsScreen = actions.any(
      (action) => action['type'] == 'read_current_screen',
    );
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
          final failed = await _invoke(
            jobId,
            'read_current_screen',
            onSuccess: (raw) {
              if (raw is! Map) return 'INVALID_SCREEN';
              final package = raw['package'];
              if (package is! String || package.isEmpty)
                return 'INVALID_SCREEN';
              screen = {'package': package};
              return null;
            },
          );
          if (failed != null) return failed;
        } else if (type == 'tap_label') {
          final label = action['label'];
          if (label is! String || label.isEmpty) {
            return JobExecutionResult(
              jobId: jobId,
              status: 'error',
              detail: 'invalid label',
            );
          }
          final failed = await _invoke(
            jobId,
            'tap_label',
            arguments: {'label': label},
          );
          if (failed != null) return failed;
        } else if (type == 'tap_xy') {
          final x = action['x'];
          final y = action['y'];
          if (x is! int || y is! int) {
            return JobExecutionResult(
              jobId: jobId,
              status: 'error',
              detail: 'invalid coordinates',
            );
          }
          final failed = await _invoke(
            jobId,
            'tap_xy',
            arguments: {'x': x, 'y': y},
          );
          if (failed != null) return failed;
        } else if (type == 'press_back' || type == 'press_home') {
          final failed = await _invoke(jobId, type);
          if (failed != null) return failed;
        } else if (type == 'type_text') {
          final text = action['text'];
          if (text is! String || text.isEmpty) {
            return JobExecutionResult(
              jobId: jobId,
              status: 'error',
              detail: 'invalid text',
            );
          }
          final failed = await _invoke(
            jobId,
            'type_text',
            arguments: {'text': text},
          );
          if (failed != null) return failed;
        } else if (type == 'set_alarm') {
          final hour = action['hour'];
          final minute = action['minute'];
          final label = action['label'];
          if (hour is! int ||
              minute is! int ||
              label is! String ||
              hour < 0 ||
              hour > 23 ||
              minute < 0 ||
              minute > 59 ||
              label.trim().isEmpty ||
              label.length > 80 ||
              label.contains('\n')) {
            return JobExecutionResult(
              jobId: jobId,
              status: 'error',
              detail: 'invalid alarm',
            );
          }
          final failed = await _invoke(
            jobId,
            'set_alarm',
            arguments: {'hour': hour, 'minute': minute, 'label': label},
          );
          if (failed != null) return failed;
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

  Future<JobExecutionResult?> _invoke(
    String jobId,
    String method, {
    Map<String, Object>? arguments,
    String? Function(dynamic raw)? onSuccess,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>(method, arguments);
      final error = onSuccess?.call(raw);
      if (error != null) {
        return JobExecutionResult(jobId: jobId, status: 'error', detail: error);
      }
      return null;
    } on PlatformException catch (e) {
      return JobExecutionResult(jobId: jobId, status: 'error', detail: e.code);
    }
  }
}
