import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/protocol/status_protocol.dart';

const key = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
const device = 'pixel-test';
const activation = '00112233445566778899aabbccddeeff';
const requestId = 'ffeeddccbbaa99887766554433221100';

void main() {
  test('Dart request matches fixed Python request vector', () {
    final envelope = StatusProtocol.buildRequest(
      deviceId: device,
      activationId: activation,
      sharedKey: key,
      nowSeconds: 1700000000,
      randomBytes: (_) => hexToBytes(requestId),
    );

    expect(envelope.requestId, requestId);
    expect(envelope.value['signature'], 'MiZYQJqNveNq1i11Bo7RB2ZRwRdOb-tUaEJcJGtSzR0');
  });

  test('accepts fixed Python response vector and verifies identities', () {
    const body =
        '{"payload":{"created_at":1700000001,"device_id":"pixel-test","expires_at":1700000061,"kind":"host.status.response","request_id":"ffeeddccbbaa99887766554433221100","status":"ok","version":1},"signature":"cr-nzS8YWLrbd-MlUGXMwCutbEWtYtfpf8E8pCpYG3I"}';

    final payload = StatusProtocol.verifyResponse(
      body: body,
      sharedKey: key,
      expectedDeviceId: device,
      expectedRequestId: requestId,
      nowSeconds: 1700000002,
    );

    expect(payload['status'], 'ok');
  });

  test('rejects duplicate keys, tamper, wrong identity, malformed signature and expiry', () {
    const valid =
        '{"payload":{"created_at":1700000001,"device_id":"pixel-test","expires_at":1700000061,"kind":"host.status.response","request_id":"ffeeddccbbaa99887766554433221100","status":"ok","version":1},"signature":"cr-nzS8YWLrbd-MlUGXMwCutbEWtYtfpf8E8pCpYG3I"}';
    final cases = <String>[
      valid.replaceFirst('"status":"ok"', '"status":"no"'),
      valid.replaceFirst('pixel-test', 'other-device'),
      valid.replaceFirst(
        'cr-nzS8YWLrbd-MlUGXMwCutbEWtYtfpf8E8pCpYG3I',
        List.filled(43, 'A').join(),
      ),
      valid.replaceFirst('1700000061', '1700000002'),
      valid.replaceFirst('"version":1', '"version":1,"version":1'),
      valid.replaceFirst('"version":1', '"version":1,"extra":1'),
      valid.replaceFirst('"created_at":1700000001', '"created_at":true'),
      valid.replaceFirst('host.status.response', 'host.status.réponse'),
    ];

    for (final body in cases) {
      expect(
        () => StatusProtocol.verifyResponse(
          body: body,
          sharedKey: key,
          expectedDeviceId: device,
          expectedRequestId: requestId,
          nowSeconds: 1700000002,
        ),
        throwsFormatException,
        reason: body,
      );
    }
  });
}
