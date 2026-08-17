import '../protocol/strict_json.dart';
import 'pairing_controller.dart';

class PairingImportResult {
  const PairingImportResult(this.record);
  final PairingRecord record;
}

/// Strictly parses the directly transferred, 60-second activation payload.
class PairingImport {
  static PairingImportResult parse(String payload, {required int nowSeconds}) {
    final dynamic decoded;
    try {
      decoded = StrictJson.decode(payload);
    } on FormatException {
      throw const FormatException('pairing payload is not strict JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('pairing payload must be an object');
    }
    const requiredKeys = {
      'version', 'activation_id', 'device_id', 'shared_key', 'endpoint', 'expires_at',
    };
    if (decoded.length != requiredKeys.length ||
        !decoded.keys.toSet().containsAll(requiredKeys) ||
        decoded['version'] is! int || decoded['version'] != 1 ||
        decoded['activation_id'] is! String ||
        decoded['device_id'] is! String ||
        decoded['shared_key'] is! String ||
        decoded['endpoint'] is! String ||
        decoded['expires_at'] is! int ||
        decoded['expires_at'] <= nowSeconds ||
        decoded['expires_at'] > nowSeconds + 60 ||
        !_asciiStrings(decoded)) {
      throw const FormatException('pairing payload is invalid or expired');
    }
    final record = PairingRecord(
      deviceId: decoded['device_id'] as String,
      sharedKey: decoded['shared_key'] as String,
      endpoint: decoded['endpoint'] as String,
      activationId: decoded['activation_id'] as String,
    );
    if (!PairingController.isValidRecord(record)) {
      throw const FormatException('pairing payload has invalid credentials');
    }
    return PairingImportResult(record);
  }

  static bool _asciiStrings(Map<String, dynamic> value) => value.values
      .whereType<String>()
      .every((item) => item.codeUnits.every((unit) => unit <= 0x7f));
}
