## 3.4.1

- Initial release of `isar_community_web_memory`.
- Pure-Dart in-memory implementation of Isar (RAM only, non-persistent).
- Supports CRUD by id and by unique index, queries (where clauses, filters,
  sorting, distinct, offset/limit), aggregations, JSON import/export and
  watchers (collection, object and query watchers).
- Works on every platform (web, VM, Flutter) without IndexedDB or FFI.
