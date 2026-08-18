import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../pairing/pairing_controller.dart';
import '../protocol/status_protocol.dart';
import '../protocol/strict_json.dart';
import 'status_client.dart';

const _requestDomain = 'private-agent/status-request/v1\n';
const _responseDomain = 'private-agent/status-response/v1\n';
const _jobDomain = 'private-agent/job-request/v1\n';
const _jobPollKind = 'device.job.poll';
const _jobResultKind = 'device.job.result';

/// One queued job received from the host.
class QueuedJob {
  const QueuedJob({required this.jobId, required this.actions});
  final String jobId;
  final List<Map<String, dynamic>> actions;
}

/// Result of executing a job on the device.
class JobExecutionResult {
  const JobExecutionResult({required this.jobId, required this.status, this.detail});
  final String jobId;
  final String status; // "ok" or "error"
  final String? detail;

  Map<String, dynamic> toJson() => {
    'status': status,
    if (detail != null) 'detail': detail,
  };
}

/// Polls the host for pending jobs, executes them, and reports results.
///
/// Runs only while the app is in the foreground. The poll interval is
/// intentionally short (15s) for responsiveness but can be tuned.
class JobPoller {
  JobPoller({
    required PairingController pairing,
    required StatusHttpTransport transport,
    Duration interval = const Duration(seconds: 15),
  })  : _pairing = pairing,
        _transport = transport,
        _interval = interval;

  final PairingController _pairing;
  final StatusHttpTransport _transport;
  final Duration _interval;
  void Function(JobExecutionResult)? onJobExecuted;

  Timer? _timer;
  bool _polling = false;
  static const _platform = MethodChannel('com.allendior.private_agent_companion/jobs');

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> pollOnce() => _poll();

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final record = await _pairing.record();
      if (record == null) return;

      // Build a signed job poll request
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final requestId = _generateRequestId();
      final payload = <String, dynamic>{
        'version': 1,
        'kind': _jobPollKind,
        'request_id': requestId,
        'device_id': record.deviceId,
        'activation_id': '',
        'created_at': now,
        'expires_at': now + 60,
      };
      final envelope = {
        'payload': payload,
        'signature': _sign(payload, record.sharedKey, _requestDomain),
      };

      // POST to /v1/jobs
      final jobsEndpoint = record.endpoint.replaceAll('/v1/status', '/v1/jobs');
      final response = await _transport.post(
        Uri.parse(jobsEndpoint),
        jsonEncode(envelope),
      );

      if (response.statusCode != 200) {
        debugPrint('[job-poller] HTTP ${response.statusCode} from $jobsEndpoint');
        return;
      }

      // Parse the response — it contains jobs[] and results[]
      final decoded = StrictJson.decode(response.body);
      if (decoded is! Map<String, dynamic>) return;
      final respPayload = decoded['payload'];
      if (respPayload is! Map<String, dynamic>) return;

      // Verify the response signature
      final respSignature = decoded['signature'];
      if (respSignature is! String) return;
      final expectedSig = _sign(respPayload, record.sharedKey, _responseDomain);
      if (respSignature != expectedSig) {
        debugPrint('[job-poller] response signature mismatch');
        return;
      }

      final jobs = respPayload['jobs'];
      if (jobs is! List) return;
      debugPrint('[job-poller] received ${jobs.length} jobs');

      // Execute each job
      for (final jobEnvelope in jobs) {
        if (jobEnvelope is! Map<String, dynamic>) continue;
        final jobPayload = jobEnvelope['payload'];
        final jobSig = jobEnvelope['signature'];
        if (jobPayload is! Map<String, dynamic> || jobSig is! String) continue;

        final jobId = jobPayload['job_id'];
        if (jobId is! String) continue;

        // Verify host job envelope with job-request domain before execution.
        final expectedJobSig = _sign(jobPayload, record.sharedKey, _jobDomain);
        if (jobSig != expectedJobSig) {
          debugPrint('[job-poller] job signature mismatch for $jobId');
          continue;
        }

        final actions = jobPayload['actions'];
        if (actions is! List) continue;

        final typedActions = <Map<String, dynamic>>[];
        for (final a in actions) {
          if (a is Map<String, dynamic>) {
            typedActions.add(a);
          }
        }

        final result = await _executeJob(jobId, typedActions);
        onJobExecuted?.call(result);
        await _reportResult(record, requestId, jobId, result);
      }
    } catch (e, stack) {
      // Log errors for debugging — don't crash the poller
      debugPrint('[job-poller] error: $e');
      debugPrint('[job-poller] stack: $stack');
    } finally {
      _polling = false;
    }
  }

  Future<JobExecutionResult> _executeJob(String jobId, List<Map<String, dynamic>> actions) async {
    try {
      for (final action in actions) {
        final type = action['type'];
        if (type == 'open_app') {
          final package = action['package'];
          if (package is! String) {
            return JobExecutionResult(jobId: jobId, status: 'error', detail: 'invalid package');
          }
          await _platform.invokeMethod('open_app', {'package': package});
        } else if (type == 'read_current_screen' || type == 'device.status.get') {
          // Read-only actions — acknowledge without side effects
          debugPrint('[job-poller] read-only action: $type');
        } else {
          return JobExecutionResult(jobId: jobId, status: 'error', detail: 'unknown action: $type');
        }
      }
      return JobExecutionResult(jobId: jobId, status: 'ok');
    } catch (e) {
      return JobExecutionResult(jobId: jobId, status: 'error', detail: e.toString());
    }
  }

  Future<void> _reportResult(PairingRecord record, String requestId, String jobId, JobExecutionResult result) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final newRequestId = _generateRequestId();
    final payload = <String, dynamic>{
      'version': 1,
      'kind': _jobResultKind,
      'request_id': newRequestId,
      'device_id': record.deviceId,
      'activation_id': '',
      'job_id': jobId,
      'result': result.toJson(),
      'created_at': now,
      'expires_at': now + 60,
    };
    final envelope = {
      'payload': payload,
      'signature': _sign(payload, record.sharedKey, _requestDomain),
    };

    final resultsEndpoint = record.endpoint.replaceAll('/v1/status', '/v1/results');
    await _transport.post(Uri.parse(resultsEndpoint), jsonEncode(envelope));
  }

  String _generateRequestId() {
    final random = DateTime.now().millisecondsSinceEpoch;
    final micros = DateTime.now().microsecond;
    final bytes = List<int>.generate(16, (i) {
      final seed = (random + i * 31 + micros) & 0xFF;
      return seed;
    });
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _sign(Map<String, dynamic> payload, String key, String domain) {
    final keyBytes = base64Url.decode(base64Url.normalize(key));
    final payloadJson = _canonicalJson(payload);
    final digest = Hmac(sha256, keyBytes).convert(utf8.encode(domain + payloadJson)).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  String _canonicalJson(Object? value) {
    return jsonEncode(_canonicalizeValue(value));
  }

  Object? _canonicalizeValue(Object? value) {
    if (value is Map) {
      final sorted = SplayTreeMap<String, Object?>();
      for (final entry in value.entries) {
        if (entry.key is! String) throw const FormatException('non-string JSON key');
        sorted[entry.key as String] = _canonicalizeValue(entry.value);
      }
      return sorted;
    }
    if (value is List) return value.map(_canonicalizeValue).toList(growable: false);
    return value;
  }
}
