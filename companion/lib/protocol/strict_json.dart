import 'dart:convert';

/// Minimal strict JSON parser that rejects duplicate object keys.
class StrictJson {
  static dynamic decode(String source) => _StrictJsonParser(source).parse();
}

class _StrictJsonParser {
  _StrictJsonParser(this.source);
  final String source;
  int index = 0;

  dynamic parse() {
    final value = _value();
    _space();
    if (index != source.length) throw const FormatException('trailing JSON data');
    return value;
  }

  dynamic _value() {
    _space();
    if (index >= source.length) throw const FormatException('unexpected end of JSON');
    switch (source.codeUnitAt(index)) {
      case 0x7b:
        return _object();
      case 0x5b:
        return _array();
      case 0x22:
        return _string();
      case 0x74:
        return _literal('true', true);
      case 0x66:
        return _literal('false', false);
      case 0x6e:
        return _literal('null', null);
      default:
        return _number();
    }
  }

  Map<String, dynamic> _object() {
    index++;
    final result = <String, dynamic>{};
    _space();
    if (_take(0x7d)) return result;
    while (true) {
      _space();
      if (index >= source.length || source.codeUnitAt(index) != 0x22) {
        throw const FormatException('object key must be a string');
      }
      final key = _string();
      if (result.containsKey(key)) throw const FormatException('duplicate JSON key');
      _space();
      if (!_take(0x3a)) throw const FormatException('missing colon');
      result[key] = _value();
      _space();
      if (_take(0x7d)) return result;
      if (!_take(0x2c)) throw const FormatException('missing comma');
    }
  }

  List<dynamic> _array() {
    index++;
    final result = <dynamic>[];
    _space();
    if (_take(0x5d)) return result;
    while (true) {
      result.add(_value());
      _space();
      if (_take(0x5d)) return result;
      if (!_take(0x2c)) throw const FormatException('missing comma');
    }
  }

  String _string() {
    final start = index++;
    var escaped = false;
    while (index < source.length) {
      final unit = source.codeUnitAt(index++);
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x22) {
        final decoded = jsonDecode(source.substring(start, index));
        if (decoded is! String) throw const FormatException('invalid string');
        return decoded;
      } else if (unit < 0x20) {
        throw const FormatException('invalid control character');
      }
    }
    throw const FormatException('unterminated string');
  }

  dynamic _number() {
    final start = index;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if ((unit >= 0x30 && unit <= 0x39) || unit == 0x2d || unit == 0x2b || unit == 0x2e || unit == 0x45 || unit == 0x65) {
        index++;
      } else {
        break;
      }
    }
    if (start == index) throw const FormatException('invalid JSON value');
    final decoded = jsonDecode(source.substring(start, index));
    if (decoded is! num) throw const FormatException('invalid number');
    return decoded;
  }

  dynamic _literal(String literal, dynamic value) {
    if (!source.startsWith(literal, index)) throw const FormatException('invalid literal');
    index += literal.length;
    return value;
  }

  bool _take(int unit) {
    if (index < source.length && source.codeUnitAt(index) == unit) {
      index++;
      return true;
    }
    return false;
  }

  void _space() {
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d) {
        index++;
      } else {
        return;
      }
    }
  }
}
