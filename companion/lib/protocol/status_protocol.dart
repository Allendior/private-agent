import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'strict_json.dart';

const _requestDomain = 'private-agent/status-request/v1\n';
const _responseDomain = 'private-agent/status-response/v1\n';
const _requestKeys = {
  'version', 'kind', 'request_id', 'device_id', 'activation_id', 'created_at', 'expires_at',
};
const _responseKeys = {
  'version', 'kind', 'request_id', 'device_id', 'status', 'created_at', 'expires_at',
};
final _hex128 = RegExp(r'^[0-9a-f]{32}$');
final _deviceId = RegExp(r'^[a-z][a-z0-9-]{2,63}$');
final _signature = RegExp(r'^[A-Za-z0-9_-]{43}$');

typedef RandomBytes = List<int> Function(int length);

class StatusRequestEnvelope {
  const StatusRequestEnvelope(this.value, this.requestId);
  final Map<String, dynamic> value;
  final String requestId;
}

class StatusProtocol {
  static StatusRequestEnvelope buildRequest({
    required String deviceId,
    required String activationId,
    required String sharedKey,
    required int nowSeconds,
    RandomBytes? randomBytes,
  }) {
    final bytes = (randomBytes ?? _secureBytes)(16);
    if (bytes.length != 16 || bytes.any((value) => value < 0 || value > 255)) {
      throw ArgumentError('request IDs require exactly 16 random bytes');
    }
    final requestId = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final payload = <String, dynamic>{
      'version': 1,
      'kind': 'device.status.heartbeat',
      'request_id': requestId,
      'device_id': deviceId,
      'activation_id': activationId,
      'created_at': nowSeconds,
      'expires_at': nowSeconds + 60,
    };
    _validateRequest(payload, nowSeconds);
    return StatusRequestEnvelope(
      {'payload': payload, 'signature': _sign(payload, sharedKey, _requestDomain)},
      requestId,
    );
  }

  static Map<String, dynamic> verifyResponse({
    required String body,
    required String sharedKey,
    required String expectedDeviceId,
    required String expectedRequestId,
    required int nowSeconds,
  }) {
    final decoded = StrictJson.decode(body);
    if (decoded is! Map<String, dynamic> || !_exactKeys(decoded, {'payload', 'signature'})) {
      throw const FormatException('invalid response envelope');
    }
    final payload = decoded['payload'];
    final signature = decoded['signature'];
    if (payload is! Map<String, dynamic> || signature is! String || !_signature.hasMatch(signature)) {
      throw const FormatException('invalid response envelope');
    }
    if (!_exactKeys(payload, _responseKeys) || !_asciiStrings(payload)) {
      throw const FormatException('invalid response schema');
    }
    if (payload['version'] is! int || payload['version'] != 1 ||
        payload['kind'] != 'host.status.response' || payload['status'] != 'ok' ||
        payload['request_id'] != expectedRequestId || payload['device_id'] != expectedDeviceId ||
        !_hex128.hasMatch(expectedRequestId) || !_deviceId.hasMatch(expectedDeviceId)) {
      throw const FormatException('invalid response identity');
    }
    _validateTimes(payload, nowSeconds);
    final expected = _sign(payload, sharedKey, _responseDomain);
    if (!_constantTimeEquals(ascii.encode(signature), ascii.encode(expected))) {
      throw const FormatException('invalid response signature');
    }
    return payload;
  }

  static String encodeEnvelope(Map<String, dynamic> envelope) => _canonicalJson(envelope);

  static void _validateRequest(Map<String, dynamic> payload, int nowSeconds) {
    if (!_exactKeys(payload, _requestKeys) || !_asciiStrings(payload) ||
        payload['version'] is! int || payload['version'] != 1 ||
        payload['kind'] != 'device.status.heartbeat' ||
        payload['request_id'] is! String || !_hex128.hasMatch(payload['request_id'] as String) ||
        payload['device_id'] is! String || !_deviceId.hasMatch(payload['device_id'] as String) ||
        payload['activation_id'] is! String ||
        ((payload['activation_id'] as String).isNotEmpty && !_hex128.hasMatch(payload['activation_id'] as String))) {
      throw const FormatException('invalid request payload');
    }
    _validateTimes(payload, nowSeconds);
  }

  static void _validateTimes(Map<String, dynamic> payload, int nowSeconds) {
    final createdAt = payload['created_at'];
    final expiresAt = payload['expires_at'];
    if (createdAt is! int || expiresAt is! int || expiresAt <= createdAt ||
        expiresAt - createdAt > 60 || createdAt > nowSeconds + 30 || expiresAt <= nowSeconds) {
      throw const FormatException('invalid protocol timestamps');
    }
  }

  static String _sign(Map<String, dynamic> payload, String key, String domain) {
    final keyBytes = _decodeKey(key);
    final digest = Hmac(sha256, keyBytes).convert(utf8.encode(domain + _canonicalJson(payload))).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  static List<int> _decodeKey(String key) {
    if (!_signature.hasMatch(key)) throw const FormatException('invalid shared key');
    final bytes = base64Url.decode(base64Url.normalize(key));
    if (bytes.length != 32 || base64UrlEncode(bytes).replaceAll('=', '') != key) {
      throw const FormatException('invalid shared key');
    }
    return bytes;
  }

  static String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final sorted = SplayTreeMap<String, Object?>();
      for (final entry in value.entries) {
        if (entry.key is! String) throw const FormatException('non-string JSON key');
        sorted[entry.key as String] = _canonicalize(entry.value);
      }
      return sorted;
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    return value;
  }

  static bool _exactKeys(Map<String, dynamic> value, Set<String> expected) =>
      value.length == expected.length && value.keys.toSet().containsAll(expected);

  static bool _asciiStrings(Map<String, dynamic> value) {
    for (final item in value.values.whereType<String>()) {
      if (item.codeUnits.any((unit) => unit > 0x7f)) return false;
    }
    return true;
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static List<int> _secureBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256), growable: false);
  }
}

List<int> hexToBytes(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
    throw const FormatException('invalid lower-case hex');
  }
  return List<int>.generate(
    value.length ~/ 2,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
    growable: false,
  );
}
