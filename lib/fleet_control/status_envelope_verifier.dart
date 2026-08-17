import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

class StatusEnvelopeResult {
  const StatusEnvelopeResult(this.accepted, this.code);

  final bool accepted;
  final String code;
}

/// Verifies the first Android-facing fleet protocol slice.
///
/// This accepts only a signed, unexpired [device.status.get] request. It does
/// not execute Accessibility actions, expose a listener, or read device data.
class StatusEnvelopeVerifier {
  static StatusEnvelopeResult verify({
    required Map<String, dynamic> envelope,
    required String sharedKey,
    required int nowSeconds,
  }) {
    final payload = envelope['payload'];
    final signature = envelope['signature'];
    if (payload is! Map || signature is! String || sharedKey.isEmpty) {
      return const StatusEnvelopeResult(false, 'MALFORMED_ENVELOPE');
    }

    final normalizedPayload = Map<String, dynamic>.from(payload);
    if (!_isStatusOnlyPayload(normalizedPayload, nowSeconds)) {
      return const StatusEnvelopeResult(false, 'INVALID_PAYLOAD');
    }

    final providedSignature = _decodeBase64Url(signature);
    if (providedSignature == null) {
      return const StatusEnvelopeResult(false, 'INVALID_SIGNATURE');
    }
    final canonicalPayload = jsonEncode(_canonicalize(normalizedPayload));
    final expectedSignature = Hmac(sha256, utf8.encode(sharedKey))
        .convert(utf8.encode(canonicalPayload))
        .bytes;
    if (!_constantTimeEquals(providedSignature, expectedSignature)) {
      return const StatusEnvelopeResult(false, 'INVALID_SIGNATURE');
    }
    return const StatusEnvelopeResult(true, 'OK');
  }

  static bool _isStatusOnlyPayload(Map<String, dynamic> payload, int nowSeconds) {
    const requiredKeys = {
      'version',
      'job_id',
      'device_id',
      'actions',
      'created_at',
      'expires_at',
    };
    if (payload.keys.toSet().length != requiredKeys.length ||
        !payload.keys.toSet().containsAll(requiredKeys) ||
        payload['version'] != 1 ||
        payload['job_id'] is! String ||
        payload['device_id'] is! String ||
        payload['created_at'] is! int ||
        payload['expires_at'] is! int ||
        payload['expires_at'] <= nowSeconds) {
      return false;
    }
    final actions = payload['actions'];
    return actions is List &&
        actions.length == 1 &&
        actions.single is Map &&
        Map<Object?, Object?>.from(actions.single as Map).length == 1 &&
        (actions.single as Map)['type'] == 'device.status.get';
  }

  static List<int>? _decodeBase64Url(String value) {
    try {
      return base64Url.decode(base64Url.normalize(value));
    } on FormatException {
      return null;
    }
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final sorted = SplayTreeMap<String, Object?>();
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ArgumentError('protocol object keys must be strings');
        }
        sorted[entry.key as String] = _canonicalize(entry.value);
      }
      return sorted;
    }
    if (value is List) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }
}
