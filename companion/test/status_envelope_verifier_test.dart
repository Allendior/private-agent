import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/protocol/status_envelope_verifier.dart';

Map<String, dynamic> signedEnvelope({
  String action = 'device.status.get',
  int expiresAt = 1700000300,
}) {
  const key = '0123456789abcdefghijklmnopqrstuvwxyz';
  final payload = <String, dynamic>{
    'version': 1,
    'job_id': 'job-1',
    'device_id': 'pixel-test',
    'actions': [
      {'type': action},
    ],
    'created_at': 1700000000,
    'expires_at': expiresAt,
  };
  final canonical = jsonEncode(SplayTreeMap<String, dynamic>.from(payload));
  final signature = base64UrlEncode(
    Hmac(sha256, utf8.encode(key)).convert(utf8.encode(canonical)).bytes,
  ).replaceAll('=', '');
  return {'payload': payload, 'signature': signature};
}

void main() {
  test('accepts a fixed host-generated status probe vector', () {
    final result = StatusEnvelopeVerifier.verify(
      envelope: {
        'payload': {
          'version': 1,
          'job_id': 'host-vector-1',
          'device_id': 'pixel-test',
          'actions': [
            {'type': 'device.status.get'},
          ],
          'created_at': 1700000000,
          'expires_at': 1700000300,
        },
        'signature': 'KMw7ISSxkpKBcLzm2w2ejG10Ilup_gx_CTCFQ-bN0m0',
      },
      sharedKey: '0123456789abcdefghijklmnopqrstuvwxyz',
      nowSeconds: 1700000001,
    );

    expect(result.accepted, isTrue);
    expect(result.code, 'OK');
  });

  test('accepts a signed unexpired status-only envelope', () {
    final result = StatusEnvelopeVerifier.verify(
      envelope: signedEnvelope(),
      sharedKey: '0123456789abcdefghijklmnopqrstuvwxyz',
      nowSeconds: 1700000001,
    );

    expect(result.accepted, isTrue);
    expect(result.code, 'OK');
  });

  test('rejects an expired status-only envelope', () {
    final result = StatusEnvelopeVerifier.verify(
      envelope: signedEnvelope(expiresAt: 1700000001),
      sharedKey: '0123456789abcdefghijklmnopqrstuvwxyz',
      nowSeconds: 1700000001,
    );

    expect(result.accepted, isFalse);
    expect(result.code, 'INVALID_PAYLOAD');
  });

  test('rejects an action outside status-only scope', () {
    final result = StatusEnvelopeVerifier.verify(
      envelope: signedEnvelope(action: 'open_app'),
      sharedKey: '0123456789abcdefghijklmnopqrstuvwxyz',
      nowSeconds: 1700000001,
    );

    expect(result.accepted, isFalse);
    expect(result.code, 'INVALID_PAYLOAD');
  });
}
