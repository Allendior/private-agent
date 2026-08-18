import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../pairing/pairing_controller.dart';
import '../protocol/status_protocol.dart';

class StatusHttpResponse {
  const StatusHttpResponse({required this.statusCode, required this.body, required this.redirected});
  final int statusCode;
  final String body;
  final bool redirected;
}

abstract class StatusHttpTransport {
  Future<StatusHttpResponse> post(Uri endpoint, String body);
}

/// Foreground-only HTTP transport. Each call creates and closes one client,
/// disables redirects and persistence, and applies bounded timeouts.
///
/// Uses plain HTTP over the LAN. The HMAC signed-envelope protocol provides
/// authentication, replay protection, and integrity — TLS is not needed
/// because the security layer is the envelope signature, not the transport.
class IoStatusHttpTransport implements StatusHttpTransport {
  const IoStatusHttpTransport();

  @override
  Future<StatusHttpResponse> post(Uri endpoint, String body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(endpoint).timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.persistentConnection = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final bodyBytes = utf8.encode(body);
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);
      final response = await request.close().timeout(const Duration(seconds: 10));
      final chunks = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        chunks.addAll(chunk);
        if (chunks.length > 65536) throw const FormatException('response too large');
      }
      return StatusHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(chunks, allowMalformed: false),
        redirected: response.isRedirect || response.redirects.isNotEmpty,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class ProbeResult {
  const ProbeResult(this.success, this.code);
  const ProbeResult.ok() : this(true, 'OK');
  final bool success;
  final String code;
}

/// Sends nothing automatically. The UI is the only production caller of
/// [probe], and invokes it only from a manual button press.
class StatusProbeController {
  StatusProbeController({
    required this._pairing,
    required this._transport,
    int Function()? nowSeconds,
    this._randomBytes,
  })  : _nowSeconds = nowSeconds ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  final PairingController _pairing;
  final StatusHttpTransport _transport;
  final int Function() _nowSeconds;
  final RandomBytes? _randomBytes;
  bool _inFlight = false;

  Future<ProbeResult> probe() async {
    if (_inFlight) return const ProbeResult(false, 'PROBE_IN_PROGRESS');
    _inFlight = true;
    try {
      final record = await _pairing.record();
      if (record == null) return const ProbeResult(false, 'NOT_PAIRED');
      final now = _nowSeconds();
      final request = StatusProtocol.buildRequest(
        deviceId: record.deviceId,
        activationId: record.activationId ?? '',
        sharedKey: record.sharedKey,
        nowSeconds: now,
        randomBytes: _randomBytes,
      );
      final response = await _transport.post(
        Uri.parse(record.endpoint),
        StatusProtocol.encodeEnvelope(request.value),
      );
      if (response.redirected || response.statusCode >= 300 && response.statusCode < 400) {
        return const ProbeResult(false, 'REDIRECT_REJECTED');
      }
      if (response.statusCode != 200) {
        print('[probe] host rejected: ${response.statusCode} body=${response.body.substring(0, response.body.length.clamp(0, 200))}');
        return const ProbeResult(false, 'HOST_REJECTED');
      }
      StatusProtocol.verifyResponse(
        body: response.body,
        sharedKey: record.sharedKey,
        expectedDeviceId: record.deviceId,
        expectedRequestId: request.requestId,
        nowSeconds: _nowSeconds(),
      );
      if (record.activationId != null) await _pairing.consumeActivation();
      return const ProbeResult.ok();
    } on TimeoutException catch (error) {
      print('[probe] timeout: $error');
      return const ProbeResult(false, 'TIMEOUT');
    } on SocketException catch (error) {
      print('[probe] socket: $error');
      return const ProbeResult(false, 'NETWORK_ERROR');
    } on HttpException catch (error) {
      print('[probe] http: $error');
      return const ProbeResult(false, 'NETWORK_ERROR');
    } on FormatException catch (error) {
      print('[probe] format: $error');
      return const ProbeResult(false, 'INVALID_RESPONSE');
    } catch (error) {
      print('[probe] unexpected ${error.runtimeType}: $error');
      return const ProbeResult(false, 'UNEXPECTED');
    } finally {
      _inFlight = false;
    }
  }
}
