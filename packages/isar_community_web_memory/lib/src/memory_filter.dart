// ignore_for_file: public_member_api_docs

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/src/memory_reader.dart';

/// Returns `true` if [value] represents a `null` value in the in-memory store.
bool isNullish(dynamic value) {
  return value == null ||
      (value is double && (value == nullNumber || value.isNaN)) ||
      value == memoryNullInt;
}

/// Encodes a Dart [value] coming from a filter into the stored representation.
dynamic encodeValue(dynamic value) {
  if (value == null) {
    return null;
  } else if (value is bool) {
    return value ? 1 : 0;
  } else if (value is DateTime) {
    return value.toUtc().millisecondsSinceEpoch;
  } else if (value is Enum) {
    return value.index;
  } else if (value is List) {
    return value.map<dynamic>(encodeValue).toList();
  } else {
    return value;
  }
}

/// Compares two stored (encoded) scalar values following Isar/IndexedDB
/// ordering: `null` is the smallest value, numbers sort before strings.
int compareValues(dynamic a, dynamic b) {
  final aNull = isNullish(a);
  final bNull = isNullish(b);
  if (aNull || bNull) {
    if (aNull && bNull) return 0;
    return aNull ? -1 : 1;
  }
  if (a is num && b is num) {
    return a.compareTo(b);
  } else if (a is String && b is String) {
    return a.compareTo(b);
  } else if (a is num) {
    // Numbers sort before strings.
    return -1;
  } else if (b is num) {
    return 1;
  }
  return a.toString().compareTo(b.toString());
}

/// Evaluates query filters against in-memory objects.
class MemoryFilter {
  MemoryFilter(this.schema);

  final CollectionSchema<dynamic> schema;

  /// Returns the stored value of [property] for the given [object].
  ///
  /// The implicit id property resolves to [id].
  dynamic propertyValue(
    Schema<dynamic> objSchema,
    MemoryObject object,
    Id id,
    String property,
  ) {
    if (objSchema is CollectionSchema && property == objSchema.idName) {
      return id;
    }
    final prop = objSchema.property(property);
    return object[prop.id];
  }

  bool evaluate(
    FilterOperation filter,
    MemoryObject object,
    Id id,
  ) {
    return _evaluate(schema, filter, object, id);
  }

  bool _evaluate(
    Schema<dynamic> objSchema,
    FilterOperation filter,
    MemoryObject object,
    Id id,
  ) {
    if (filter is FilterGroup) {
      return _evaluateGroup(objSchema, filter, object, id);
    } else if (filter is FilterCondition) {
      return _evaluateCondition(objSchema, filter, object, id);
    } else if (filter is ObjectFilter) {
      return _evaluateObject(objSchema, filter, object, id);
    } else if (filter is LinkFilter) {
      throw UnsupportedError(
        'Link filters are not supported by the in-memory Isar backend.',
      );
    }
    return true;
  }

  bool _evaluateGroup(
    Schema<dynamic> objSchema,
    FilterGroup group,
    MemoryObject object,
    Id id,
  ) {
    switch (group.type) {
      case FilterGroupType.and:
        return group.filters
            .every((f) => _evaluate(objSchema, f, object, id));
      case FilterGroupType.or:
        return group.filters.any((f) => _evaluate(objSchema, f, object, id));
      case FilterGroupType.xor:
        return group.filters
                .where((f) => _evaluate(objSchema, f, object, id))
                .length ==
            1;
      case FilterGroupType.not:
        return !_evaluate(objSchema, group.filters.first, object, id);
    }
  }

  bool _evaluateObject(
    Schema<dynamic> objSchema,
    ObjectFilter filter,
    MemoryObject object,
    Id id,
  ) {
    final prop = objSchema.property(filter.property);
    final target = prop.target;
    final embeddedSchema = target != null
        ? schema.embeddedSchemas[target]
        : null;
    if (embeddedSchema == null) {
      return false;
    }
    final value = object[prop.id];
    if (prop.type.isList) {
      if (value is! List) return false;
      return value.any(
        (e) =>
            e is MemoryObject &&
            _evaluate(embeddedSchema, filter.filter, e, id),
      );
    } else {
      if (value is! MemoryObject) return false;
      return _evaluate(embeddedSchema, filter.filter, value, id);
    }
  }

  bool _evaluateCondition(
    Schema<dynamic> objSchema,
    FilterCondition condition,
    MemoryObject object,
    Id id,
  ) {
    final value = propertyValue(objSchema, object, id, condition.property);

    final isIdProperty = objSchema is CollectionSchema &&
        condition.property == objSchema.idName;
    final isListProperty = !isIdProperty &&
        objSchema.property(condition.property).type.isList;

    switch (condition.type) {
      case FilterConditionType.listLength:
        final length = value is List ? value.length : 0;
        return length >= (condition.value1! as int) &&
            length <= (condition.value2! as int);
      case FilterConditionType.elementIsNull:
        return value is List && value.any(isNullish);
      case FilterConditionType.elementIsNotNull:
        return value is List && value.any((e) => !isNullish(e));
      // ignore: no_default_cases
      default:
        if (isListProperty) {
          if (value is! List) return false;
          return value.any((e) => _matchScalar(condition, e));
        }
        return _matchScalar(condition, value);
    }
  }

  bool _matchScalar(FilterCondition condition, dynamic stored) {
    final caseSensitive = condition.caseSensitive;

    dynamic variable = stored;
    dynamic val1 = encodeValue(condition.value1);
    dynamic val2 = encodeValue(condition.value2);

    if (!caseSensitive) {
      if (variable is String) variable = variable.toLowerCase();
      if (val1 is String) val1 = val1.toLowerCase();
      if (val2 is String) val2 = val2.toLowerCase();
    }

    switch (condition.type) {
      case FilterConditionType.equalTo:
        if (condition.value1 == null) {
          return isNullish(variable);
        }
        return _equals(variable, val1, condition.epsilon);
      case FilterConditionType.greaterThan:
        final cmp = compareValues(variable, val1);
        return condition.include1 ? cmp >= 0 : cmp > 0;
      case FilterConditionType.lessThan:
        final cmp = compareValues(variable, val1);
        return condition.include1 ? cmp <= 0 : cmp < 0;
      case FilterConditionType.between:
        final lower = val1;
        final upper = val2;
        if (lower != null) {
          final cmp = compareValues(variable, lower);
          if (condition.include1 ? cmp < 0 : cmp <= 0) return false;
        }
        if (upper != null) {
          final cmp = compareValues(variable, upper);
          if (condition.include2 ? cmp > 0 : cmp >= 0) return false;
        }
        if (lower == null && upper == null) {
          return isNullish(variable);
        }
        return true;
      case FilterConditionType.startsWith:
        return variable is String &&
            val1 is String &&
            variable.startsWith(val1);
      case FilterConditionType.endsWith:
        return variable is String &&
            val1 is String &&
            variable.endsWith(val1);
      case FilterConditionType.contains:
        return variable is String &&
            val1 is String &&
            variable.contains(val1);
      case FilterConditionType.matches:
        if (variable is! String || val1 is! String) return false;
        return _wildcardMatch(variable, val1, caseSensitive);
      case FilterConditionType.isNull:
        return isNullish(variable);
      case FilterConditionType.isNotNull:
        return !isNullish(variable);
      case FilterConditionType.listLength:
      case FilterConditionType.elementIsNull:
      case FilterConditionType.elementIsNotNull:
        return false;
    }
  }

  bool _equals(dynamic variable, dynamic val, double epsilon) {
    if (variable is double && val is num) {
      return (variable - val).abs() < epsilon;
    }
    if (variable is num && val is double) {
      return (variable - val).abs() < epsilon;
    }
    return compareValues(variable, val) == 0;
  }

  static bool _wildcardMatch(String value, String wildcard, bool cs) {
    final buffer = StringBuffer('^');
    for (final char in wildcard.split('')) {
      if (char == '*') {
        buffer.write('.*');
      } else if (char == '?') {
        buffer.write('.');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    final regex = RegExp(buffer.toString(), caseSensitive: cs);
    return regex.hasMatch(value);
  }
}
