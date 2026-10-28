// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/src/memory_collection.dart';
import 'package:isar_community_web_memory/src/memory_engine.dart';

/// A pure-Dart, in-memory [Isar] instance.
///
/// All data lives in RAM for the lifetime of the instance and is never
/// persisted. Transactions are executed synchronously; the asynchronous
/// variants simply complete immediately.
class MemoryIsar extends Isar {
  MemoryIsar(super.name, this.stores, this.offsets);

  final Map<String, MemoryCollectionStore> stores;
  final Map<Type, List<int>> offsets;

  final Map<String, MemoryCollection<dynamic>> _memCollections =
      <String, MemoryCollection<dynamic>>{};

  bool _inTxn = false;
  bool _writeTxn = false;

  final Map<String, Set<Id>> _changedIds = <String, Set<Id>>{};
  final Set<String> _changedAll = <String>{};

  @override
  final String? directory = null;

  void attachMemoryCollections(
    Map<String, MemoryCollection<dynamic>> collections,
  ) {
    _memCollections.addAll(collections);
  }

  bool get inWriteTxn => _inTxn && _writeTxn;

  /// Throws unless currently inside a write transaction.
  void requireWriteTxn() {
    requireOpen();
    if (!inWriteTxn) {
      throw IsarError(
        'Write operations require an explicit transaction. '
        'Use isar.writeTxn() or isar.writeTxnSync().',
      );
    }
  }

  void recordChange(String collection, Id id) {
    if (!_changedAll.contains(collection)) {
      (_changedIds[collection] ??= <Id>{}).add(id);
    }
  }

  void recordChangeAll(String collection) {
    _changedAll.add(collection);
    _changedIds.remove(collection);
  }

  T _runTxn<T>(bool write, bool silent, T Function() callback) {
    requireOpen();
    if (_inTxn) {
      throw IsarError(
        'Cannot start a transaction from within another transaction.',
      );
    }
    _inTxn = true;
    _writeTxn = write;
    _changedIds.clear();
    _changedAll.clear();

    if (write) {
      for (final store in stores.values) {
        store.beginSnapshot();
      }
    }

    try {
      final result = callback();
      if (write) {
        for (final store in stores.values) {
          store.commitSnapshot();
        }
      }
      _inTxn = false;
      _writeTxn = false;
      if (write && !silent) {
        _flushChanges();
      }
      return result;
    } catch (_) {
      if (write) {
        for (final store in stores.values) {
          store.rollbackSnapshot();
        }
      }
      _inTxn = false;
      _writeTxn = false;
      _changedIds.clear();
      _changedAll.clear();
      rethrow;
    }
  }

  void _flushChanges() {
    final collections = <String>{..._changedIds.keys, ..._changedAll};
    for (final name in collections) {
      final collection = _memCollections[name];
      if (collection == null) continue;
      if (_changedAll.contains(name)) {
        collection.notifyChange(null);
      } else {
        collection.notifyChange(_changedIds[name]);
      }
    }
    _changedIds.clear();
    _changedAll.clear();
  }

  @override
  Future<T> txn<T>(Future<T> Function() callback) async {
    // Reads do not require isolation; run directly while flagging the zone.
    return _runAsyncTxn(false, false, callback);
  }

  @override
  Future<T> writeTxn<T>(
    Future<T> Function() callback, {
    bool silent = false,
  }) async {
    return _runAsyncTxn(true, silent, callback);
  }

  Future<T> _runAsyncTxn<T>(
    bool write,
    bool silent,
    Future<T> Function() callback,
  ) async {
    requireOpen();
    if (_inTxn) {
      throw IsarError(
        'Cannot start a transaction from within another transaction.',
      );
    }
    _inTxn = true;
    _writeTxn = write;
    _changedIds.clear();
    _changedAll.clear();

    if (write) {
      for (final store in stores.values) {
        store.beginSnapshot();
      }
    }

    try {
      final result = await callback();
      if (write) {
        for (final store in stores.values) {
          store.commitSnapshot();
        }
      }
      _inTxn = false;
      _writeTxn = false;
      if (write && !silent) {
        _flushChanges();
      }
      return result;
    } catch (_) {
      if (write) {
        for (final store in stores.values) {
          store.rollbackSnapshot();
        }
      }
      _inTxn = false;
      _writeTxn = false;
      _changedIds.clear();
      _changedAll.clear();
      rethrow;
    }
  }

  @override
  T txnSync<T>(T Function() callback) => _runTxn(false, false, callback);

  @override
  T writeTxnSync<T>(T Function() callback, {bool silent = false}) =>
      _runTxn(true, silent, callback);

  @override
  Future<int> getSize({
    bool includeIndexes = false,
    bool includeLinks = false,
  }) async =>
      getSizeSync(includeIndexes: includeIndexes, includeLinks: includeLinks);

  @override
  int getSizeSync({bool includeIndexes = false, bool includeLinks = false}) {
    // Not meaningful for an in-memory store.
    return 0;
  }

  @override
  Future<void> copyToFile(String targetPath) {
    throw UnsupportedError(
      'copyToFile is not supported by the in-memory Isar backend.',
    );
  }

  @override
  Future<bool> close({bool deleteFromDisk = false}) async {
    requireOpen();
    for (final store in stores.values) {
      store.clear();
    }
    await super.close();
    return true;
  }

  @override
  Future<void> verify() async {}
}
