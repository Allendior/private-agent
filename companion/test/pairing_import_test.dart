import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/pairing/pairing_import.dart';

void main() {
  test('imports a valid unexpired one-time pairing payload', () {
    final result = PairingImport.parse(
      '''{"version":1,"device_id":"pixel-test","shared_key":"0123456789abcdefghijklmnopqrstuvwxyz","expires_at":1700000300}''',
      nowSeconds: 1700000000,
    );

    expect(result.record.deviceId, 'pixel-test');
    expect(result.record.sharedKey, '0123456789abcdefghijklmnopqrstuvwxyz');
  });

  test('rejects an expired pairing payload', () {
    expect(
      () => PairingImport.parse(
        '''{"version":1,"device_id":"pixel-test","shared_key":"0123456789abcdefghijklmnopqrstuvwxyz","expires_at":1700000000}''',
        nowSeconds: 1700000000,
      ),
      throwsFormatException,
    );
  });

  test('rejects unknown fields to avoid silent capability expansion', () {
    expect(
      () => PairingImport.parse(
        '''{"version":1,"device_id":"pixel-test","shared_key":"0123456789abcdefghijklmnopqrstuvwxyz","expires_at":1700000300,"role":"social"}''',
        nowSeconds: 1700000000,
      ),
      throwsFormatException,
    );
  });
}
