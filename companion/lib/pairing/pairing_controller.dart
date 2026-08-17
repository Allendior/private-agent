abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PairingRecord {
  const PairingRecord({
    required this.deviceId,
    required this.sharedKey,
    required this.endpoint,
  });

  final String deviceId;
  final String sharedKey;
  final String endpoint;
}

class PairingStatus {
  const PairingStatus.unpaired()
      : deviceId = null,
        endpoint = null;
  const PairingStatus.paired(this.deviceId, this.endpoint);

  final String? deviceId;
  final String? endpoint;

  @override
  bool operator ==(Object other) =>
      other is PairingStatus &&
      other.deviceId == deviceId &&
      other.endpoint == endpoint;

  @override
  int get hashCode => Object.hash(deviceId, endpoint);
}

/// Persists only the device identity, status-proof key, and the explicit
/// private Tailscale HTTPS endpoint. No background work is initiated here.
class PairingController {
  PairingController(this._store);

  static const _deviceIdKey = 'fleet.device_id';
  static const _sharedKeyKey = 'fleet.shared_key';
  static const _endpointKey = 'fleet.endpoint';

  final KeyValueStore _store;

  Future<PairingStatus> status() async {
    final deviceId = await _store.read(_deviceIdKey);
    final sharedKey = await _store.read(_sharedKeyKey);
    final endpoint = await _store.read(_endpointKey);
    if (!_validDeviceId(deviceId) ||
        !_validSharedKey(sharedKey) ||
        !_validEndpoint(endpoint)) {
      return const PairingStatus.unpaired();
    }
    return PairingStatus.paired(deviceId!, endpoint!);
  }

  Future<PairingRecord?> record() async {
    final deviceId = await _store.read(_deviceIdKey);
    final sharedKey = await _store.read(_sharedKeyKey);
    final endpoint = await _store.read(_endpointKey);
    if (deviceId == null || sharedKey == null || endpoint == null) return null;
    final value = PairingRecord(
      deviceId: deviceId,
      sharedKey: sharedKey,
      endpoint: endpoint,
    );
    return isValidRecord(value) ? value : null;
  }

  Future<void> pair(PairingRecord record) async {
    if (!isValidRecord(record)) {
      throw ArgumentError('invalid pairing record');
    }
    await _store.write(_deviceIdKey, record.deviceId);
    await _store.write(_sharedKeyKey, record.sharedKey);
    await _store.write(_endpointKey, record.endpoint);
  }

  Future<void> revoke() async {
    await _store.delete(_deviceIdKey);
    await _store.delete(_sharedKeyKey);
    await _store.delete(_endpointKey);
  }

  static bool isValidRecord(PairingRecord record) =>
      _validDeviceId(record.deviceId) &&
      _validSharedKey(record.sharedKey) &&
      _validEndpoint(record.endpoint);

  static bool _validDeviceId(String? value) =>
      value != null && RegExp(r'^[a-z][a-z0-9-]{2,63}$').hasMatch(value);

  static bool _validSharedKey(String? value) => value != null && value.length >= 32;

  static const _trustedEndpoint =
      'https://mac-mini-fleet.tailed5697.ts.net/v1/status';

  static bool _validEndpoint(String? value) => value == _trustedEndpoint;
}
