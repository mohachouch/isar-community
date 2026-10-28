// ignore_for_file: public_member_api_docs

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/src/memory_filter.dart';
import 'package:isar_community_web_memory/src/memory_reader.dart';

/// In-memory storage for a single collection.
///
/// Objects are kept in a [Map] keyed by their id. Indexes are evaluated by
/// scanning the stored objects which keeps the implementation simple and
/// correct for the expected in-memory data set sizes.
class MemoryCollectionStore {
  MemoryCollectionStore(this.schema);

  final CollectionSchema<dynamic> schema;

  final Map<Id, MemoryObject> objects = <Id, MemoryObject>{};

  int _maxId = 0;

  // Snapshot used to roll back a failed write transaction.
  Map<Id, MemoryObject>? _snapshot;
  int _snapshotMaxId = 0;

  /// Returns the next auto-increment id.
  Id nextId() => ++_maxId;

  void registerId(Id id) {
    if (id > _maxId) {
      _maxId = id;
    }
  }

  void beginSnapshot() {
    _snapshot = Map<Id, MemoryObject>.of(objects);
    _snapshotMaxId = _maxId;
  }

  void commitSnapshot() {
    _snapshot = null;
  }

  void rollbackSnapshot() {
    if (_snapshot != null) {
      objects
        ..clear()
        ..addAll(_snapshot!);
      _maxId = _snapshotMaxId;
      _snapshot = null;
    }
  }

  void clear() {
    objects.clear();
    _maxId = 0;
  }

  /// Computes all index keys (encoded) produced by [object] for [index].
  ///
  /// Multi-entry indexes expand list properties into multiple keys.
  List<IndexKey> indexKeys(IndexSchema index, MemoryObject object) {
    var keys = <IndexKey>[<Object?>[]];
    for (final indexProperty in index.properties) {
      final parts = _keyParts(indexProperty, object);
      final newKeys = <IndexKey>[];
      for (final key in keys) {
        for (final part in parts) {
          newKeys.add(<Object?>[...key, part]);
        }
      }
      keys = newKeys;
    }
    return keys;
  }

  List<dynamic> _keyParts(
    IndexPropertySchema indexProperty,
    MemoryObject object,
  ) {
    final property = schema.property(indexProperty.name);
    final value = object[property.id];
    final multiEntry = property.type.isList &&
        indexProperty.type != IndexType.hash;
    if (multiEntry) {
      if (value is List && value.isNotEmpty) {
        return value.map((e) => _normalizeKeyPart(indexProperty, e)).toList();
      }
      return <dynamic>[null];
    }
    return <dynamic>[_normalizeKeyPart(indexProperty, value)];
  }

  dynamic _normalizeKeyPart(IndexPropertySchema indexProperty, dynamic value) {
    if (value is String && !indexProperty.caseSensitive) {
      return value.toLowerCase();
    }
    return value;
  }

  /// Encodes a raw [IndexKey] provided by the caller into its stored form.
  IndexKey encodeIndexKey(IndexSchema index, IndexKey key) {
    final result = <Object?>[];
    for (var i = 0; i < key.length; i++) {
      final indexProperty =
          i < index.properties.length ? index.properties[i] : null;
      final encoded = encodeValue(key[i]);
      if (encoded is String &&
          indexProperty != null &&
          !indexProperty.caseSensitive) {
        result.add(encoded.toLowerCase());
      } else {
        result.add(encoded);
      }
    }
    return result;
  }

  bool indexKeyEquals(IndexKey a, IndexKey b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (compareValues(a[i], b[i]) != 0) return false;
    }
    return true;
  }

  /// Finds the id of the object matching [encodedKey] for the unique [index],
  /// or `null` if no object matches.
  Id? findByIndex(IndexSchema index, IndexKey encodedKey) {
    for (final entry in objects.entries) {
      final keys = indexKeys(index, entry.value);
      for (final key in keys) {
        if (indexKeyEquals(key, encodedKey)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Checks and enforces unique index constraints for [id]/[object].
  ///
  /// Conflicting objects on a `replace` index are returned so the caller can
  /// delete them. Throws `IsarUniqueViolationError` otherwise.
  List<Id> enforceUniqueIndexes(Id id, MemoryObject object) {
    final toReplace = <Id>[];
    for (final index in schema.indexes.values) {
      if (!index.unique) continue;
      final keys = indexKeys(index, object);
      for (final entry in objects.entries) {
        if (entry.key == id) continue;
        final existingKeys = indexKeys(index, entry.value);
        final conflict = keys.any(
          (k) => existingKeys.any((e) => indexKeyEquals(k, e)),
        );
        if (conflict) {
          if (index.replace) {
            toReplace.add(entry.key);
          } else {
            throw IsarUniqueViolationError();
          }
        }
      }
    }
    return toReplace;
  }
}
