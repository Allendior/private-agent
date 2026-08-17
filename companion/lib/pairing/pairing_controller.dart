abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PairingRecord {
  const PairingRecord({required this.deviceId, required this.sharedKey});

  final String deviceId;
  final String sharedKey;
}

class PairingStatus {
  const PairingStatus.unpaired() : deviceId = null;
  const PairingStatus.paired(this.deviceId);

  final String? deviceId;

  @override
  bool operator ==(Object other) =>
      other is PairingStatus && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

/// Persists only the device identity and shared key needed for a local proof.
/// No network, background job, or Android automation is initiated here.
class PairingController {
  PairingController(this._store);

  static const _deviceIdKey = 'fleet.device_id';
  static const _sharedKeyKey = 'fleet.shared_key';

  final KeyValueStore _store;

  Future<PairingStatus> status() async {
    final deviceId = await _store.read(_deviceIdKey);
    final sharedKey = await _store.read(_sharedKeyKey);
    if (!_validDeviceId(deviceId) || !_validSharedKey(sharedKey)) {
      return const PairingStatus.unpaired();
    }
    return PairingStatus.paired(deviceId!);
  }

  Future<void> pair(PairingRecord record) async {
    if (!isValidRecord(record)) {
      throw ArgumentError('invalid pairing record');
    }
    await _store.write(_deviceIdKey, record.deviceId);
    await _store.write(_sharedKeyKey, record.sharedKey);
  }

  Future<void> revoke() async {
    await _store.delete(_deviceIdKey);
    await _store.delete(_sharedKeyKey);
  }

  static bool isValidRecord(PairingRecord record) =>
      _validDeviceId(record.deviceId) && _validSharedKey(record.sharedKey);

  static bool _validDeviceId(String? value) =>
      value != null && RegExp(r'^[a-z][a-z0-9-]{2,63}$').hasMatch(value);

  static bool _validSharedKey(String? value) => value != null && value.length >= 32;
}
