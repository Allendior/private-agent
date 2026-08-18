import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/pairing/pairing_controller.dart';

class MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('reports unpaired when its secure store has no record', () async {
    expect(await PairingController(MemoryStore()).status(), const PairingStatus.unpaired());
  });

  test('persists pairing without exposing key and can consume activation', () async {
    final store = MemoryStore();
    final controller = PairingController(store);
    await controller.pair(
      const PairingRecord(
        deviceId: 'pixel-test',
        sharedKey: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
        endpoint: 'http://192.168.0.196:8787/v1/status',
        activationId: '00112233445566778899aabbccddeeff',
      ),
    );

    expect(
      await controller.status(),
      const PairingStatus.paired(
        'pixel-test',
        'http://192.168.0.196:8787/v1/status',
      ),
    );
    await controller.consumeActivation();
    expect((await controller.record())!.activationId, isNull);
  });
}
