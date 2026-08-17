import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/pairing/pairing_import.dart';

const payload =
    '{"version":1,"activation_id":"00112233445566778899aabbccddeeff","device_id":"pixel-test","shared_key":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","endpoint":"https://mac-mini-fleet.tailed5697.ts.net/v1/status","expires_at":1700000060}';

void main() {
  test('imports a valid unexpired one-time activation payload', () {
    final result = PairingImport.parse(payload, nowSeconds: 1700000000);

    expect(result.record.deviceId, 'pixel-test');
    expect(result.record.activationId, '00112233445566778899aabbccddeeff');
    expect(result.record.sharedKey, 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8');
  });

  test('rejects expired or overlong activation windows', () {
    expect(() => PairingImport.parse(payload, nowSeconds: 1700000060), throwsFormatException);
    expect(
      () => PairingImport.parse(payload.replaceFirst('1700000060', '1700000061'), nowSeconds: 1700000000),
      throwsFormatException,
    );
  });

  test('rejects foreign endpoint, unknown fields, and duplicate keys', () {
    final cases = [
      payload.replaceFirst('mac-mini-fleet.tailed5697', 'other-tailnet'),
      payload.replaceFirst('"version":1', '"version":1,"role":"social"'),
      payload.replaceFirst('"version":1', '"version":1,"version":1'),
    ];
    for (final value in cases) {
      expect(() => PairingImport.parse(value, nowSeconds: 1700000000), throwsFormatException);
    }
  });
}
