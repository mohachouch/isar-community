// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/src/memory_collection.dart';
import 'package:isar_community_web_memory/src/memory_filter.dart';
import 'package:isar_community_web_memory/src/memory_reader.dart';

typedef MemoryDeserialize<T> = T Function(Id id, MemoryObject object);

class MemoryQuery<T> extends Query<T> {
  MemoryQuery({
    required this.collection,
    required this.deserialize,
    required this.whereClauses,
    required this.whereDistinct,
    required this.whereSort,
    required this.filter,
    required this.sortBy,
    required this.distinctBy,
    required this.offset,
    required this.limit,
    required this.property,
  });

  final MemoryCollection<dynamic> collection;
  final MemoryDeserialize<T> deserialize;
  final List<WhereClause> whereClauses;
  final bool whereDistinct;
  final Sort whereSort;
  final FilterOperation? filter;
  final List<SortProperty> sortBy;
  final List<DistinctProperty> distinctBy;
  final int? offset;
  final int? limit;
  final String? property;

  CollectionSchema<dynamic> get schema => collection.schema;

  MemoryFilter get _filter => collection.memoryFilter;

  @override
  Isar get isar => collection.isar;

  /// Returns the ordered, filtered list of matching entries.
  List<MapEntry<Id, MemoryObject>> matchedEntries() {
    var entries = _applyWhereClauses();

    final filterOp = filter;
    if (filterOp != null) {
      entries = entries
          .where((e) => _filter.evaluate(filterOp, e.value, e.key))
          .toList();
    }

    if (sortBy.isNotEmpty) {
      entries = _stableSort(entries);
    }

    if (distinctBy.isNotEmpty) {
      entries = _applyDistinct(entries);
    }

    final start = offset ?? 0;
    if (start > 0) {
      entries = start < entries.length
          ? entries.sublist(start)
          : <MapEntry<Id, MemoryObject>>[];
    }
    final max = limit;
    if (max != null && max < entries.length) {
      entries = entries.sublist(0, max);
    }
    return entries;
  }

  List<MapEntry<Id, MemoryObject>> _applyWhereClauses() {
    if (whereClauses.isEmpty) {
      final entries = collection.store.objects.entries.toList()
        ..sort(
          (a, b) => whereSort == Sort.asc
              ? a.key.compareTo(b.key)
              : b.key.compareTo(a.key),
        );
      return entries;
    }

    final seen = <Id>{};
    final result = <MapEntry<Id, MemoryObject>>[];
    for (final clause in whereClauses) {
      for (final entry in _applyClause(clause)) {
        if (seen.add(entry.key)) {
          result.add(entry);
        }
      }
    }
    return result;
  }

  List<MapEntry<Id, MemoryObject>> _applyClause(WhereClause clause) {
    if (clause is IdWhereClause) {
      return _applyIdClause(clause);
    } else if (clause is IndexWhereClause) {
      return _applyIndexClause(clause);
    } else if (clause is LinkWhereClause) {
      throw UnsupportedError(
        'Link where clauses are not supported by the in-memory Isar backend.',
      );
    }
    return <MapEntry<Id, MemoryObject>>[];
  }

  List<MapEntry<Id, MemoryObject>> _applyIdClause(IdWhereClause clause) {
    bool inRange(Id id) {
      final lower = clause.lower;
      final upper = clause.upper;
      if (lower != null) {
        if (clause.includeLower ? id < lower : id <= lower) return false;
      }
      if (upper != null) {
        if (clause.includeUpper ? id > upper : id >= upper) return false;
      }
      return true;
    }

    final entries =
        collection.store.objects.entries.where((e) => inRange(e.key)).toList()
          ..sort(
            (a, b) => whereSort == Sort.asc
                ? a.key.compareTo(b.key)
                : b.key.compareTo(a.key),
          );
    return entries;
  }

  List<MapEntry<Id, MemoryObject>> _applyIndexClause(IndexWhereClause clause) {
    final index = schema.index(clause.indexName);
    final store = collection.store;
    final lower = clause.lower != null
        ? store.encodeIndexKey(index, clause.lower!)
        : null;
    final upper = clause.upper != null
        ? store.encodeIndexKey(index, clause.upper!)
        : null;

    bool inRange(IndexKey key) {
      if (lower != null) {
        final cmp = _compareIndexKey(key, lower);
        if (clause.includeLower ? cmp < 0 : cmp <= 0) return false;
      }
      if (upper != null) {
        final cmp = _compareIndexKey(key, upper);
        if (clause.includeUpper ? cmp > 0 : cmp >= 0) return false;
      }
      return true;
    }

    final items = <_IndexedEntry>[];
    for (final entry in store.objects.entries) {
      for (final key in store.indexKeys(index, entry.value)) {
        if (inRange(key)) {
          items.add(_IndexedEntry(key, entry));
        }
      }
    }

    items.sort((a, b) {
      final cmp = _compareIndexKey(a.key, b.key);
      return whereSort == Sort.asc ? cmp : -cmp;
    });

    final result = <MapEntry<Id, MemoryObject>>[];
    final seenKeys = <String>{};
    for (final item in items) {
      if (whereDistinct) {
        final keyStr = item.key.map((e) => e.toString()).join('\u0000');
        if (!seenKeys.add(keyStr)) continue;
      }
      result.add(item.entry);
    }
    return result;
  }

  int _compareIndexKey(IndexKey a, IndexKey b) {
    final length = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final cmp = compareValues(a[i], b[i]);
      if (cmp != 0) return cmp;
    }
    return a.length.compareTo(b.length);
  }

  List<MapEntry<Id, MemoryObject>> _stableSort(
    List<MapEntry<Id, MemoryObject>> entries,
  ) {
    final indexed = <MapEntry<int, MapEntry<Id, MemoryObject>>>[
      for (var i = 0; i < entries.length; i++) MapEntry(i, entries[i]),
    ];
    indexed.sort((a, b) {
      for (final sortProperty in sortBy) {
        final va = _filter.propertyValue(
          schema,
          a.value.value,
          a.value.key,
          sortProperty.property,
        );
        final vb = _filter.propertyValue(
          schema,
          b.value.value,
          b.value.key,
          sortProperty.property,
        );
        var cmp = compareValues(va, vb);
        if (sortProperty.sort == Sort.desc) cmp = -cmp;
        if (cmp != 0) return cmp;
      }
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  List<MapEntry<Id, MemoryObject>> _applyDistinct(
    List<MapEntry<Id, MemoryObject>> entries,
  ) {
    final seen = <String>{};
    final result = <MapEntry<Id, MemoryObject>>[];
    for (final entry in entries) {
      final parts = <String>[];
      for (final distinct in distinctBy) {
        var value = _filter.propertyValue(
          schema,
          entry.value,
          entry.key,
          distinct.property,
        );
        if (value is String && distinct.caseSensitive == false) {
          value = value.toLowerCase();
        }
        parts.add(isNullish(value) ? '\u0000null' : value.toString());
      }
      if (seen.add(parts.join('\u0001'))) {
        result.add(entry);
      }
    }
    return result;
  }

  List<T> _results() {
    return matchedEntries()
        .map((e) => deserialize(e.key, e.value))
        .toList();
  }

  @override
  Future<T?> findFirst() async => findFirstSync();

  @override
  T? findFirstSync() {
    final entries = matchedEntries();
    if (entries.isEmpty) return null;
    return deserialize(entries.first.key, entries.first.value);
  }

  @override
  Future<List<T>> findAll() async => findAllSync();

  @override
  List<T> findAllSync() => _results();

  @override
  Future<R?> aggregate<R>(AggregationOp op) async => aggregateSync<R>(op);

  @override
  R? aggregateSync<R>(AggregationOp op) {
    final entries = matchedEntries();

    if (op == AggregationOp.count) {
      return entries.length as R;
    }
    if (op == AggregationOp.isEmpty) {
      return (entries.isEmpty ? 1 : 0) as R;
    }

    final propertyName = property ?? schema.idName;
    final values = <num>[];
    for (final entry in entries) {
      final value = _filter.propertyValue(
        schema,
        entry.value,
        entry.key,
        propertyName,
      );
      if (!isNullish(value) && value is num) {
        values.add(value);
      }
    }

    num? result;
    switch (op) {
      case AggregationOp.min:
        result = values.isEmpty
            ? null
            : values.reduce((a, b) => a < b ? a : b);
        break;
      case AggregationOp.max:
        result = values.isEmpty
            ? null
            : values.reduce((a, b) => a > b ? a : b);
        break;
      case AggregationOp.sum:
        result = values.fold<num>(0, (a, b) => a + b);
        break;
      case AggregationOp.average:
        result = values.isEmpty
            ? double.nan
            : values.fold<num>(0, (a, b) => a + b) / values.length;
        break;
      // ignore: no_default_cases
      default:
        throw UnimplementedError();
    }

    if (result == null) return null;
    if (R == DateTime) {
      return DateTime.fromMillisecondsSinceEpoch(result.toInt(), isUtc: true)
          .toLocal() as R;
    } else if (R == int) {
      return result.toInt() as R;
    } else if (R == double) {
      return result.toDouble() as R;
    } else {
      return result as R;
    }
  }

  @override
  Future<bool> deleteFirst() async => deleteFirstSync();

  @override
  bool deleteFirstSync() {
    collection.isarImpl.requireWriteTxn();
    final entries = matchedEntries();
    if (entries.isEmpty) return false;
    collection.deleteInternal(entries.first.key);
    return true;
  }

  @override
  Future<int> deleteAll() async => deleteAllSync();

  @override
  int deleteAllSync() {
    collection.isarImpl.requireWriteTxn();
    final entries = matchedEntries();
    for (final entry in entries) {
      collection.deleteInternal(entry.key);
    }
    return entries.length;
  }

  @override
  Stream<List<T>> watch({bool fireImmediately = false}) {
    late final StreamController<List<T>> controller;
    void Function()? remove;
    controller = StreamController<List<T>>(
      onListen: () {
        if (fireImmediately) {
          controller.add(findAllSync());
        }
        remove = collection.addWatcher(() {
          controller.add(findAllSync());
        });
      },
      onCancel: () => remove?.call(),
    );
    return controller.stream;
  }

  @override
  Stream<void> watchLazy({bool fireImmediately = false}) {
    late final StreamController<void> controller;
    void Function()? remove;
    controller = StreamController<void>(
      onListen: () {
        if (fireImmediately) {
          controller.add(null);
        }
        remove = collection.addWatcher(() => controller.add(null));
      },
      onCancel: () => remove?.call(),
    );
    return controller.stream;
  }

  @override
  Future<R> exportJsonRaw<R>(R Function(Uint8List) callback) async {
    return exportJsonRawSync(callback);
  }

  @override
  R exportJsonRawSync<R>(R Function(Uint8List) callback) {
    final json = exportJsonSync();
    final jsonStr = jsonEncode(json);
    return callback(Uint8List.fromList(utf8.encode(jsonStr)));
  }

  @override
  Future<List<Map<String, dynamic>>> exportJson() async => exportJsonSync();

  @override
  List<Map<String, dynamic>> exportJsonSync() {
    return matchedEntries()
        .map((e) => collection.objectToJson(e.key, e.value))
        .toList();
  }
}

class _IndexedEntry {
  _IndexedEntry(this.key, this.entry);

  final IndexKey key;
  final MapEntry<Id, MemoryObject> entry;
}
