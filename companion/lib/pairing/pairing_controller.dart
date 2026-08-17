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
    required this.activationId,
  });

  final String deviceId;
  final String sharedKey;
  final String endpoint;
  final String? activationId;
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
      other is PairingStatus && other.deviceId == deviceId && other.endpoint == endpoint;

  @override
  int get hashCode => Object.hash(deviceId, endpoint);
}

/// Persists only the device identity, status-proof key, pinned endpoint, and
/// optional one-time activation. It never initiates network activity.
class PairingController {
  PairingController(this._store);

  static const _deviceIdKey = 'fleet.device_id';
  static const _sharedKeyKey = 'fleet.shared_key';
  static const _endpointKey = 'fleet.endpoint';
  static const _activationIdKey = 'fleet.activation_id';

  final KeyValueStore _store;

  Future<PairingStatus> status() async {
    final recordValue = await record();
    if (recordValue == null) return const PairingStatus.unpaired();
    return PairingStatus.paired(recordValue.deviceId, recordValue.endpoint);
  }

  Future<PairingRecord?> record() async {
    final deviceId = await _store.read(_deviceIdKey);
    final sharedKey = await _store.read(_sharedKeyKey);
    final endpoint = await _store.read(_endpointKey);
    final activationId = await _store.read(_activationIdKey);
    if (deviceId == null || sharedKey == null || endpoint == null) return null;
    final value = PairingRecord(
      deviceId: deviceId,
      sharedKey: sharedKey,
      endpoint: endpoint,
      activationId: activationId,
    );
    return isValidRecord(value) ? value : null;
  }

  Future<void> pair(PairingRecord record) async {
    if (!isValidRecord(record)) throw ArgumentError('invalid pairing record');
    await _store.write(_deviceIdKey, record.deviceId);
    await _store.write(_sharedKeyKey, record.sharedKey);
    await _store.write(_endpointKey, record.endpoint);
    if (record.activationId == null) {
      await _store.delete(_activationIdKey);
    } else {
      await _store.write(_activationIdKey, record.activationId!);
    }
  }

  Future<void> consumeActivation() => _store.delete(_activationIdKey);

  Future<void> revoke() async {
    await _store.delete(_deviceIdKey);
    await _store.delete(_sharedKeyKey);
    await _store.delete(_endpointKey);
    await _store.delete(_activationIdKey);
  }

  static bool isValidRecord(PairingRecord record) =>
      _validDeviceId(record.deviceId) &&
      _validSharedKey(record.sharedKey) &&
      _validEndpoint(record.endpoint) &&
      _validActivationId(record.activationId);

  static bool _validDeviceId(String? value) =>
      value != null && RegExp(r'^[a-z][a-z0-9-]{2,63}$').hasMatch(value);

  static bool _validSharedKey(String? value) =>
      value != null && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);

  static bool _validActivationId(String? value) =>
      value == null || RegExp(r'^[0-9a-f]{32}$').hasMatch(value);

  static const _trustedEndpoint =
      'https://mac-mini-fleet.tailed5697.ts.net/v1/status';

  static bool _validEndpoint(String? value) => value == _trustedEndpoint;
}
