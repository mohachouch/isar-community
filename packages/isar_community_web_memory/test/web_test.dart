@TestOn('browser')
library web_test;

// ignore_for_file: invalid_use_of_protected_member

// A self-contained web (Chrome) test for the in-memory Isar backend.
//
// It uses a hand-written [CollectionSchema] with small, JavaScript-safe ids and
// the raw [IsarCollection]/buildQuery API, so it compiles with dart2js. The
// generated `*.g.dart` schemas cannot be compiled to JavaScript because Isar's
// code generator emits 64-bit (xxh3) ids that exceed the JS safe-integer range,
// which is an upstream limitation independent of this package.

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/isar_community_web_memory.dart';
import 'package:test/test.dart';

class User {
  User({this.id = Isar.autoIncrement, required this.name, required this.age});

  Id id;
  String name;
  int age;
}

// offsets are the identity mapping [0, 1] -> property ids.
void _serialize(
  User object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.name);
  writer.writeLong(offsets[1], object.age);
}

User _deserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  return User(
    id: id,
    name: reader.readString(offsets[0]),
    age: reader.readLong(offsets[1]),
  );
}

dynamic _deserializeProp(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return reader.readString(offset);
    case 1:
      return reader.readLong(offset);
    default:
      throw ArgumentError('Unknown property with id $propertyId');
  }
}

const _userSchema = CollectionSchema<User>(
  name: 'User',
  id: 1,
  properties: {
    'name': PropertySchema(id: 0, name: 'name', type: IsarType.string),
    'age': PropertySchema(id: 1, name: 'age', type: IsarType.long),
  },
  estimateSize: _estimateSize,
  serialize: _serialize,
  deserialize: _deserialize,
  deserializeProp: _deserializeProp,
  idName: 'id',
  indexes: {
    'name': IndexSchema(
      id: 2,
      name: 'name',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: 'name',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _getId,
  getLinks: _getLinks,
  attach: _attach,
  version: Isar.version,
);

int _estimateSize(
  User object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) =>
    object.name.length * 3 + 8;

Id _getId(User object) => object.id;

List<IsarLinkBase<dynamic>> _getLinks(User object) => [];

void _attach(IsarCollection<User> col, Id id, User object) {
  object.id = id;
}

extension on Isar {
  IsarCollection<User> get users => this.collection<User>();
}

void main() {
  late Isar isar;

  setUp(() {
    isar = openIsarInMemorySync(
      schemas: [_userSchema],
      name: 'web_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    await isar.close();
  });

  test('put and get by id (sync, runs on Chrome)', () {
    final id = isar.writeTxnSync(() => isar.users.putSync(User(name: 'a', age: 1)));
    expect(id, 1);
    final user = isar.users.getSync(id);
    expect(user!.name, 'a');
    expect(user.age, 1);
  });

  test('requires write transaction', () {
    expect(
      () => isar.users.putSync(User(name: 'x', age: 1)),
      throwsA(isA<IsarError>()),
    );
  });

  test('filter + sort + limit via buildQuery', () {
    isar.writeTxnSync(() {
      isar.users.putAllSync([
        User(name: 'a', age: 10),
        User(name: 'b', age: 20),
        User(name: 'c', age: 30),
        User(name: 'd', age: 40),
      ]);
    });

    final query = isar.users.buildQuery<User>(
      filter: const FilterCondition.greaterThan(property: 'age', value: 10),
      sortBy: const [SortProperty(property: 'age', sort: Sort.desc)],
      offset: 1,
      limit: 2,
    );
    expect(query.findAllSync().map((e) => e.age), [30, 20]);
  });

  test('unique replace index + getByIndex', () {
    isar.writeTxnSync(() => isar.users.putSync(User(name: 'dup', age: 1)));
    isar.writeTxnSync(() => isar.users.putSync(User(name: 'dup', age: 2)));
    expect(isar.users.countSync(), 1);

    final byIndex = isar.users.getAllByIndexSync('name', [
      ['dup'],
    ]);
    expect(byIndex.single!.age, 2);
  });

  test('aggregation (sum) via property query', () {
    isar.writeTxnSync(() {
      isar.users.putAllSync([
        User(name: 'a', age: 10),
        User(name: 'b', age: 20),
        User(name: 'c', age: 30),
      ]);
    });
    final sum = isar.users
        .buildQuery<int>(property: 'age')
        .aggregateSync<int>(AggregationOp.sum);
    expect(sum, 60);
  });

  test('watchers notify on change', () async {
    final events = <void>[];
    final sub = isar.users.watchLazy().listen(events.add);
    isar.writeTxnSync(() => isar.users.putSync(User(name: 'a', age: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events.length, 1);
    await sub.cancel();
  });

  test('rollback on error', () {
    isar.writeTxnSync(() => isar.users.putSync(User(name: 'a', age: 1)));
    expect(
      () => isar.writeTxnSync(() {
        isar.users.putSync(User(name: 'b', age: 2));
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(isar.users.countSync(), 1);
  });
}
