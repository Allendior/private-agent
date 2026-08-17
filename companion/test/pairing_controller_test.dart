import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent_companion/pairing/pairing_controller.dart';

class MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('reports unpaired when its secure store has no record', () async {
    final controller = PairingController(MemoryStore());

    expect(await controller.status(), const PairingStatus.unpaired());
  });

  test('persists a valid pairing without exposing its key in status', () async {
    final controller = PairingController(MemoryStore());

    await controller.pair(
      const PairingRecord(
        deviceId: 'pixel-test',
        sharedKey: '0123456789abcdefghijklmnopqrstuvwxyz',
        endpoint: 'https://mac-mini-fleet.tailed5697.ts.net/v1/status',
      ),
    );

    expect(
      await controller.status(),
      const PairingStatus.paired(
        'pixel-test',
        'https://mac-mini-fleet.tailed5697.ts.net/v1/status',
      ),
    );
  });
}
