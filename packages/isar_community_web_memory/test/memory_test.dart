@TestOn('vm')
library memory_test;

// ignore_for_file: invalid_use_of_protected_member

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/isar_community_web_memory.dart';
import 'package:test/test.dart';

part 'memory_test.g.dart';

@collection
class User {
  User({
    this.id = Isar.autoIncrement,
    required this.name,
    required this.age,
    this.tags = const [],
  });

  Id id;

  @Index(unique: true, replace: true)
  final String name;

  @Index()
  final int age;

  @Index(type: IndexType.value)
  final List<String> tags;
}

late Isar isar;

void main() {
  setUp(() async {
    isar = await openIsarInMemory(
      schemas: [UserSchema],
      name: 'test_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    await isar.close();
  });

  test('put and get by id with auto increment', () async {
    final id = await isar.writeTxn(() => isar.users.put(User(name: 'a', age: 1)));
    expect(id, 1);
    final user = await isar.users.get(id);
    expect(user!.name, 'a');
    expect(user.age, 1);
  });

  test('requires write transaction', () async {
    expect(
      () => isar.users.put(User(name: 'x', age: 1)),
      throwsA(isA<IsarError>()),
    );
  });

  test('update, delete and count', () async {
    await isar.writeTxn(() async {
      await isar.users.putAll([
        User(name: 'a', age: 10),
        User(name: 'b', age: 20),
        User(name: 'c', age: 30),
      ]);
    });
    expect(await isar.users.count(), 3);

    await isar.writeTxn(() => isar.users.delete(2));
    expect(await isar.users.count(), 2);
    expect(await isar.users.get(2), isNull);
  });

  test('filter, sort, offset and limit', () async {
    await isar.writeTxn(() async {
      await isar.users.putAll([
        User(name: 'a', age: 10),
        User(name: 'b', age: 20),
        User(name: 'c', age: 30),
        User(name: 'd', age: 40),
      ]);
    });

    final result = await isar.users
        .filter()
        .ageGreaterThan(10)
        .sortByAgeDesc()
        .offset(1)
        .limit(2)
        .findAll();
    expect(result.map((e) => e.age), [30, 20]);
  });

  test('unique replace index', () async {
    await isar.writeTxn(() => isar.users.put(User(name: 'dup', age: 1)));
    await isar.writeTxn(() => isar.users.put(User(name: 'dup', age: 2)));
    final all = await isar.users.where().findAll();
    expect(all.length, 1);
    expect(all.single.age, 2);
  });

  test('getByIndex / putByIndex', () async {
    await isar.writeTxn(
      () => isar.users.putByName(User(name: 'idx', age: 5)),
    );
    final user = await isar.users.getByName('idx');
    expect(user!.age, 5);
  });

  test('multi-entry index query', () async {
    await isar.writeTxn(() async {
      await isar.users.putAll([
        User(name: 'a', age: 1, tags: ['red', 'blue']),
        User(name: 'b', age: 2, tags: ['green']),
      ]);
    });
    final red = await isar.users.filter().tagsElementEqualTo('red').findAll();
    expect(red.length, 1);
    expect(red.single.name, 'a');
  });

  test('aggregations', () async {
    await isar.writeTxn(() async {
      await isar.users.putAll([
        User(name: 'a', age: 10),
        User(name: 'b', age: 20),
        User(name: 'c', age: 30),
      ]);
    });
    expect(await isar.users.where().ageProperty().sum(), 60);
    expect(await isar.users.where().ageProperty().max(), 30);
    expect(await isar.users.where().ageProperty().min(), 10);
    expect(await isar.users.where().ageProperty().average(), 20);
  });

  test('watchers notify on change', () async {
    final events = <void>[];
    final sub = isar.users.watchLazy().listen(events.add);
    await isar.writeTxn(() => isar.users.put(User(name: 'a', age: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events.length, 1);
    await sub.cancel();
  });

  test('rollback on error', () async {
    await isar.writeTxn(() => isar.users.put(User(name: 'a', age: 1)));
    await expectLater(
      isar.writeTxn(() async {
        await isar.users.put(User(name: 'b', age: 2));
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(await isar.users.count(), 1);
  });

  test('json export / import', () async {
    await isar.writeTxn(() async {
      await isar.users.putAll([
        User(name: 'a', age: 10),
        User(name: 'b', age: 20),
      ]);
    });
    final json = await isar.users.where().exportJson();
    expect(json.length, 2);

    await isar.writeTxn(() => isar.users.clear());
    expect(await isar.users.count(), 0);

    await isar.writeTxn(() => isar.users.importJson(json));
    expect(await isar.users.count(), 2);
  });
}
