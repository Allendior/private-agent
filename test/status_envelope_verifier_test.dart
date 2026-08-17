import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/fleet_control/status_envelope_verifier.dart';

void main() {
  test('rejects a status envelope with an invalid signature', () {
    final result = StatusEnvelopeVerifier.verify(
      envelope: {
        'payload': {
          'version': 1,
          'job_id': 'job-1',
          'device_id': 'pixel-test',
          'actions': [
            {'type': 'device.status.get'},
          ],
          'created_at': 1700000000,
          'expires_at': 1700000300,
        },
        'signature': 'not-a-valid-signature',
      },
      sharedKey: 'test-shared-key',
      nowSeconds: 1700000001,
    );

    expect(result.accepted, isFalse);
    expect(result.code, 'INVALID_SIGNATURE');
  });
}
