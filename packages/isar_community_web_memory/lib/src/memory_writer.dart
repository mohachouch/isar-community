// ignore_for_file: public_member_api_docs

import 'package:isar_community/isar.dart';
import 'package:isar_community_web_memory/src/memory_reader.dart';

/// [IsarWriter] implementation writing values into an in-memory [MemoryObject].
class MemoryWriter implements IsarWriter {
  MemoryWriter(this.object);

  final MemoryObject object;

  @override
  void writeBool(int offset, bool? value) {
    object[offset] = value == null ? null : (value ? 1 : 0);
  }

  @override
  void writeByte(int offset, int value) {
    object[offset] = value;
  }

  @override
  void writeInt(int offset, int? value) {
    object[offset] = value ?? memoryNullInt;
  }

  @override
  void writeFloat(int offset, double? value) {
    object[offset] = value ?? nullNumber;
  }

  @override
  void writeLong(int offset, int? value) {
    object[offset] = value ?? memoryNullInt;
  }

  @override
  void writeDouble(int offset, double? value) {
    object[offset] = value ?? nullNumber;
  }

  @override
  void writeDateTime(int offset, DateTime? value) {
    object[offset] = value?.toUtc().millisecondsSinceEpoch ?? memoryNullInt;
  }

  @override
  void writeString(int offset, String? value) {
    object[offset] = value;
  }

  @override
  void writeObject<T>(
    int offset,
    Map<Type, List<int>> allOffsets,
    Serialize<T> serialize,
    T? value,
  ) {
    if (value != null) {
      final nested = <int, dynamic>{};
      final writer = MemoryWriter(nested);
      serialize(value, writer, allOffsets[T]!, allOffsets);
      object[offset] = nested;
    } else {
      object[offset] = null;
    }
  }

  @override
  void writeByteList(int offset, List<int>? values) {
    object[offset] = values?.toList();
  }

  @override
  void writeBoolList(int offset, List<bool?>? values) {
    object[offset] = values
        ?.map((e) => e == null ? null : (e ? 1 : 0))
        .toList();
  }

  @override
  void writeIntList(int offset, List<int?>? values) {
    object[offset] = values?.map((e) => e ?? memoryNullInt).toList();
  }

  @override
  void writeFloatList(int offset, List<double?>? values) {
    object[offset] = values?.map((e) => e ?? nullNumber).toList();
  }

  @override
  void writeLongList(int offset, List<int?>? values) {
    object[offset] = values?.map((e) => e ?? memoryNullInt).toList();
  }

  @override
  void writeDoubleList(int offset, List<double?>? values) {
    object[offset] = values?.map((e) => e ?? nullNumber).toList();
  }

  @override
  void writeDateTimeList(int offset, List<DateTime?>? values) {
    object[offset] = values
        ?.map((e) => e?.toUtc().millisecondsSinceEpoch ?? memoryNullInt)
        .toList();
  }

  @override
  void writeStringList(int offset, List<String?>? values) {
    object[offset] = values?.toList();
  }

  @override
  void writeObjectList<T>(
    int offset,
    Map<Type, List<int>> allOffsets,
    Serialize<T> serialize,
    List<T?>? values,
  ) {
    if (values != null) {
      object[offset] = values.map((e) {
        if (e != null) {
          final nested = <int, dynamic>{};
          final writer = MemoryWriter(nested);
          serialize(e, writer, allOffsets[T]!, allOffsets);
          return nested;
        }
        return null;
      }).toList();
    } else {
      object[offset] = null;
    }
  }
}
