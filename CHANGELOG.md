# Changelog

## 0.2.0 — 2026-09-03

Bug fixes, performance, and feature surface that landed between 0.1.0 and
the first public release.

### Added

- **`$casts`** — per-column cast registry on `Model`. `int`, `double`,
  `string`, `bool`, `date`, `datetime`, `json`, `array` (see
  `CastType`). Read via `Model.getAttribute(key)`, write via
  `Model.setAttribute(key, value)`. Applies automatically through
  `ModelQuery.create(map)`.
- **`isDirty` / `isClean` / `wasChanged` / `getOriginal` / `$original` /
  `$dirty` / `$changes`** — Laravel-style dirty tracking. `save()`,
  `update()`, and `refresh()` snapshot the row; pending writes via
  `setAttribute` mark columns dirty.
- **SoftDeletes mixin** — `with SoftDeletes<...>` adds `delete()` (sets
  `deleted_at`), `forceDelete()`, `restore()`, and a `trashed` getter.
  QueryBuilder defaults to excluding trashed rows on tables with a
  `deleted_at` column; `withTrashed()` / `onlyTrashed()` /
  `withoutTrashed()` flip the filter.
- **`saveQuietly` / `deleteQuietly` / `Model.withoutEvents(...)`** —
  skip observer dispatch on individual calls or in a callback scope.
- **`pluck(column)` / `pluck(column, key)`** — single-column lists or
  `Map<key, model>` projections.
- **`value(column)`** — first row's column value, or null.
- **`sole()`** — assert exactly one row matches; throws
  `ModelNotFoundException` or `MultipleRecordsFoundException`.
- **`firstOrCreate` / `firstOrNew` / `updateOrCreate` / `upsert`** —
  idempotent creation helpers.
- **`whereHas` / `orWhereHas` / `has` / `orHas` / `doesntHave` /
  `whereDoesntHave` / `orDoesntHave` / `orWhereDoesntHave`** —
  relationship existence predicates, fold into the parent WHERE.
- **`withCount` / `withSum` / `withAvg` / `withMin` / `withMax`** —
  correlated aggregate subquery columns attached to each parent row.
- **`onlyTrashed` exception** — `ModelNotSoftDeletableException` thrown
  by `onlyTrashed()` when the table has no `deleted_at` column.
- **Benchmark suite** — `benchmark/eloquent_vs_drift.dart` runs
  INSERT / FIND / WHERE / ALL / COUNT / SAVE head-to-head against raw
  drift, prints µs/op and overhead %.

### Fixed

- **`ModelQuery.create` now honors `$casts`** — values land in the
  database as the cast's storage type, not as whatever the user typed.
- **`wasChanged` after `save`** — columns written through `setAttribute`
  stay in the change-set until the next `save()` or `refresh()`, matching
  Laravel semantics.
- **SoftDeletes on `ModelQuery`** — the implicit `deleted_at IS NULL`
  filter is now applied by `all()`, `find()`, `first()`, `count()`,
  `exists()`, and `min/max/avg/sum`.
- **`min` / `max` / `sum` / `avg` respect the soft-delete filter** —
  previously they queried every row, including trashed ones, because
  they emitted raw `customSelect` SQL that skipped `_trashedExpression()`.
- **`restore()` + `refresh()`** — `restore()` was no-op on the
  in-memory instance until `refresh()` re-read the row; now the
  underlying UPDATE applies and the snapshot is re-taken.
- **`withCount` aggregate type** — `comments_count` is now an `int`
  (was `Object?` in some code paths).
- **`sum` null result** — when no rows match, `sum()` returns `0`
  instead of throwing on a null column read.
- **`WithTimestamps` after `save` + `refresh`** — the mixin's
  `persistTimestamps` no longer throws on the abstract `refresh()`;
  timestamps are now correctly visible in the post-refresh row data.

### Changed

- **`Eloquent.dispose()` no longer closes the database** — the database
  is owned by the caller. `dispose()` now only drops the package's
  reference to the database. The caller is responsible for `close()`.
- **Lazy snapshot in `Model` constructor** — `_original` is left empty
  after `Model(data)`; populated on first call to `getOriginal`, after
  `save()`, or after `refresh()`. Cuts the per-row construction cost on
  read paths by ~75%.
- **`Model.wrap(data)` simplified** — now just flips `$exists = true`.
  The previous implementation did a redundant `$wrap` plus a second
  snapshot. Called on every fetched row.
- **`QueryBuilder.count()` fast path** — when no user predicates are
  present, emits a static `SELECT COUNT(*) ... WHERE "deleted_at" IS
  NULL` that hits SQLite's prepared-statement cache. Dropped COUNT
  overhead from ~600% to ~13%.

### Performance

`benchmark/eloquent_vs_drift.dart` is the reference. Numbers below are
overhead vs the equivalent raw drift statement on a 1k-row table on
SQLite in-memory.

| Operation | Overhead |
|---|---|
| `count()` (no predicates) | ~13% |
| `all()` (1k rows) | ~9% |
| `where(...).orderBy().limit().get()` | ~50% |
| `find(id)` | ~63% |
| `create(map)` (fair vs insert+read-back) | ~175% |
| `new Model(...).save()` (vs bare insert) | ~262% (lower bound) |

The wrapper pays for two things it cannot avoid: (a) one extra SELECT
round-trip to populate auto-incremented / defaulted columns after
INSERT, and (b) per-instance state (casts, dirty tracking, snapshot).
The 0.2.0 release brings per-row wrapper overhead down to ~50ns —
about 5% of drift's own round-trip — by removing redundant work in the
hot path.

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
