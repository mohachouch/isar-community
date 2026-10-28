// ignore_for_file: public_member_api_docs

import 'package:isar_community/isar.dart';

/// Sentinel used to represent a `null` number in the in-memory store.
///
/// This mirrors the encoding historically used by the Isar web backend so
/// that the generated `serialize`/`deserialize` code round-trips unchanged.
const double nullNumber = double.negativeInfinity;

/// Name of the implicit id property.
const String idName = '_id';

final DateTime _nullDate = DateTime.fromMillisecondsSinceEpoch(0);

/// A single serialized object. Property values are keyed by their offset.
typedef MemoryObject = Map<int, dynamic>;

/// [IsarReader] implementation reading values from an in-memory [MemoryObject].
class MemoryReader implements IsarReader {
  MemoryReader(this.object);

  final MemoryObject object;

  @override
  bool readBool(int offset) => object[offset] == 1;

  @override
  bool? readBoolOrNull(int offset) {
    final value = object[offset];
    return value == 0
        ? false
        : value == 1
            ? true
            : null;
  }

  @override
  int readByte(int offset) {
    final value = object[offset];
    return value is int ? value : 0;
  }

  @override
  int? readByteOrNull(int offset) {
    final value = object[offset];
    return value is int ? value : null;
  }

  @override
  int readInt(int offset) {
    final value = object[offset];
    return value is int ? value : _nullInt;
  }

  @override
  int? readIntOrNull(int offset) {
    final value = object[offset];
    return value is int && value != _nullInt ? value : null;
  }

  @override
  double readFloat(int offset) {
    final value = object[offset];
    return value is double ? value : nullNumber;
  }

  @override
  double? readFloatOrNull(int offset) {
    final value = object[offset];
    return value is double && !value.isNaN && value != nullNumber
        ? value
        : null;
  }

  @override
  int readLong(int offset) {
    final value = object[offset];
    return value is int ? value : _nullInt;
  }

  @override
  int? readLongOrNull(int offset) {
    final value = object[offset];
    return value is int && value != _nullInt ? value : null;
  }

  @override
  double readDouble(int offset) {
    final value = object[offset];
    return value is double ? value : nullNumber;
  }

  @override
  double? readDoubleOrNull(int offset) {
    final value = object[offset];
    return value is double && !value.isNaN && value != nullNumber
        ? value
        : null;
  }

  @override
  DateTime readDateTime(int offset) {
    final value = object[offset];
    return value is int && value != _nullInt
        ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal()
        : _nullDate;
  }

  @override
  DateTime? readDateTimeOrNull(int offset) {
    final value = object[offset];
    return value is int && value != _nullInt
        ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true).toLocal()
        : null;
  }

  @override
  String readString(int offset) {
    final value = object[offset];
    return value is String ? value : '';
  }

  @override
  String? readStringOrNull(int offset) {
    final value = object[offset];
    return value is String ? value : null;
  }

  @override
  T? readObjectOrNull<T>(
    int offset,
    Deserialize<T> deserialize,
    Map<Type, List<int>> allOffsets,
  ) {
    final value = object[offset];
    if (value is MemoryObject) {
      final reader = MemoryReader(value);
      return deserialize(0, reader, allOffsets[T]!, allOffsets);
    } else {
      return null;
    }
  }

  @override
  List<bool>? readBoolList(int offset) {
    final value = object[offset];
    return value is List ? value.map((e) => e == 1).toList() : null;
  }

  @override
  List<bool?>? readBoolOrNullList(int offset) {
    final value = object[offset];
    return value is List
        ? value
            .map(
              (e) => e == 0
                  ? false
                  : e == 1
                      ? true
                      : null,
            )
            .toList()
        : null;
  }

  @override
  List<int>? readByteList(int offset) {
    final value = object[offset];
    return value is List
        ? value.map((e) => e is int ? e : 0).toList()
        : null;
  }

  @override
  List<int>? readIntList(int offset) {
    final value = object[offset];
    return value is List
        ? value.map((e) => e is int ? e : _nullInt).toList()
        : null;
  }

  @override
  List<int?>? readIntOrNullList(int offset) {
    final value = object[offset];
    return value is List
        ? value.map((e) => e is int && e != _nullInt ? e : null).toList()
        : null;
  }

  @override
  List<double>? readFloatList(int offset) {
    final value = object[offset];
    return value is List
        ? value.map((e) => e is double ? e : nullNumber).toList()
        : null;
  }

  @override
  List<double?>? readFloatOrNullList(int offset) {
    final value = object[offset];
    return value is List
        ? value
            .map((e) => e is double && !e.isNaN && e != nullNumber ? e : null)
            .toList()
        : null;
  }

  @override
  List<int>? readLongList(int offset) {
    final value = object[offset];
    return value is List
        ? value.map((e) => e is int ? e : _nullInt).toList()
        : null;
  }

  @override
  List<int?>? readLongOrNullList(int offset) {
    final value = object[offset];
    return value is List
        ? value.map((e) => e is int && e != _nullInt ? e : null).toList()
        : null;
  }

  @override
  List<double>? readDoubleList(int offset) {
    final value = object[offset];
    return value is List
        ? value.map((e) => e is double ? e : nullNumber).toList()
        : null;
  }

  @override
  List<double?>? readDoubleOrNullList(int offset) {
    final value = object[offset];
    return value is List
        ? value
            .map((e) => e is double && !e.isNaN && e != nullNumber ? e : null)
            .toList()
        : null;
  }

  @override
  List<DateTime>? readDateTimeList(int offset) {
    final value = object[offset];
    return value is List
        ? value
            .map(
              (e) => e is int && e != _nullInt
                  ? DateTime.fromMillisecondsSinceEpoch(e, isUtc: true)
                      .toLocal()
                  : _nullDate,
            )
            .toList()
        : null;
  }

  @override
  List<DateTime?>? readDateTimeOrNullList(int offset) {
    final value = object[offset];
    return value is List
        ? value
            .map(
              (e) => e is int && e != _nullInt
                  ? DateTime.fromMillisecondsSinceEpoch(e, isUtc: true)
                      .toLocal()
                  : null,
            )
            .toList()
        : null;
  }

  @override
  List<String>? readStringList(int offset) {
    final value = object[offset];
    return value is List
        ? value.map((e) => e is String ? e : '').toList()
        : null;
  }

  @override
  List<String?>? readStringOrNullList(int offset) {
    final value = object[offset];
    return value is List
        ? value.map((e) => e is String ? e : null).toList()
        : null;
  }

  @override
  List<T>? readObjectList<T>(
    int offset,
    Deserialize<T> deserialize,
    Map<Type, List<int>> allOffsets,
    T defaultValue,
  ) {
    final value = object[offset];
    return value is List
        ? value.map((e) {
            if (e is MemoryObject) {
              final reader = MemoryReader(e);
              return deserialize(0, reader, allOffsets[T]!, allOffsets);
            } else {
              return defaultValue;
            }
          }).toList()
        : null;
  }

  @override
  List<T?>? readObjectOrNullList<T>(
    int offset,
    Deserialize<T> deserialize,
    Map<Type, List<int>> allOffsets,
  ) {
    final value = object[offset];
    return value is List
        ? value.map((e) {
            if (e is MemoryObject) {
              final reader = MemoryReader(e);
              return deserialize(0, reader, allOffsets[T]!, allOffsets);
            } else {
              return null;
            }
          }).toList()
        : null;
  }
}

/// Integer sentinel used to represent a `null` int/long/DateTime value.
const int _nullInt = -9223372036854775808;

/// Exposes the integer null sentinel to other library files.
const int memoryNullInt = _nullInt;
