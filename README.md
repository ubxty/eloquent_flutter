# eloquent_flutter

> **Laravel Eloquent-style ORM for Flutter and Dart, built on top of Drift.**
> Chainable queries, casts, soft deletes, dirty tracking, relationships,
> eager loading, and a Laravel-style schema / migrator — without giving
> up Drift's reactive streams or typesafe codegen.

[![pub package](https://img.shields.io/pub/v/eloquent_flutter.svg)](https://pub.dev/packages/eloquent_flutter)
[![Dart ≥ 3.4](https://img.shields.io/badge/Dart-%3E%3D3.4-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
[![Flutter ≥ 3.10](https://img.shields.io/badge/Flutter-%3E%3D3.10-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Drift ≥ 2.18](https://img.shields.io/badge/Drift-%3E%3D2.18-0095D5)](https://drift.simonbinder.eu/)
[![License MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/ubxty/eloquent_flutter.svg)](https://github.com/ubxty/eloquent_flutter/stargazers)

---

## Why eloquent_flutter?

[Drift](https://drift.simonbinder.eu/) is one of the most capable SQLite
ORMs in the Dart ecosystem, but its day-to-day API is verbose:

```dart
final users = await (db.select(db.users)
      ..where((u) => u.active.equals(true) & u.age.isBiggerThanValue(18))
      ..orderBy([(u) => OrderingTerm(expression: u.name)]))
    .get();
```

Eloquent-style code is shorter, more discoverable, and reads like the
SQL it generates:

```dart
final users = await User.where('active', true).where('age', '>', 18).orderBy('name').get();
```

`eloquent_flutter` is a **thin wrapper on top of Drift** — not a
replacement. You keep your existing `@DriftDatabase` and the
generated row classes. The package adds chainable queries, casts,
soft deletes, dirty tracking, relationships, eager loading, observers,
pagination, auto-timestamps, and a Laravel-style `Schema` / `Migrator`
for declarative DDL.

---

## Table of contents

1. [Features](#features)
2. [Performance](#performance)
3. [Install](#install)
4. [Quick start](#quick-start)
5. [Usage guide](#usage-guide)
   - [Database setup](#database-setup)
   - [The registry pattern](#the-registry-pattern)
   - [Defining a model](#defining-a-model)
   - [Creating records](#creating-records)
   - [Reading records](#reading-records)
   - [Updating and deleting](#updating-and-deleting)
   - [Chainable queries](#chainable-queries)
   - [Operators](#operators)
   - [Aggregates](#aggregates)
   - [Casts](#casts)
   - [Soft deletes](#soft-deletes)
   - [Dirty tracking](#dirty-tracking)
   - [Reactive streams](#reactive-streams)
   - [Pagination](#pagination)
   - [Transactions](#transactions)
   - [Raw SQL](#raw-sql)
   - [Relationships](#relationships)
   - [Eager loading](#eager-loading)
   - [Lifecycle observers](#lifecycle-observers)
   - [Auto timestamps](#auto-timestamps)
   - [Schema: declaring tables](#schema-declaring-tables)
   - [Migrations: evolving the schema](#migrations-evolving-the-schema)
6. [API reference](#api-reference)
7. [Limitations](#limitations)
8. [Roadmap](#roadmap)
9. [Contributing](#contributing)
10. [Maintainer](#maintainer)
11. [License](#license)

---

## Features

- **Chainable `QueryBuilder<T, D>`** that also implements Drift's
  `Selectable<T>` — `.get()`, `.watch()`, `.getSingleOrNull()` work
  for free.
- **Forwarding statics** — `User.all()`, `User.find(id)`,
  `User.create(map)`, `User.where(...)`.
- **Rich operator set** — `=`, `!=`, `<`, `<=`, `>`, `>=`, `LIKE`,
  `NOT LIKE`, `IN`, `NOT IN`, `IS NULL`, `IS NOT NULL`, `BETWEEN`.
- **Aggregates** — `count` / `min` / `max` / `avg` / `sum` on
  `QueryBuilder`, plus `withCount` / `withSum` / `withAvg` /
  `withMin` / `withMax` for correlated subquery columns.
- **Casts** — per-column `$casts` registry with `int`, `double`,
  `string`, `bool`, `date`, `datetime`, `json`, `array`. Read via
  `getAttribute`, write via `setAttribute`; applied automatically on
  `ModelQuery.create(map)`.
- **Soft deletes** — opt-in `with SoftDeletes<...>` mixin. Tables
  with a `deleted_at` column auto-exclude trashed rows. Override with
  `withTrashed()` / `onlyTrashed()`.
- **Dirty tracking** — `isDirty`, `isClean`, `wasChanged`,
  `getOriginal`, `$original`, `$dirty`, `$changes`. Snapshot taken
  on `save()`, `update()`, `refresh()`.
- **Reactive streams** — `watch()`, `watchSingle()`, `watchSingleOrNull()`
  re-emit on any write to the underlying table.
- **Transactions** — `Eloquent.transaction(() async { ... })`. Nested
  calls reuse the outer transaction.
- **Raw SQL escape hatch** — `Eloquent.raw(sql, [vars])`,
  `Eloquent.rawSelect(sql, [vars])`. Always use `?` placeholders.
- **Relationships** — `HasMany`, `HasOne`, `BelongsTo`, `BelongsToMany`
  with `attach` / `detach` / `sync`.
- **Eager loading** — `User.query().with_(['posts', 'profile']).get()`
  batches related fetches into one query per relation.
- **Lifecycle observers** — `creating` / `created` / `updating` /
  `updated` / `deleting` / `deleted`. Cancelable by returning `false`
  on the `*ing` hook. `saveQuietly` / `deleteQuietly` /
  `Model.withoutEvents(...)` skip dispatch.
- **Pagination** — `Paginator<T>` with `data`, `currentPage`,
  `lastPage`, `total`, `hasMore`, `nextPage()`, `previousPage()`.
- **Auto timestamps** — opt-in `WithTimestamps` mixin.
- **Schema + Migrations** — Laravel-style `Schema.create()` /
  `Schema.table()` with a Blueprint DSL, plus a `Migrator` that tracks
  applied migrations in an `_migrations` ledger and supports
  `up()` / `down()` rollbacks.

---

## Performance

`benchmark/eloquent_vs_drift.dart` is the reference. It runs INSERT /
FIND / WHERE / ALL / COUNT / SAVE head-to-head against raw drift on a
1k-row SQLite-in-memory table. The wrapper pays for two things it
cannot avoid: one extra SELECT round-trip to populate
auto-incremented / defaulted columns after INSERT, and per-instance
state (casts, dirty tracking, snapshot). Per-row construction cost is
~50ns — about 5% of drift's own round-trip.

| Operation | Overhead vs raw drift |
|---|---|
| `count()` (no predicates) | ~13% |
| `all()` (1k rows) | ~9% |
| `where(...).orderBy().limit().get()` | ~50% |
| `find(id)` | ~63% |
| `create(map)` (vs insert+read-back) | ~175% |
| `new Model(...).save()` (vs bare insert) | ~262% (lower bound) |

Run it with:

```bash
dart run benchmark/eloquent_vs_drift.dart
```

---

## Install

```yaml
dependencies:
  drift: ^2.18.0
  eloquent_flutter: ^0.1.0
```

Or for the latest unreleased:

```yaml
dependencies:
  eloquent_flutter:
    git: https://github.com/ubxty/eloquent_flutter.git
```

Then `dart pub get`. The example app uses Drift's
`NativeDatabase.memory()`; for production, point `AppDatabase` at
`NativeDatabase(file)` (or `flutter` for cross-platform).

---

## Quick start

```dart
// 1. Open Drift, register with Eloquent
final db = AppDatabase(NativeDatabase.memory());
Eloquent.init(db);
AppRegistry.init(db);

// 2. Apply pending migrations
await migrate();

// 3. Use models like Laravel
final alice = await User.create({
  'email': 'alice@example.com',
  'name':  'Alice',
});
final active = await User.where('active', true).orderBy('name').get();
final page   = await User.where('active', true).paginate(page: 1, perPage: 20);
final posts  = await alice.posts().get();
```

The full example in [`example/`](example/) runs through every feature.
Clone, `dart pub get`, `dart run build_runner build`,
`dart run example/lib/main.dart`.

---

## Usage guide

### Database setup

Declare your Drift tables as you normally would:

```dart
// lib/database.dart
import 'package:drift/drift.dart';

part 'database.g.dart';

@DataClassName('UserRow')
class Users extends Table {
  IntColumn      get id        => integer().autoIncrement()();
  TextColumn     get email     => text().unique()();
  TextColumn     get name      => text()();
  BoolColumn     get active    => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

@DriftDatabase(tables: [Users, Posts, Profiles, Roles, RoleUsers])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  // Schema is owned by eloquent's `Migrator`, not by Drift's
  // MigrationStrategy. Keep the strategy as a no-op so the two don't
  // fight each other.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {},
        onUpgrade: (m, from, to) async {},
      );
}
```

Run `dart run build_runner build` to generate `database.g.dart`.

The Drift schema here exists **only** for type-safe row access
(`UserRow`, `PostRow`, etc.) and codegen-driven `Selectable` plumbing.
The actual DDL is written by your migrations (see
[Schema: declaring tables](#schema-declaring-tables)).

### The registry pattern

Drift exposes each table as an instance getter on the database
(`db.users`, `db.posts`, …). Models need a static handle to their
table — the simplest pattern is a singleton registry:

```dart
// lib/registry.dart
import 'package:drift/drift.dart';
import 'database.dart';

class AppRegistry {
  AppRegistry._();

  static AppDatabase? _db;

  static void init(AppDatabase db) => _db = db;

  static TableInfo<Users,    UserRow>    get users    => _instance.users;
  static TableInfo<Posts,    PostRow>    get posts    => _instance.posts;
  static TableInfo<Profiles, ProfileRow> get profiles => _instance.profiles;
  static TableInfo<Roles,    RoleRow>    get roles    => _instance.roles;

  static AppDatabase get _instance =>
      _db ?? (throw StateError('AppRegistry.init(db) must be called first.'));
}
```

Call `AppRegistry.init(db)` immediately after `Eloquent.init(db)`.
Anywhere in the app you can read `AppRegistry.users`.

> **Why a registry?** Drift's `TableInfo<T, D>` is parameterized over
> the row type. The wrapper needs the same instance everywhere a
> `User` is constructed; a static accessor avoids threading the
> database through every callsite.

### Defining a model

```dart
// lib/models/user.dart
import 'package:drift/drift.dart' show TableInfo;
import 'package:eloquent_flutter/eloquent_flutter.dart';

import '../database.dart';
import '../registry.dart';
import 'post.dart';
import 'profile.dart';
import 'role.dart';

class User extends Model<User, UserRow>
    with SoftDeletes<User, UserRow>, WithTimestamps {
  User(super.data);

  @override
  TableInfo<Users, UserRow> get $table => AppRegistry.users;

  @override
  User $wrap(UserRow data) => User(data);

  @override
  Map<String, dynamic> toMap() => {
        'id':         $data.id,
        'email':      $data.email,
        'name':       $data.name,
        'active':     $data.active,
        'created_at': $data.createdAt,
        'updated_at': $data.updatedAt,
      };

  // Per-column cast registry. Values round-trip through these on
  // getAttribute / setAttribute and on ModelQuery.create(map).
  @override
  Map<String, String> get $casts => const {
        'created_at': 'datetime',
        'updated_at': 'datetime',
        'deleted_at': 'datetime',
      };

  // Relationships.
  HasMany<Post, PostRow> posts() => HasMany<Post, PostRow>(
        local: this,
        relatedTable: AppRegistry.posts,
        foreignKey: 'user_id',
        creator: Post.new,
      );

  HasOne<Profile, ProfileRow> profile() => HasOne<Profile, ProfileRow>(
        local: this,
        relatedTable: AppRegistry.profiles,
        foreignKey: 'user_id',
        creator: Profile.new,
      );

  BelongsToMany<Role, RoleRow> roles() => BelongsToMany<Role, RoleRow>(
        local: this,
        relatedTable: AppRegistry.roles,
        creator: Role.new,
        pivotTable: 'role_users',
        foreignPivotKey: 'user_id',
        relatedPivotKey: 'role_id',
      );

  // Eager-loading registry.
  @override
  Map<String, Relationship<dynamic>> get $relations => {
        'posts':   posts(),
        'profile': profile(),
        'roles':   roles(),
      };

  // Lifecycle hooks.
  @override
  ObserverSet get $observers => ObserverSet(
        creating: (u) => (u.toMap()['email'] as String).contains('@'),
        created:  (u) => print('User created: id=${u.toMap()["id"]}'),
      );

  // Forwarding statics — copy/paste per model.
  static final _q = ModelQuery<User, UserRow>(
    table: AppRegistry.users,
    creator: User.new,
    primaryKey: 'id',
  );

  static Future<List<User>> all() => _q.all();
  static Future<User?> find(Object id) => _q.find(id);
  static Future<User> findOrFail(Object id) => _q.findOrFail(id);
  static Future<User?> first({String? orderBy}) => _q.first(orderBy: orderBy);
  static Future<int> count() => _q.count();
  static Future<bool> exists() => _q.exists();
  static Stream<List<User>> watch() => _q.watch();
  static Future<User> create(Map<String, dynamic> v) => _q.create(v);
  static QueryBuilder<User, UserRow> where(
          String c, [Object? v, String op = '=']) =>
      _q.where(c, v, op);
  static QueryBuilder<User, UserRow> query() => _q.query();
}
```

`Model<T, D>` takes two type parameters: `T` is the model class
itself (used for covariant returns) and `D` is the Drift-generated
row class. `$table`, `$wrap`, and `toMap()` are abstract — every
model must implement them.

### Creating records

```dart
final user = await User.create({
  'email': 'alice@example.com',
  'name':  'Alice',
});
```

`create()` inserts the row and fires the `created` observer. To
cancel before insert, build the instance yourself and use `save()`:

```dart
final u = User(UserRow(email: 'a@b', name: 'A', active: true, /* … */));
try {
  await u.save();      // fires `creating`, then INSERT, then `created`
} on OperationCancelledException {
  // `creating` returned false
}
```

`save()` upserts: if the row has no primary key yet it inserts,
otherwise it updates. `refresh()` re-reads the row from the database.

### Reading records

```dart
final all          = await User.all();
final one          = await User.find(1);
final required     = await User.findOrFail(1);     // throws ModelNotFoundException
final firstActive  = await User.where('active', true).first();
final count        = await User.count();
final hasAny       = await User.exists();
```

### Updating and deleting

```dart
// Instance methods — fire `updating` / `updated`, `deleting` / `deleted`
await user.update({'name': 'New name'});
await user.delete();
await user.refresh();

// Mass operations on a query
final affected = await User.where('active', false).update({'active': true});
final deleted  = await User.where('id', [1, 2, 3], 'in').delete();
```

For silent operations (no observer dispatch), use `saveQuietly`,
`deleteQuietly`, or wrap a batch in `Model.withoutEvents(...)`:

```dart
await user.saveQuietly();
await Model.withoutEvents(() async {
  for (final row in seedRows) await User.create(row);
});
```

### Chainable queries

```dart
final adults = await User
    .where('active', true)
    .where('age', '>', 18)
    .whereNotNull('verified_at')
    .orderByDesc('created_at')
    .limit(20)
    .offset(40)
    .get();
```

Available chainable methods on `QueryBuilder<T, D>`:

| Method | Description |
|---|---|
| `where(c, [v, op])` | Add a predicate. `op` defaults to `=`. |
| `orWhere(c, [v, op])` | OR-join with the previous predicate. |
| `whereIn(c, list)` / `whereNotIn(c, list)` | `IN` / `NOT IN`. |
| `whereNull(c)` / `whereNotNull(c)` | NULL checks. |
| `whereBetween(c, a, b)` | Inclusive `BETWEEN`. |
| `whereRaw(expr)` | Drop down to a Drift `Expression<bool>`. |
| `orderBy(c, {descending})` / `orderByDesc(c)` | Sort. |
| `limit(n)` / `offset(k)` | Pagination slicing. |
| `with_(name)` / `with_([names])` | Eager-load named relations. |
| `withCount(name)` / `withSum(name, col)` / `withAvg(name, col)` / `withMin(name, col)` / `withMax(name, col)` | Correlated aggregate subquery columns. |
| `has(name, [op, n])` / `whereHas(name, [cb])` / `doesntHave(name)` / `whereDoesntHave(name, [cb])` (and `orHas` / `orWhereHas` / `orDoesntHave` / `orWhereDoesntHave`) | Relationship existence predicates. |
| `withTrashed()` / `onlyTrashed()` / `withoutTrashed()` | Soft-delete filter overrides. |
| `first()` | First row, or null. |
| `count()` / `exists()` | Aggregates. |
| `min(c)` / `max(c)` / `avg(c)` / `sum(c)` | Column aggregates. |
| `pluck(c)` / `pluck(c, key)` | Single-column list or keyed map. |
| `value(c)` | First row's column value, or null. |
| `sole()` | Assert exactly one row matches. |
| `update(map)` | Mass update matching rows. |
| `delete()` | Mass delete matching rows. |
| `paginate({page, perPage})` | Returns a `Paginator<T>`. |

`QueryBuilder<T, D>` implements `Selectable<T>`, so all of Drift's
terminal methods work too: `.get()`, `.watch()`, `.getSingleOrNull()`,
`.watchSingleOrNull()`, plus `map` / `asyncMap` for custom
transformations.

### Operators

The string-based `where()` accepts the full Eloquent operator set:

```
=, ==, !=, <>, >, >=, <, <=,
like, not like,
in, not in,
is null, is not null,
between
```

`IS NULL` and `IS NOT NULL` ignore the value argument:

```dart
User.where('verified_at', null, 'is null');     // verified_at IS NULL
User.where('verified_at', null, 'is not null'); // verified_at IS NOT NULL
```

For type-mismatched operators the package throws
`InvalidArgumentException` (e.g. `LIKE` on an integer column, `>` on
a boolean column). For anything beyond the operator string set, drop
to `whereRaw` with a typed Drift expression:

```dart
import 'package:drift/drift.dart' show OrderingTerm;

User.query().whereRaw((u) => u.email.like('%@example.com')).get();
```

### Aggregates

`count`, `exists`, `min`, `max`, `avg`, `sum` all honor the
soft-delete filter on tables that have a `deleted_at` column. Use
`withTrashed()` / `onlyTrashed()` to flip it.

```dart
final total  = await User.count();
final oldest = await User.max('age');
final avgAge = await User.avg('age');
final hasAny = await User.exists();
final admins = await User.where('role', 'admin').count();
```

Attach a correlated count to each parent row:

```dart
final users = await User.query().withCount('posts').get();
for (final u in users) {
  print('${u.toMap()["name"]}: ${u.getLoaded("posts_count")} posts');
}
```

### Casts

Declare a per-column cast registry on the model:

```dart
@override
Map<String, String> get $casts => {
  'age':        'int',
  'is_admin':   'bool',
  'meta':       'json',
  'birthday':   'date',
  'created_at': 'datetime',
};
```

Supported types (`CastType`):

| Constant | Cast type | Reads | Writes |
|---|---|---|---|
| `CastType.integer` | `int` | `int` from `int` / `String` / `bool` / `double` | parses the user value to `int` |
| `CastType.double_` | `double` | `double` from `double` / `int` / `String` | parses to `double` |
| `CastType.string` | `String` | `String` via `toString()` | unchanged |
| `CastType.boolean` | `bool` | `bool` from `bool` / `int` / `String` | normalized to `bool` |
| `CastType.date` | `DateTime` | date-only `DateTime` (midnight) | date-only `DateTime` |
| `CastType.dateTime` | `DateTime` | `DateTime` from `DateTime` / `String` / epoch seconds | `DateTime` |
| `CastType.json` | `Map<String, dynamic>` | JSON object via `jsonDecode` | JSON string via `jsonEncode` |
| `CastType.array` | `List<dynamic>` | JSON array via `jsonDecode` | JSON string via `jsonEncode` |

Read with `getAttribute(key)`, write with `setAttribute(key, value)`:

```dart
final age = user.getAttribute('age') as int;       // cast on read
user.setAttribute('meta', {'theme': 'dark'});      // encoded to JSON
await user.save();                                  // lands as a JSON string
```

`ModelQuery.create(map)` applies the casts before insert, so the
value in the database is always the cast's storage type, not
whatever the user typed.

### Soft deletes

Add the `SoftDeletes` mixin to a model whose table has a nullable
`deleted_at` column. By default, every read on the table excludes
trashed rows:

```dart
class User extends Model<User, UserRow> with SoftDeletes<User, UserRow> {
  // ...
}

await user.delete();            // sets deleted_at = now()
await user.refresh();
print(user.trashed);            // true

await user.restore();           // clears deleted_at

await User.all();               // live rows only
await User.withTrashed().get(); // live + trashed
await User.onlyTrashed().get(); // trashed only
```

`delete()` is reversible (`restore()` clears the column). To remove
the row permanently, use `forceDelete()`. The `min` / `max` / `avg` /
`sum` / `count` aggregates also respect the filter.

### Dirty tracking

Every `Model` tracks dirty columns after writes through
`setAttribute` or `update({...})`. The snapshot is taken by
`save()`, `update()`, and `refresh()`.

```dart
final u = await User.find(1);
u.setAttribute('name', 'New name');
u.isDirty();             // true
u.isDirty('name');       // true
u.isClean('email');      // true (no pending write)

await u.save();
u.isDirty();             // false (snapshot taken)
u.wasChanged();          // true (writes happened during this lifecycle)
u.wasChanged('name');    // true
await u.refresh();
u.wasChanged();          // false (next snapshot)
u.$original;             // { ... row at last snapshot ... }
u.getOriginal('name');   // 'New name' (the value at snapshot)
```

`setAttribute` writes go through the inverse of any registered cast,
so a `'42'` typed as `'int'` becomes `42` in `$pending` and in the
column on `save()`.

### Reactive streams

`watch()` re-emits whenever the table is written to. This pairs
with `StreamBuilder` in Flutter:

```dart
final users$ = User.watch();   // Stream<List<User>>
final one$  = User.where('id', 1).watchSingleOrNull();

StreamBuilder<List<User>>(
  stream: users$,
  builder: (ctx, snap) => ListView(children: /* snap.data!.map(...) */),
);
```

Streams are powered by Drift's reactive query engine, so any write
that touches the underlying table — including raw SQL via
`customInsert`, `customUpdate`, `customWriteReturning` — triggers a
re-emission.

### Pagination

```dart
final page = await User
    .where('active', true)
    .paginate(page: 2, perPage: 20);

page.data;          // List<User> on this page
page.currentPage;   // 2
page.lastPage;      // 5
page.total;         // 100
page.perPage;       // 20
page.hasMore;       // true
page.hasPrevious;   // true

final next = await page.nextPage();
final prev = await page.previousPage();
```

### Transactions

```dart
await Eloquent.transaction(() async {
  final u = await User.create({'email': 'x@y', 'name': 'x'});
  await Post.create({'user_id': u.toMap()['id'], 'title': 'first'});
  if (bad) throw StateError('rolled back');   // everything unwinds
});
```

Nested `transaction` calls reuse the outer transaction in Drift, so
this composes naturally.

### Raw SQL

When you need to escape the wrapper:

```dart
// DML / DDL — returns nothing
await Eloquent.raw(
  'UPDATE users SET active = ? WHERE last_login < ?',
  [false, DateTime.now().subtract(Duration(days: 90))],
);

// Ad-hoc SELECT
final rows = await Eloquent.rawSelect(
  'SELECT email, COUNT(*) AS n FROM users GROUP BY email HAVING n > 1',
);
// rows: List<Map<String, Object?>>
```

For reactive SELECTs, use Drift's native `customSelect` directly:

```dart
final stream = Eloquent.db
    .customSelect('SELECT * FROM users', readsFrom: {Eloquent.db.users})
    .watch();
```

> **Always bind user input.** Use `?` placeholders and the
> `variables` parameter — never interpolate values into the SQL
> string. `Eloquent.rawSelect` accepts `Object?` so `null` binds
> as SQL `NULL`.

### Relationships

Declare relationships on the model as instance methods:

```dart
class User extends Model<User, UserRow> {
  HasMany<Post, PostRow> posts() => HasMany<Post, PostRow>(
    local: this, relatedTable: AppRegistry.posts,
    foreignKey: 'user_id', creator: Post.new,
  );

  HasOne<Profile, ProfileRow> profile() => HasOne<Profile, ProfileRow>(
    local: this, relatedTable: AppRegistry.profiles,
    foreignKey: 'user_id', creator: Profile.new,
  );
}

class Post extends Model<Post, PostRow> {
  BelongsTo<User, UserRow> user() => BelongsTo<User, UserRow>(
    local: this, relatedTable: AppRegistry.users,
    foreignKey: 'user_id', creator: User.new,
  );
}
```

Then call them like Laravel:

```dart
final posts    = await alice.posts().get();
final profile  = await alice.profile().get();
final owner    = await firstPost.user().get();
final liveUser = firstPost.user().watch();          // Stream<User?>
```

`HasMany` and `HasOne` also expose `create(map)` / `createOrFail(map)`
that auto-fill the foreign key from the parent:

```dart
final p = await alice.posts().create({'title': 'new', 'body': '...'});
// p.user_id == alice.toMap()['id']
```

`BelongsToMany` adds pivot-table ergonomics:

```dart
await alice.roles().attach(adminId);
await alice.roles().detach(editorId);
await alice.roles().sync([adminId]);           // full replace
final roles = await alice.roles().get();
```

### Eager loading

Eager loading batches the related fetches into one query per
relation, so `User.query().with_(['posts', 'profile']).get()` runs
three queries instead of `1 + N`.

```dart
final users = await User.query().with_(['posts', 'profile']).get();

for (final u in users) {
  print(u.toMap()['name']);
  if (u.isLoaded('posts')) {
    for (final p in u.getLoaded<List<Post>>('posts')) print('  - ${p.toMap()['title']}');
  }
  if (u.isLoaded('profile')) {
    print('  bio: ${u.getLoaded<Profile>('profile').toMap()['bio']}');
  }
}
```

The string keys must match `$relations` on the model. An unknown key
throws `RelationNotFoundException` listing the available relations.

### Lifecycle observers

Two styles, both supported, with the registry form taking precedence
if both are declared:

```dart
// Laravel-style statics
class User extends Model<User, UserRow> {
  static bool creating() => true;            // return false to cancel
  static void created()  { print('saved'); }
  // also: updating/updated, deleting/deleted
}

// Registry (Dart-idiomatic, has access to the model instance)
class User extends Model<User, UserRow> {
  @override
  ObserverSet get $observers => ObserverSet(
    creating: (u) => (u.toMap()['email'] as String).contains('@'),
    created:  (u) => print('saved ${u.toMap()["id"]}'),
    updated:  (u) => print('updated ${u.toMap()["id"]}'),
  );
}
```

Hooks fire in this order on instance `save()` / `update()` /
`delete()`:

```
creating → INSERT → created
updating → UPDATE → updated
deleting → DELETE → deleted
```

`ModelQuery.create()` bypasses the cancel path (`creating`) because
it inserts via Drift directly, then fires `created` post-insert. If
you need cancellation, use `Model.save()` from an instance.

Returning `false` from `creating` / `updating` / `deleting` aborts
the operation and throws `OperationCancelledException`.

### Auto timestamps

```dart
class User extends Model<User, UserRow> with WithTimestamps { … }
```

The mixin:

- Sets `created_at = DateTime.now()` on the first `save()` (if null).
- Bumps `updated_at = DateTime.now()` on every `save()` and `update()`.

It detects column presence at runtime — if the table is missing
`created_at` / `updated_at`, the mixin no-ops silently.

### Schema: declaring tables

The `Schema` facade emits SQL via a Blueprint DSL. SQLite storage
types are inferred from the column helpers; modifiers are chainable.

```dart
await Schema.create('users', (t) {
  t.id();
  t.string('email').unique_();
  t.string('name');
  t.boolean('active').default_(true);
  t.dateTime('deleted_at').nullable_();
  t.timestamps();
});

await Schema.create('posts', (t) {
  t.id();
  t.integer('user_id');
  t.string('title');
  t.text('body').default_('');
  t.foreign('user_id', references: 'users.id', onDelete: 'CASCADE');
});
```

Column helpers:

| Helper | Storage | Notes |
|---|---|---|
| `t.id()` | `INTEGER PRIMARY KEY AUTOINCREMENT` | Conventional PK. |
| `t.string(name)` | `TEXT` | Short strings, enums. |
| `t.text(name)` | `TEXT` | Long-form text. |
| `t.integer(name)` | `INTEGER` | |
| `t.real(name)` | `REAL` | Double-precision float. |
| `t.boolean(name)` | `INTEGER` | 0/1 (SQLite has no native BOOL). |
| `t.dateTime(name)` | `TEXT` | ISO-8601. |
| `t.blob(name)` | `BLOB` | |
| `t.timestamps()` | nullable `created_at` + `updated_at` | Filled by `WithTimestamps`. |

Modifiers (chainable, mutate the column in place):

```dart
t.string('email').unique_();
t.string('nickname').nullable_();
t.string('slug').default_('untitled');
t.boolean('verified').default_(false);
```

Constraints:

```dart
t.compositePrimary(['user_id', 'role_id']);          // for pivot tables
t.foreign('user_id', references: 'users.id', onDelete: 'CASCADE');
t.index(['user_id', 'created_at']);
t.unique(['user_id', 'slug']);
```

`foreign()` accepts either Laravel-style `'users.id'` or SQLite-style
`'users(id)'`; both are normalized to `users(id)` in the rendered SQL.

Inspect the database:

```dart
if (await Schema.hasTable('users')) { … }
final cols     = await Schema.getColumns('users');    // ['id', 'email', ...]
final hasEmail = await Schema.hasColumn('users', 'email');
```

Drop / wipe:

```dart
await Schema.drop('posts');                            // DROP TABLE IF EXISTS
await Schema.dropUnlessExists('posts');                // bare DROP TABLE
await Schema.dropAll();                                // every non-sqlite_* table
```

### Migrations: evolving the schema

Each migration is a class with `up()` and `down()`. Register with a
`Migrator`, then call `migrate()` at boot:

```dart
class AddUserPhone extends Migration {
  const AddUserPhone();

  @override
  Future<void> up() async {
    await Schema.table('users', (t) {
      t.addColumn('string', 'phone').default_('');
    });
  }

  @override
  Future<void> down() async {
    await Schema.table('users', (t) {
      t.dropColumn('phone');
    });
  }
}

List<Migration> allMigrations() => const <Migration>[
  CreateUsers(),
  AddUserPhone(),
];

Future<void> migrate() async =>
    (Migrator()..register(allMigrations())).migrate();
```

The `Migrator` keeps an `_migrations(name, batch)` ledger table;
each migration is run inside `Eloquent.transaction(...)` so a
partial failure rolls back the schema change. Re-running
`migrate()` only applies new migrations.

```dart
final m = Migrator()..register(allMigrations());

await m.migrate();                  // apply pending
await m.rollback(steps: 1);         // run down() on the last batch
await m.migrate();                  // re-apply
await m.fresh();                    // drop every table + re-migrate
```

**Drop / rename columns** follow the same pattern. `ALTER TABLE
DROP COLUMN` requires SQLite 3.35+ (March 2021).

---

## API reference

### `Eloquent` facade

| Member | Description |
|---|---|
| `Eloquent.init(db)` | Wire the user's `@DriftDatabase`. Call once at app start. |
| `Eloquent.db` | The `GeneratedDatabase`. Use for joins, `customSelect` with `readsFrom`, etc. |
| `Eloquent.transaction(action)` | Run `action` inside a Drift transaction. |
| `Eloquent.raw(sql, [vars])` | Execute a SQL statement. Returns rowid for inserts. |
| `Eloquent.rawSelect(sql, [vars])` | Execute a SQL `SELECT`; returns `List<Map<String, Object?>>`. |
| `Eloquent.dispose()` | Drop the package's reference to the database. **Does not close the database** — the caller owns its lifecycle. |

### `Model<T, D>`

Abstract base.

| Member | Description |
|---|---|
| `$data` | The current row data. Mutable. |
| `$exists` | `true` after the row has been INSERTed at least once. |
| `$table` | Abstract: the Drift `TableInfo` for this model's table. |
| `$wrap(d)` | Abstract: wrap a row into this model. |
| `wrap(d)` | Internal helper: flip `$exists = true` on an existing instance. |
| `$primaryKey` | Primary-key column name. Defaults to `'id'`. |
| `toMap()` | Abstract: serialize `$data` to `Map<String, dynamic>`. |
| `toMapWithPending()` | `toMap()` merged with pending `setAttribute` writes. |
| `$casts` | Per-column cast registry. |
| `$relations` | Registry of named relations, used by `with_(...)`. |
| `$observers` | Lifecycle hooks (see Observers). |
| `$original` / `$dirty` / `$changes` | Unmodifiable views of the last snapshot, the dirty columns, and the columns that changed in the most recent lifecycle. |
| `getAttribute(key)` / `setAttribute(key, value)` | Read / write a column through the cast registry. |
| `getOriginal(key)` | The value of `key` at the last snapshot. |
| `isDirty([key])` / `isClean([key])` | `true` if `key` (or any column) has a pending write. |
| `wasChanged([key])` | `true` if `key` (or any column) was written in the most recent lifecycle. |
| `save()` | Insert (if no PK) or update (if PK present). Fires observers. |
| `update(map)` | Merge `map` into `toMap()` and update the row. |
| `delete()` | Delete the row from the database. |
| `refresh()` | Re-fetch the row from the database. |
| `saveQuietly()` / `deleteQuietly()` | Like `save` / `delete` but no observers fire. |
| `getLoaded(name)` / `isLoaded(name)` | Inspect an eagerly-loaded relation or aggregate. |
| `Model.withoutEvents(action)` | Run `action` with every observer globally suppressed. |

### `ModelQuery<T, D>`

One per model — declared as `static final _q = ModelQuery(...)` inside
the model. The forwarding statics template wraps these.

| Method | Description |
|---|---|
| `all()` / `find(id)` / `findOrFail(id)` / `first()` | Standard lookups. |
| `count()` / `exists()` | Aggregates. |
| `watch()` | `Stream<List<T>>` that re-emits on any write to the table. |
| `create(map)` / `createMany(rows)` | Insert one or many. Casts applied. Fires `created` after the row exists. |
| `firstOrCreate(attrs, [creational])` / `firstOrNew(attrs, [creational])` / `updateOrCreate(attrs, values)` / `upsert(rows, [uniqueBy])` | Idempotent creation helpers. |
| `update(map, whereColumn: ..., whereValue: ...)` | Mass update. |
| `delete(whereColumn: ..., whereValue: ...)` | Mass delete. |
| `where(c, [v, op])` | Start a chain. Equivalent to `query().where(...)`. |
| `query()` | Start an empty chain. |

### `QueryBuilder<T, D> implements Selectable<T>`

Chainable query builder. See [Chainable queries](#chainable-queries) for
the full method table.

### `Schema`

Static facade — see [Schema: declaring tables](#schema-declaring-tables).

| Method | Description |
|---|---|
| `Schema.create(table, builder)` | `CREATE TABLE`. |
| `Schema.drop(table)` | `DROP TABLE IF EXISTS`. |
| `Schema.dropUnlessExists(table)` | Bare `DROP TABLE`. |
| `Schema.table(table, builder)` | `ALTER TABLE` (uses Blueprint alter methods). |
| `Schema.hasTable(table)` | `bool`. |
| `Schema.hasColumn(table, column)` | `bool`. |
| `Schema.getColumns(table)` | `List<String>`. |
| `Schema.dropAll()` | Drop every non-`sqlite_*` table. |

### `Blueprint`

Used inside `Schema.create` / `Schema.table` closures. See
[Schema: declaring tables](#schema-declaring-tables).

### `Migration` / `Migrator`

| Method | Description |
|---|---|
| `Migration.up()` | Apply the schema change. |
| `Migration.down()` | Inverse of `up()`. |
| `Migration.name` | Identifier used by the ledger. Defaults to `runtimeType.toString()`. |
| `Migrator.register(list)` | Append migrations to the run queue. |
| `Migrator.migrate()` | Apply any not yet recorded. |
| `Migrator.rollback({steps: 1})` | Run `down()` on the most recent batch. |
| `Migrator.fresh()` | Drop every table, clear the ledger, re-migrate. |

### Exceptions

`EloquentException` is the sealed base. Subclasses:
`ColumnNotFoundException`, `TableNotFoundException`,
`ModelNotFoundException`, `UnsupportedOperatorException`,
`RelationNotFoundException`, `OperationCancelledException`,
`InvalidArgumentException`, `MultipleRecordsFoundException`,
`ModelNotSoftDeletableException`.

---

## Limitations

1. **`distinct()`** — Drift's `SimpleSelectStatement.distinct` is
   `final`, so we can't toggle it post-construction. For
   `SELECT DISTINCT …` use `Eloquent.db.customSelect(sql,
   readsFrom: {...}).watch()` directly.
2. **`ModelQuery.create()` does not fire `creating`** — it inserts
   directly, then fires `created` post-insert. Use `Model.save()`
   from an instance if you need the cancel path.
3. **Forwarding statics** — ~10 lines of boilerplate per model. A
   codegen builder is on the roadmap.
4. **`ALTER TABLE DROP COLUMN`** requires SQLite 3.35+ (March 2021)
   or newer. Older runtimes fail at execute time, not at parse time.
5. **SQLite only** — Drift itself targets SQLite (native),
   PostgreSQL (server) and Cloud Spanner. The wrapper is exercised
   against `NativeDatabase.memory()` and should work on any Drift
   backend, but the Blueprint DSL emits SQLite-flavored DDL.
6. **`watch()` with `withCount` / `withSum` / etc.** falls back to a
   one-shot `get()` — the reactive path through Drift's `addColumns`
   isn't fully re-implemented yet.

---

## Roadmap

- Codegen of forwarding statics (`eloquent_flutter_codegen` builder)
- Local scopes
- `selectRaw`, `whereRaw(String)` for raw SQL fragments with bindings
- Full sync engine / offline-first
- PostgreSQL / Cloud Spanner parity tests

---

## Contributing

Issues and pull requests are welcome. For anything beyond a typo:

1. Open an issue describing the change you want to make and why.
2. Wait for a maintainer to acknowledge before sending large PRs.
3. Make sure `dart test` and `dart analyze` both pass.

The benchmark suite is the source of truth for performance
regressions. Run it before and after a change that touches the
read path:

```bash
dart test
dart analyze
dart run benchmark/eloquent_vs_drift.dart
```

---

## Maintainer

**Ravdeep Singh**  
Lead Developer, Ubxty

- [github.com/ubxty](https://github.com/ubxty)
- [linkedin.com/in/ravdeep-singh-a4544abb](https://www.linkedin.com/in/ravdeep-singh-a4544abb/)
- [info.ubxty@gmail.com](mailto:info.ubxty@gmail.com)
- [ubxty.com](https://ubxty.com)

Built and maintained as part of the Ubxty open-source stack. Also see
[**ubxcert**](https://github.com/ubxty/ubxcert) — a dependency-free
ACME v2 / Let's Encrypt CLI written in PHP, the same author's
companion project.

---

## License

MIT © [Ubxty](https://ubxty.com)
