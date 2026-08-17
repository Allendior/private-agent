import 'dart:convert';

import 'pairing_controller.dart';

class PairingImportResult {
  const PairingImportResult(this.record);

  final PairingRecord record;
}

/// Parses a one-time local pairing payload. This imports no network endpoint,
/// role, capability, or transport configuration.
class PairingImport {
  static PairingImportResult parse(String payload, {required int nowSeconds}) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const FormatException('pairing payload is not JSON');
    }
    if (decoded is! Map) {
      throw const FormatException('pairing payload must be an object');
    }
    final value = Map<String, dynamic>.from(decoded);
    const requiredKeys = {
      'version',
      'device_id',
      'shared_key',
      'endpoint',
      'expires_at',
    };
    if (value.keys.toSet().length != requiredKeys.length ||
        !value.keys.toSet().containsAll(requiredKeys) ||
        value['version'] != 1 ||
        value['device_id'] is! String ||
        value['shared_key'] is! String ||
        value['endpoint'] is! String ||
        value['expires_at'] is! int ||
        value['expires_at'] <= nowSeconds) {
      throw const FormatException('pairing payload is invalid or expired');
    }
    final record = PairingRecord(
      deviceId: value['device_id'] as String,
      sharedKey: value['shared_key'] as String,
      endpoint: value['endpoint'] as String,
    );
    if (!PairingController.isValidRecord(record)) {
      throw const FormatException('pairing payload has invalid credentials');
    }
    return PairingImportResult(record);
  }
}
