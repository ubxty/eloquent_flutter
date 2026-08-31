# Changelog

## 0.1.0 — 2026-08-31

Initial implementation.

- `Eloquent` facade with `init`, `db`, `transaction`, `raw`, `rawSelect`,
  `dispose`
- `Model<T, D>` base with `save`, `update`, `delete`, `refresh`
- `ModelQuery<T, D>` with `all`, `find`, `findOrFail`, `first`, `count`,
  `exists`, `watch`, `create`, `createMany`
- `QueryBuilder<T, D>` implementing `Selectable<T>` — chainable `where`
  (rich operator set), `orWhere`, `whereIn`, `whereNotIn`, `whereNull`,
  `whereNotNull`, `whereBetween`, `whereRaw`, `orderBy`, `orderByDesc`,
  `limit`, `offset`, `with_(...)`, `paginate(...)`
- Relationships: `HasMany`, `HasOne`, `BelongsTo`, `BelongsToMany` (with
  `attach` / `detach` / `sync`)
- Eager loading via `with_(...)` against the model's `$relations`
  registry
- Lifecycle observers (`ObserverSet`) with cancellation support
- Auto-timestamp mixin (`WithTimestamps`)
- `Paginator<T>` with `nextPage` / `previousPage`
- Exception hierarchy: `EloquentException`, `ColumnNotFoundException`,
  `TableNotFoundException`, `ModelNotFoundException`,
  `UnsupportedOperatorException`, `RelationNotFoundException`,
  `OperationCancelledException`, `InvalidArgumentException`
- Laravel-style `Schema` facade: `create`, `drop`, `dropUnlessExists`,
  `table` (alter), `hasTable`, `hasColumn`, `getColumns`, `dropAll`
- `Blueprint` DSL with column types (`id`, `string`, `text`, `integer`,
  `real`, `boolean`, `dateTime`, `blob`, `timestamps`), modifiers
  (`nullable_`, `unique_`, `primary_`, `default_`), constraints
  (`compositePrimary`, `foreign`, `index`, `unique`), and alter methods
  (`addColumn`, `dropColumn`, `renameColumn`, `dropIndex`)
- `Migrator` with `register`, `migrate`, `rollback`, `fresh`, backed by
  an `_migrations(name, batch)` ledger
