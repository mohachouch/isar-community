// ignore_for_file: public_member_api_docs

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/src/memory_filter.dart';
import 'package:isar_community_web_memory/src/memory_reader.dart';

/// Converts in-memory objects to and from JSON maps keyed by property name.
class MemoryJsonCodec {
  MemoryJsonCodec(this.schema, this.embeddedSchemas);

  final CollectionSchema<dynamic> schema;
  final Map<String, Schema<dynamic>> embeddedSchemas;

  Map<String, dynamic> toJson(Id id, MemoryObject object) {
    final json = _objectToJson(schema, object);
    json[schema.idName] = id;
    return json;
  }

  MemoryObject fromJson(Map<String, dynamic> json) {
    return _jsonToObject(schema, json);
  }

  Id? idFromJson(Map<String, dynamic> json) {
    final value = json[schema.idName];
    return value is int ? value : null;
  }

  Map<String, dynamic> _objectToJson(
    Schema<dynamic> objSchema,
    MemoryObject object,
  ) {
    final json = <String, dynamic>{};
    for (final property in objSchema.properties.values) {
      json[property.name] = _decode(property, object[property.id]);
    }
    return json;
  }

  dynamic _decode(PropertySchema property, dynamic value) {
    if (property.type.isList) {
      if (value is! List) return null;
      final scalar = property.type.scalarType;
      return value.map((e) => _decodeScalar(scalar, property, e)).toList();
    }
    return _decodeScalar(property.type, property, value);
  }

  dynamic _decodeScalar(
    IsarType type,
    PropertySchema property,
    dynamic value,
  ) {
    switch (type) {
      case IsarType.bool:
        return value == 1
            ? true
            : value == 0
                ? false
                : null;
      case IsarType.byte:
        return value is int ? value : 0;
      case IsarType.int:
      case IsarType.long:
        return isNullish(value) ? null : value;
      case IsarType.float:
      case IsarType.double:
        return isNullish(value) ? null : value;
      case IsarType.dateTime:
        return isNullish(value)
            ? null
            : DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true)
                .toIso8601String();
      case IsarType.string:
        return value is String ? value : null;
      case IsarType.object:
        final target = property.target;
        final embedded = target != null ? embeddedSchemas[target] : null;
        if (embedded != null && value is MemoryObject) {
          return _objectToJson(embedded, value);
        }
        return null;
      // ignore: no_default_cases
      default:
        return value;
    }
  }

  MemoryObject _jsonToObject(Schema<dynamic> objSchema, Map<String, dynamic> json) {
    final object = <int, dynamic>{};
    for (final property in objSchema.properties.values) {
      object[property.id] = _encode(property, json[property.name]);
    }
    return object;
  }

  dynamic _encode(PropertySchema property, dynamic value) {
    if (property.type.isList) {
      if (value is! List) return null;
      final scalar = property.type.scalarType;
      return value.map((e) => _encodeScalar(scalar, property, e)).toList();
    }
    return _encodeScalar(property.type, property, value);
  }

  dynamic _encodeScalar(
    IsarType type,
    PropertySchema property,
    dynamic value,
  ) {
    switch (type) {
      case IsarType.bool:
        return value == null ? null : (value as bool ? 1 : 0);
      case IsarType.byte:
        return value is num ? value.toInt() : 0;
      case IsarType.int:
      case IsarType.long:
        return value is num ? value.toInt() : memoryNullInt;
      case IsarType.float:
      case IsarType.double:
        return value is num ? value.toDouble() : nullNumber;
      case IsarType.dateTime:
        if (value is String) {
          return DateTime.parse(value).toUtc().millisecondsSinceEpoch;
        } else if (value is int) {
          return value;
        }
        return memoryNullInt;
      case IsarType.string:
        return value is String ? value : null;
      case IsarType.object:
        final target = property.target;
        final embedded = target != null ? embeddedSchemas[target] : null;
        if (embedded != null && value is Map<String, dynamic>) {
          return _jsonToObject(embedded, value);
        }
        return null;
      // ignore: no_default_cases
      default:
        return value;
    }
  }
}
