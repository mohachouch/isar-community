---
title: Limitations
---

# Limitations

As you know, Isar works on mobile devices and desktops running on the VM as well as Web. Both platforms are very different and have different limitations.

## VM Limitations

- Only the first 1024 bytes of a string can be used for a prefix where-clause
- Objects can only be 16MB in size

## Web Limitations

Because Isar Web relies on IndexedDB, there are more limitations, but they are barely noticeable while using Isar.

- Synchronous methods are unsupported
- Currently, `Isar.splitWords()` and `.matches()` filters are not yet implemented
- Schema changes are not as tightly checked as in the VM so be careful to comply with the rules
- All number types are stored as double (the only js number type) so `@Size32` has no effect
- Indexes are represented differently so hash indexes don't use less space (they still work the same)
- `col.delete()` and `col.deleteAll()` work correctly but the return value is not correct
- `col.clear()` do not reset the auto-increment value
- `NaN` is not supported as a value

## In-memory alternative for the Web

The default web backend relies on IndexedDB. If you only need **ephemeral,
non-persistent** storage for the lifetime of the page (for example in tests or
web prototypes), you can use the separate
[`isar_community_web_memory`](https://github.com/isar-community/isar-community/tree/main/packages/isar_community_web_memory)
package instead. It stores all collections in RAM, works without IndexedDB or
FFI, and supports synchronous methods. Open it explicitly with
`openIsarInMemory(schemas: [...])`. Note that it does not persist data and does
not support links.
