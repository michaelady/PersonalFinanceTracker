/// Converts Dart JSON <-> Firestore REST `fields` values.
abstract final class FirestoreRestCodec {
  static Map<String, dynamic> encodeFields(Map<String, dynamic> json) {
    return {
      for (final entry in json.entries)
        if (entry.value != null) entry.key: encodeValue(entry.value),
    };
  }

  static Map<String, dynamic> decodeFields(Map<String, dynamic>? fields) {
    if (fields == null) return {};
    return {
      for (final entry in fields.entries) entry.key: decodeValue(entry.value),
    };
  }

  static Map<String, dynamic> encodeValue(Object? value) {
    if (value == null) return {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': '$value'};
    if (value is double) return {'doubleValue': value};
    if (value is num) return {'doubleValue': value.toDouble()};
    if (value is String) return {'stringValue': value};
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is List) {
      return {
        'arrayValue': {
          'values': [for (final item in value) encodeValue(item)],
        },
      };
    }
    if (value is Map) {
      return {
        'mapValue': {
          'fields': encodeFields(
            {
              for (final entry in value.entries)
                entry.key.toString(): entry.value,
            },
          ),
        },
      };
    }
    return {'stringValue': value.toString()};
  }

  static Object? decodeValue(Object? value) {
    if (value is! Map) return value;
    final map = {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
    if (map.containsKey('nullValue')) return null;
    if (map.containsKey('booleanValue')) return map['booleanValue'] as bool;
    if (map.containsKey('integerValue')) {
      final raw = map['integerValue'];
      if (raw is int) return raw;
      return int.parse('$raw');
    }
    if (map.containsKey('doubleValue')) {
      return (map['doubleValue'] as num).toDouble();
    }
    if (map.containsKey('stringValue')) return map['stringValue'] as String;
    if (map.containsKey('timestampValue')) {
      return map['timestampValue'] as String;
    }
    if (map.containsKey('arrayValue')) {
      final values = (map['arrayValue'] as Map)['values'] as List<dynamic>? ?? [];
      return [for (final item in values) decodeValue(item)];
    }
    if (map.containsKey('mapValue')) {
      final fields = (map['mapValue'] as Map)['fields'];
      return decodeFields(
        fields is Map
            ? {
                for (final entry in fields.entries)
                  entry.key.toString(): entry.value,
              }
            : null,
      );
    }
    return null;
  }
}
