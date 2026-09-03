/// Built-in value casters used by [Model]'s `$casts` registry.
library;

import 'dart:convert';

import '../exceptions.dart';

/// The canonical cast-type strings recognised by [Casts.cast].
///
/// Subclasses can use any string here as the value in `$casts`:
/// ```dart
/// @override
/// Map<String, String> get $casts => {'age': 'int', 'meta': 'json'};
/// ```
abstract class CastType {
  static const String integer = 'int';
  static const String double_ = 'double';
  static const String string = 'string';
  static const String boolean = 'bool';
  static const String date = 'date';
  static const String dateTime = 'datetime';
  static const String json = 'json';
  static const String array = 'array';
}

/// Cast helpers used by the `$casts` registry on [Model].
///
/// Each `to<Type>(value)` returns the typed in-memory value (e.g. an
/// `int`, a `Map<String, dynamic>`). Each `from<Type>(value)` returns the
/// underlying storage representation (almost always a `String`, since
/// Drift columns store everything except primitives as text).
///
/// [Casts.cast] dispatches by type name (see [CastType]). [Casts.uncast]
/// is the inverse used by [Model.setAttribute].
class Casts {
  Casts._();

  /// Convert [value] (a raw column value) into the user-facing type named
  /// by [typeName] (one of [CastType]'s constants).
  ///
  /// Returns [value] unchanged when [value] is already `null`. Unknown
  /// [typeName]s throw [InvalidArgumentException].
  static Object? cast(Object? value, String typeName) {
    if (value == null) return null;
    switch (typeName) {
      case CastType.integer:
        return toInt(value);
      case CastType.double_:
        return toDouble(value);
      case CastType.string:
        return toString_(value);
      case CastType.boolean:
        return toBool(value);
      case CastType.date:
        return toDate(value);
      case CastType.dateTime:
        return toDateTime(value);
      case CastType.json:
        return toJson(value);
      case CastType.array:
        return toArray(value);
      default:
        throw InvalidArgumentException(
          'Unknown cast type "$typeName". '
          'Supported: int, double, string, bool, date, datetime, json, array.',
        );
    }
  }

  /// Inverse of [cast]: convert a typed user value back into the
  /// underlying storage representation.
  ///
  /// `String` stays a `String`; `int` / `double` / `bool` are coerced via
  /// their textual encoding; `DateTime` is ISO-8601; `Map` / `List` go
  /// through `jsonEncode`.
  static Object? uncast(Object? value, String typeName) {
    if (value == null) return null;
    switch (typeName) {
      case CastType.integer:
        return fromInt(value);
      case CastType.double_:
        return fromDouble(value);
      case CastType.string:
        return fromString_(value);
      case CastType.boolean:
        return fromBool(value);
      case CastType.date:
        return fromDate(value);
      case CastType.dateTime:
        return fromDateTime(value);
      case CastType.json:
        return fromJson(value);
      case CastType.array:
        return fromArray(value);
      default:
        throw InvalidArgumentException(
          'Unknown cast type "$typeName". '
          'Supported: int, double, string, bool, date, datetime, json, array.',
        );
    }
  }

  // ===== int =====

  /// Parse [value] as an `int`.
  ///
  /// Accepts `int`, `String`, `bool`, and `double` (truncated).
  static int toInt(Object value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is bool) return value ? 1 : 0;
    if (value is String) return int.parse(value);
    throw InvalidArgumentException(
      'Cannot cast ${value.runtimeType} to int.',
    );
  }

  /// Inverse of [toInt] used when values come from user code (e.g.
  /// `Model.create({'stock': '42'})`) and need to be coerced into the
  /// storage type for the column. Drift's `IntColumn` requires `int`, so
  /// a stringly-typed `'42'` has to be parsed before it reaches Drift.
  ///
  /// Accepts `int`, `String`, `bool`, and `double`. Everything else
  /// throws.
  static int fromInt(Object value) {
    if (value is int) return value;
    if (value is String) return int.parse(value);
    if (value is bool) return value ? 1 : 0;
    if (value is double) return value.toInt();
    throw InvalidArgumentException(
      'Cannot uncast ${value.runtimeType} to int.',
    );
  }

  // ===== double =====

  /// Parse [value] as a `double`.
  ///
  /// Accepts `double`, `int`, and `String`.
  static double toDouble(Object value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.parse(value);
    throw InvalidArgumentException(
      'Cannot cast ${value.runtimeType} to double.',
    );
  }

  /// Inverse of [toDouble]. Accepts `double`, `int`, and `String` and
  /// returns the canonical `double` value drift expects.
  static double fromDouble(Object value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.parse(value);
    throw InvalidArgumentException(
      'Cannot uncast ${value.runtimeType} to double.',
    );
  }

  // ===== string =====

  /// Coerce [value] to a `String` via `toString()`.
  static String toString_(Object value) => value.toString();

  static String fromString_(Object value) {
    if (value is String) return value;
    return value.toString();
  }

  // ===== bool =====

  /// Coerce [value] to a `bool`.
  ///
  /// Accepts `bool` (`true`/`false`), `int` (`0` is false, anything else
  /// is true), `String` (`'1'`, `'true'`, `'yes'`, `'on'` are true; `'0'`,
  /// `'false'`, `'no'`, `'off'`, `''` are false), and `null` (returns
  /// `false`).
  static bool toBool(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is double) return value != 0.0;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == '1' ||
          lower == 'true' ||
          lower == 'yes' ||
          lower == 'on') {
        return true;
      }
      return false;
    }
    throw InvalidArgumentException(
      'Cannot cast ${value.runtimeType} to bool.',
    );
  }

  /// Inverse of [toBool]. Returns `bool` as the canonical drift value
  /// (`bool` itself). Accepts `bool`, `int`, or `String`.
  static bool fromBool(Object value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return toBool(value);
    throw InvalidArgumentException(
      'Cannot uncast ${value.runtimeType} to bool.',
    );
  }

  // ===== date =====

  /// Parse [value] as a `DateTime` and truncate to a date (midnight, local).
  static DateTime toDate(Object value) {
    final dt = toDateTime(value);
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Inverse of [toDate]. Drift's `DateTime` column accepts `DateTime`
  /// instances; truncate to midnight before returning.
  static DateTime fromDate(Object value) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    if (value is String) {
      final parsed = DateTime.parse(value);
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    throw InvalidArgumentException(
      'Cannot uncast ${value.runtimeType} to date.',
    );
  }

  // ===== datetime =====

  /// Parse [value] as a `DateTime`.
  ///
  /// Accepts `DateTime`, `String` (ISO-8601 or anything `DateTime.parse`
  /// understands), and `int` / `double` (treated as Unix epoch seconds).
  static DateTime toDateTime(Object value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (value is double) {
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
    }
    throw InvalidArgumentException(
      'Cannot cast ${value.runtimeType} to DateTime.',
    );
  }

  /// Inverse of [toDateTime]. Drift's `DateTime` column accepts `DateTime`
  /// instances directly, so the canonical storage form is the same
  /// `DateTime` object the user typed. If a `String` arrives from caller
  /// code, parse it; anything else throws.
  static DateTime fromDateTime(Object value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    throw InvalidArgumentException(
      'Cannot uncast ${value.runtimeType} to DateTime.',
    );
  }

  // ===== json =====

  /// Decode [value] (a JSON string or already-decoded `Map`) into a
  /// `Map<String, dynamic>`.
  static Map<String, dynamic> toJson(Object value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      throw InvalidArgumentException(
        'JSON cast expected an object, got ${decoded.runtimeType}.',
      );
    }
    throw InvalidArgumentException(
      'Cannot cast ${value.runtimeType} to JSON object.',
    );
  }

  /// Encode [value] (a `Map` or a JSON string) back into a JSON string.
  static String fromJson(Object value) {
    if (value is String) return value;
    if (value is Map) return jsonEncode(value);
    throw InvalidArgumentException(
      'Cannot uncast ${value.runtimeType} to JSON string.',
    );
  }

  // ===== array =====

  /// Decode [value] (a JSON array string or already-decoded `List`) into
  /// a `List<dynamic>`.
  static List<dynamic> toArray(Object value) {
    if (value is List) return value;
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded;
      throw InvalidArgumentException(
        'Array cast expected a JSON array, got ${decoded.runtimeType}.',
      );
    }
    throw InvalidArgumentException(
      'Cannot cast ${value.runtimeType} to List.',
    );
  }

  /// Encode [value] (a `List` or a JSON string) back into a JSON string.
  static String fromArray(Object value) {
    if (value is String) return value;
    if (value is List) return jsonEncode(value);
    throw InvalidArgumentException(
      'Cannot uncast ${value.runtimeType} to JSON array string.',
    );
  }
}
