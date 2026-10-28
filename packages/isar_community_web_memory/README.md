# isar_community_web_memory

An in-memory (RAM only, **non-persistent**) implementation of the
[`isar_community`](https://pub.dev/packages/isar_community) database.

It is a pure-Dart drop-in Isar backend that keeps every collection in memory for
the lifetime of the instance. It works on **every platform** (web, VM and
Flutter) **without FFI, native binaries or IndexedDB**, which makes it ideal
for:

- the **web**, when you only need ephemeral storage for the lifetime of the page;
- **unit tests**, where you want a fast, isolated database without touching disk;
- quick prototypes and examples.

## Features

- Open with an explicit, non-intrusive API: `openIsarInMemory` /
  `openIsarInMemorySync`.
- CRUD by id and by unique index (`get`/`put`/`delete`, `getByIndex`/
  `putByIndex`/`deleteByIndex`).
- Auto-increment ids.
- Unique, non-unique and multi-entry indexes.
- Queries: where clauses, filters, sorting, `distinct`, `offset`/`limit`.
- Aggregations: `count`, `min`, `max`, `sum`, `average`, `isEmpty`.
- JSON import/export.
- Watchers: collection, object and query watchers (scoped to the instance).
- Synchronous **and** asynchronous transactions with rollback on error.

## Limitations

This backend trades persistence and advanced features for simplicity:

- **No persistence.** All data lives in RAM and is lost when the instance is
  closed or the page is reloaded.
- **No cross-isolate / cross-tab sharing.** Watchers only notify listeners of
  the same instance; there is no `BroadcastChannel` multi-tab synchronization.
- **Links and backlinks (`IsarLink`/`IsarLinks`) are not supported.** The Isar
  link factories are bound at compile time to the native/web implementation, so
  they cannot be backed by a custom collection. Link usage throws
  `UnsupportedError`.
- **No full-text search index helpers** beyond the standard query filters.
- Writes must happen inside a `writeTxn`/`writeTxnSync`, matching Isar's
  behaviour.

> **Web compilation note:** Isar's generated `*.g.dart` schema files contain
> 64-bit integer ids. When compiling to JavaScript with `dart2js`, these
> literals exceed the safe-integer range. This is an upstream limitation of the
> Isar code generator that affects **all** Isar web usage, not this package in
> particular.

## Usage

Define your collections exactly as you would with Isar and run the Isar
generator:

```dart
import 'package:isar_community/isar.dart';

part 'user.g.dart';

@collection
class User {
  User({required this.name});

  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  final String name;
}
```

Then open an in-memory instance instead of calling `Isar.open`:

```dart
import 'package:isar_community_web_memory/isar_community_web_memory.dart';

Future<void> main() async {
  final isar = await openIsarInMemory(schemas: [UserSchema]);

  await isar.writeTxn(() async {
    await isar.users.put(User(name: 'Alice'));
  });

  final alice = await isar.users.getByName('Alice');
  print(alice?.name); // Alice

  await isar.close();
}
```

A synchronous variant is also available:

```dart
final isar = openIsarInMemorySync(schemas: [UserSchema]);
isar.writeTxnSync(() => isar.users.putSync(User(name: 'Bob')));
```

## Testing

Run the tests on the Dart VM:

```sh
dart test -p vm
```

Run the web suite in Chrome (compiled to JavaScript with `dart2js`):

```sh
dart test -p chrome
```

The VM suite (`test/memory_test.dart`) uses Isar's generated schemas, while the
Chrome suite (`test/web_test.dart`) uses a hand-written, JavaScript-safe schema.
This split is necessary because Isar's code generator emits 64-bit `xxh3` ids
that `dart2js` cannot represent exactly — an upstream limitation of the
generator, not of this package. The in-memory engine itself runs on Chrome
unchanged.

## License

See [LICENSE](LICENSE). This package is part of the
[`isar-community`](https://github.com/isar-community/isar-community) project.
