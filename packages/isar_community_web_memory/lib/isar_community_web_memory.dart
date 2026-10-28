/// A pure-Dart, in-memory implementation of [Isar].
///
/// This package provides a drop-in Isar backend that keeps all data in RAM.
/// It works on every platform (web, VM and Flutter) without FFI or IndexedDB,
/// which makes it convenient for tests and for web apps that only need
/// ephemeral storage for the lifetime of the page.
///
/// Data is **never persisted** and is **not shared** between isolates, tabs or
/// instances. See the README for the full list of limitations.
library isar_community_web_memory;

// ignore_for_file: invalid_use_of_protected_member

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/src/memory_collection.dart';
import 'package:isar_community_web_memory/src/memory_engine.dart';
import 'package:isar_community_web_memory/src/memory_isar.dart';

/// Opens an in-memory [Isar] instance asynchronously.
///
/// The returned instance keeps every collection in RAM for its lifetime and
/// never writes to disk. [schemas] is the list of generated collection schemas,
/// exactly as you would pass to [Isar.open]. [name] identifies the instance;
/// opening a second instance with the same [name] throws, matching Isar's
/// behaviour.
Future<Isar> openIsarInMemory({
  required List<CollectionSchema<dynamic>> schemas,
  String name = Isar.defaultName,
}) async {
  return openIsarInMemorySync(schemas: schemas, name: name);
}

/// Opens an in-memory [Isar] instance synchronously.
///
/// See [openIsarInMemory] for details.
Isar openIsarInMemorySync({
  required List<CollectionSchema<dynamic>> schemas,
  String name = Isar.defaultName,
}) {
  _checkOpen(name, schemas);

  final offsets = <Type, List<int>>{};
  final stores = <String, MemoryCollectionStore>{};

  for (final schema in schemas) {
    offsets[schema.type] = _identityOffsets(schema.properties.length);
    for (final embedded in schema.embeddedSchemas.values) {
      offsets[embedded.type] = _identityOffsets(embedded.properties.length);
    }
    stores[schema.name] = MemoryCollectionStore(schema);
  }

  final isar = MemoryIsar(name, stores, offsets);

  final collections = <Type, IsarCollection<dynamic>>{};
  final memoryCollections = <String, MemoryCollection<dynamic>>{};
  for (final schema in schemas) {
    schema.toCollection(<OBJ>() {
      final typedSchema = schema as CollectionSchema<OBJ>;
      final collection = MemoryCollection<OBJ>(
        isarImpl: isar,
        schema: typedSchema,
        store: stores[schema.name]!,
        allOffsets: offsets,
      );
      collections[OBJ] = collection;
      memoryCollections[schema.name] = collection;
    });
  }

  isar.attachCollections(collections);
  isar.attachMemoryCollections(memoryCollections);
  return isar;
}

List<int> _identityOffsets(int length) =>
    List<int>.generate(length, (i) => i, growable: false);

void _checkOpen(String name, List<CollectionSchema<dynamic>> schemas) {
  if (name.isEmpty || name.startsWith('_')) {
    throw IsarError('Instance names must not be empty or start with "_".');
  }
  if (Isar.getInstance(name) != null) {
    throw IsarError('Instance has already been opened.');
  }
  if (schemas.isEmpty) {
    throw IsarError('At least one collection needs to be opened.');
  }

  final schemaNames = <String>{};
  for (final schema in schemas) {
    if (!schemaNames.add(schema.name)) {
      throw IsarError('Duplicate collection ${schema.name}.');
    }
  }
}
