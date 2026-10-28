// ignore_for_file: public_member_api_docs
// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/src/memory_engine.dart';
import 'package:isar_community_web_memory/src/memory_filter.dart';
import 'package:isar_community_web_memory/src/memory_isar.dart';
import 'package:isar_community_web_memory/src/memory_json.dart';
import 'package:isar_community_web_memory/src/memory_query.dart';
import 'package:isar_community_web_memory/src/memory_reader.dart';
import 'package:isar_community_web_memory/src/memory_writer.dart';

class MemoryCollection<OBJ> extends IsarCollection<OBJ> {
  MemoryCollection({
    required this.isarImpl,
    required this.schema,
    required this.store,
    required this.allOffsets,
  })  : memoryFilter = MemoryFilter(schema),
        _jsonCodec = MemoryJsonCodec(schema, schema.embeddedSchemas);

  final MemoryIsar isarImpl;

  @override
  final CollectionSchema<OBJ> schema;

  final MemoryCollectionStore store;
  final Map<Type, List<int>> allOffsets;
  final MemoryFilter memoryFilter;
  final MemoryJsonCodec _jsonCodec;

  final List<void Function()> _anyWatchers = <void Function()>[];
  final List<_ObjectWatcher> _objectWatchers = <_ObjectWatcher>[];

  @override
  Isar get isar => isarImpl;

  @override
  String get name => schema.name;

  List<int> get _offsets => allOffsets[OBJ]!;

  // --- Serialization -------------------------------------------------------

  MemoryObject serializeObject(OBJ object) {
    final memory = <int, dynamic>{};
    final writer = MemoryWriter(memory);
    schema.serialize(object, writer, _offsets, allOffsets);
    return memory;
  }

  OBJ deserializeObject(Id id, MemoryObject object) {
    final reader = MemoryReader(object);
    return schema.deserialize(id, reader, _offsets, allOffsets);
  }

  Map<String, dynamic> objectToJson(Id id, MemoryObject object) =>
      _jsonCodec.toJson(id, object);

  // --- Watchers ------------------------------------------------------------

  void Function() addWatcher(void Function() callback) {
    _anyWatchers.add(callback);
    return () => _anyWatchers.remove(callback);
  }

  void Function() _addObjectWatcher(Id id, void Function() callback) {
    final watcher = _ObjectWatcher(id, callback);
    _objectWatchers.add(watcher);
    return () => _objectWatchers.remove(watcher);
  }

  void notifyChange(Set<Id>? changedIds) {
    for (final callback in _anyWatchers.toList()) {
      callback();
    }
    for (final watcher in _objectWatchers.toList()) {
      if (changedIds == null || changedIds.contains(watcher.id)) {
        watcher.callback();
      }
    }
  }

  // --- Read ----------------------------------------------------------------

  @override
  Future<List<OBJ?>> getAll(List<Id> ids) async => getAllSync(ids);

  @override
  List<OBJ?> getAllSync(List<Id> ids) {
    return ids.map((id) {
      final object = store.objects[id];
      return object == null ? null : deserializeObject(id, object);
    }).toList();
  }

  @override
  Future<List<OBJ?>> getAllByIndex(String indexName, List<IndexKey> keys) async =>
      getAllByIndexSync(indexName, keys);

  @override
  List<OBJ?> getAllByIndexSync(String indexName, List<IndexKey> keys) {
    final index = schema.index(indexName);
    return keys.map((key) {
      final encoded = store.encodeIndexKey(index, key);
      final id = store.findByIndex(index, encoded);
      if (id == null) return null;
      return deserializeObject(id, store.objects[id]!);
    }).toList();
  }

  // --- Write ---------------------------------------------------------------

  @override
  Future<List<Id>> putAll(List<OBJ> objects) async => putAllSync(objects);

  @override
  List<Id> putAllSync(List<OBJ> objects, {bool saveLinks = true}) {
    return _putAll(null, objects);
  }

  @override
  Future<List<Id>> putAllByIndex(String indexName, List<OBJ> objects) async =>
      putAllByIndexSync(indexName, objects);

  @override
  List<Id> putAllByIndexSync(
    String indexName,
    List<OBJ> objects, {
    bool saveLinks = true,
  }) {
    return _putAll(indexName, objects);
  }

  List<Id> _putAll(String? indexName, List<OBJ> objects) {
    isarImpl.requireWriteTxn();
    final ids = <Id>[];
    for (final object in objects) {
      final memory = serializeObject(object);

      Id? id;
      if (indexName != null) {
        final index = schema.index(indexName);
        final keys = store.indexKeys(index, memory);
        if (keys.isNotEmpty) {
          id = store.findByIndex(index, keys.first);
        }
      }

      if (id == null) {
        final rawId = schema.getId(object);
        if (rawId == Isar.autoIncrement) {
          id = store.nextId();
        } else {
          id = rawId;
          store.registerId(id);
        }
      }

      final replaced = store.enforceUniqueIndexes(id, memory);
      for (final replacedId in replaced) {
        _deleteInternal(replacedId);
      }

      store.objects[id] = memory;
      store.registerId(id);
      schema.attach(this, id, object);
      isarImpl.recordChange(name, id);
      ids.add(id);
    }
    return ids;
  }

  @override
  Future<int> deleteAll(List<Id> ids) async => deleteAllSync(ids);

  @override
  int deleteAllSync(List<Id> ids) {
    isarImpl.requireWriteTxn();
    var count = 0;
    for (final id in ids) {
      if (_deleteInternal(id)) {
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> deleteAllByIndex(String indexName, List<IndexKey> keys) async =>
      deleteAllByIndexSync(indexName, keys);

  @override
  int deleteAllByIndexSync(String indexName, List<IndexKey> keys) {
    isarImpl.requireWriteTxn();
    final index = schema.index(indexName);
    var count = 0;
    for (final key in keys) {
      final encoded = store.encodeIndexKey(index, key);
      final id = store.findByIndex(index, encoded);
      if (id != null && _deleteInternal(id)) {
        count++;
      }
    }
    return count;
  }

  bool _deleteInternal(Id id) {
    final removed = store.objects.remove(id);
    if (removed != null) {
      isarImpl.recordChange(name, id);
      return true;
    }
    return false;
  }

  /// Used by [MemoryQuery] to delete a matched object.
  void deleteInternal(Id id) => _deleteInternal(id);

  @override
  Future<void> clear() async => clearSync();

  @override
  void clearSync() {
    isarImpl.requireWriteTxn();
    store.clear();
    isarImpl.recordChangeAll(name);
  }

  // --- JSON ----------------------------------------------------------------

  @override
  Future<void> importJson(List<Map<String, dynamic>> json) async =>
      importJsonSync(json);

  @override
  void importJsonSync(List<Map<String, dynamic>> json) {
    isarImpl.requireWriteTxn();
    for (final entry in json) {
      final memory = _jsonCodec.fromJson(entry);
      var id = _jsonCodec.idFromJson(entry);
      if (id == null || id == Isar.autoIncrement) {
        id = store.nextId();
      } else {
        store.registerId(id);
      }
      final replaced = store.enforceUniqueIndexes(id, memory);
      for (final replacedId in replaced) {
        _deleteInternal(replacedId);
      }
      store.objects[id] = memory;
      store.registerId(id);
      isarImpl.recordChange(name, id);
    }
  }

  @override
  Future<void> importJsonRaw(Uint8List jsonBytes) async =>
      importJsonRawSync(jsonBytes);

  @override
  void importJsonRawSync(Uint8List jsonBytes) {
    final decoded = jsonDecode(utf8.decode(jsonBytes)) as List;
    importJsonSync(decoded.cast<Map<String, dynamic>>());
  }

  // --- Aggregation / size --------------------------------------------------

  @override
  Future<int> count() async => countSync();

  @override
  int countSync() => store.objects.length;

  @override
  Future<int> getSize({
    bool includeIndexes = false,
    bool includeLinks = false,
  }) async =>
      getSizeSync(includeIndexes: includeIndexes, includeLinks: includeLinks);

  @override
  int getSizeSync({bool includeIndexes = false, bool includeLinks = false}) => 0;

  // --- Watch ---------------------------------------------------------------

  @override
  Stream<void> watchLazy({bool fireImmediately = false}) {
    late final StreamController<void> controller;
    void Function()? remove;
    controller = StreamController<void>(
      onListen: () {
        if (fireImmediately) {
          controller.add(null);
        }
        remove = addWatcher(() => controller.add(null));
      },
      onCancel: () => remove?.call(),
    );
    return controller.stream;
  }

  @override
  Stream<OBJ?> watchObject(
    Id id, {
    bool fireImmediately = false,
    bool deserialize = true,
  }) {
    late final StreamController<OBJ?> controller;
    void Function()? remove;
    controller = StreamController<OBJ?>(
      onListen: () {
        if (fireImmediately) {
          controller.add(getSync(id));
        }
        remove = _addObjectWatcher(id, () => controller.add(getSync(id)));
      },
      onCancel: () => remove?.call(),
    );
    return controller.stream;
  }

  @override
  Stream<void> watchObjectLazy(Id id, {bool fireImmediately = false}) {
    late final StreamController<void> controller;
    void Function()? remove;
    controller = StreamController<void>(
      onListen: () {
        if (fireImmediately) {
          controller.add(null);
        }
        remove = _addObjectWatcher(id, () => controller.add(null));
      },
      onCancel: () => remove?.call(),
    );
    return controller.stream;
  }

  // --- Query ---------------------------------------------------------------

  @override
  Query<R> buildQuery<R>({
    List<WhereClause> whereClauses = const [],
    bool whereDistinct = false,
    Sort whereSort = Sort.asc,
    FilterOperation? filter,
    List<SortProperty> sortBy = const [],
    List<DistinctProperty> distinctBy = const [],
    int? offset,
    int? limit,
    String? property,
  }) {
    final MemoryDeserialize<R> deserialize;
    if (property == null) {
      deserialize = (id, object) => deserializeObject(id, object) as R;
    } else if (property == schema.idName) {
      deserialize = (id, object) => id as R;
    } else {
      final propertyId = schema.property(property).id;
      deserialize = (id, object) {
        final reader = MemoryReader(object);
        return schema.deserializeProp(
          reader,
          propertyId,
          propertyId,
          allOffsets,
        ) as R;
      };
    }

    return MemoryQuery<R>(
      collection: this,
      deserialize: deserialize,
      whereClauses: whereClauses,
      whereDistinct: whereDistinct,
      whereSort: whereSort,
      filter: filter,
      sortBy: sortBy,
      distinctBy: distinctBy,
      offset: offset,
      limit: limit,
      property: property,
    );
  }

  // --- Verification --------------------------------------------------------

  @override
  Future<void> verify(List<OBJ> objects) async {
    final expected = <Id, MemoryObject>{};
    for (final object in objects) {
      expected[schema.getId(object)] = serializeObject(object);
    }
    if (expected.length != store.objects.length) {
      throw IsarError('Verification failed: object count mismatch.');
    }
    for (final entry in expected.entries) {
      final actual = store.objects[entry.key];
      if (actual == null || !_deepEquals(actual, entry.value)) {
        throw IsarError('Verification failed for object ${entry.key}.');
      }
    }
  }

  @override
  Future<void> verifyLink(
    String linkName,
    List<int> sourceIds,
    List<int> targetIds,
  ) {
    throw UnsupportedError(
      'Links are not supported by the in-memory Isar backend.',
    );
  }

  static bool _deepEquals(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    } else if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}

class _ObjectWatcher {
  _ObjectWatcher(this.id, this.callback);

  final Id id;
  final void Function() callback;
}
