# eloquent_flutter

Laravel Eloquent-style ORM for Flutter and Dart, built on top of
[Drift](https://drift.simonbinder.eu/).

> **Status: v0.1.0** — initial implementation. API may change before 1.0.

---

## Table of contents

1. [Why](#why)
2. [Features](#features)
3. [Install](#install)
4. [Quick start](#quick-start)
5. [Usage guide](#usage-guide)
   - [Database setup](#database-setup)
   - [The registry pattern](#the-registry-pattern)
   - [Defining a model](#defining-a-model)
   - [Forwarding statics](#forwarding-statics)
   - [Creating records](#creating-records)
   - [Reading records](#reading-records)
   - [Updating and deleting](#updating-and-deleting)
   - [Chainable queries](#chainable-queries)
   - [Operators](#operators)
   - [Aggregates](#aggregates)
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
8. [v2 roadmap](#v2-roadmap)
9. [License](#license)

---

## Why

Drift is one of the most powerful SQLite ORMs available in Dart, but
its day-to-day API is verbose:

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

`eloquent_flutter` is a **thin wrapper** on top of Drift. It doesn't
ship its own database, table DSL, or codegen — you keep your existing
`@DriftDatabase` and the generated row classes. The package just gives
you chainable queries, relationships, eager loading, observers,
pagination, timestamps, and a Laravel-style `Schema` / `Migrator` for
declarative DDL.

---

## Features

- **Forwarding statics** — `User.all()`, `User.find(id)`,
  `User.create(map)`, `User.where(...)`, …
- **Chainable `QueryBuilder<T, D>`** that also implements Drift's
  `Selectable<T>` — so `.get()`, `.watch()`, `.getSingleOrNull()` all
  work for free.
- **Rich operator set** — `=`, `!=`, `<`, `<=`, `>`, `>=`, `LIKE`,
  `NOT LIKE`, `IN`, `NOT IN`, `IS NULL`, `IS NOT NULL`, `BETWEEN`.
- **Reactive streams** — `watch()`, `watchSingle()`, `watchSingleOrNull()`
  re-emit on any write to the underlying table.
- **Transactions** — `Eloquent.transaction(() async { ... })`.
- **Raw SQL escape hatch** — `Eloquent.raw(sql, [vars])`,
  `Eloquent.rawSelect(sql, [vars])`.
- **Relationships** — `HasMany`, `HasOne`, `BelongsTo`, `BelongsToMany`
  with `attach` / `detach` / `sync`.
- **Eager loading** — `User.query().with_(['posts', 'profile']).get()`
  batches the related fetches.
- **Lifecycle observers** — `creating` / `created` / `updating` /
  `updated` / `deleting` / `deleted`. The first three can cancel the
  operation by returning `false`.
- **Pagination** — `Paginator<T>` with `data`, `currentPage`, `lastPage`,
  `total`, `hasMore`, `nextPage()`, `previousPage()`.
- **Auto timestamps** — opt-in `WithTimestamps` mixin.
- **Schema + Migrations** — Laravel-style `Schema.create()` /
  `Schema.table()` with a Blueprint DSL, plus a `Migrator` that tracks
  applied migrations in an `_migrations` ledger and supports `up()` /
  `down()` rollbacks.

---

## Install

```yaml
dependencies:
  drift: ^2.18.0
  eloquent_flutter:
    git: https://github.com/your-org/eloquent_flutter.git
```

Or for a local checkout:

```yaml
dependencies:
  eloquent_flutter:
    path: ../eloquent_flutter
```

Then `dart pub get`. The example app uses Drift's
`NativeDatabase.memory()`; for production, point `AppDatabase` at a
`NativeDatabase(file)` (or `flutter` for cross-platform).

---

## Quick start

The end-to-end loop looks like this:

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

The full example in `example/` runs through every feature; clone,
`dart pub get`, `dart run build_runner build`, `dart run lib/main.dart`.

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

Call `AppRegistry.init(db)` immediately after `Eloquent.init(db)` and
anywhere in the app you can read `AppRegistry.users`.

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

class User extends Model<User, UserRow> {
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

  // Relationships (see the Relationships section for details).
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

  // Eager-loading registry — `with_('posts')` looks up these strings.
  @override
  Map<String, Relationship<dynamic>> get $relations => {
        'posts':   posts(),
        'profile': profile(),
        'roles':   roles(),
      };

  // Lifecycle hooks (see Observers section).
  @override
  ObserverSet get $observers => ObserverSet(
        creating: (u) => (u.toMap()['email'] as String).contains('@'),
        created:  (u) => print('User created: id=${u.toMap()["id"]}'),
      );

  // Forwarding statics — copy/paste per model (see next section).
  static final _q = ModelQuery<User, UserRow>(
    table: AppRegistry.users,
    creator: User.new,
    primaryKey: 'id',
  );

  static Future<List<User>>   all()                              => _q.all();
  static Future<User?>        find(Object id)                    => _q.find(id);
  static Future<User>         findOrFail(Object id)             => _q.findOrFail(id);
  static Future<User?>        first({String? orderBy})          => _q.first(orderBy: orderBy);
  static Future<int>          count()                            => _q.count();
  static Future<bool>         exists()                           => _q.exists();
  static Stream<List<User>>   watch()                            => _q.watch();
  static Future<User>         create(Map<String, dynamic> v)     => _q.create(v);
  static Future<int>          createMany(List<Map<String, dynamic>> rows) =>
      _q.createMany(rows);
  static QueryBuilder<User, UserRow> where(
          String c, [Object? v, String op = '=']) =>
      _q.where(c, v, op);
  static QueryBuilder<User, UserRow> query()                     => _q.query();
}
```

`Model<T, D>` takes two type parameters: `T` is the model class itself
(used for covariant returns) and `D` is the Drift-generated row class.
`$table`, `$wrap`, and `toMap()` are abstract — every model must
implement them.

### Forwarding statics

The block at the bottom of the model (`static Future<List<User>> all()
=> _q.all();`, etc.) is what gives you Laravel-style ergonomics.
`ModelQuery<T, D>` holds the table + creator and exposes the
underlying operations. Per model this is roughly ten lines.

The v2 roadmap has a codegen builder that collapses this into an
annotation; for now, copy/paste and adjust the types.

### Creating records

```dart
final user = await User.create({
  'email': 'alice@example.com',
  'name':  'Alice',
});
```

`create()` inserts the row and fires the `created` observer (see
Observers). To cancel before insert, build the instance yourself and
use `save()`:

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
await user.refresh();          // re-fetch from DB

// Mass operations on a query
final affected = await User.where('active', false).update({'active': true});
final deleted  = await User.where('id', [1, 2, 3], 'in').delete();
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
| `whereBetween(c, a, b)` | Inclusive `BETWEEN` (composed as `>= a AND <= b`). |
| `whereRaw(expr)` | Drop down to a Drift `Expression<bool>`. |
| `orderBy(c, {descending: false})` | Sort ascending by default. |
| `orderByDesc(c)` | Sugar for `orderBy(c, descending: true)`. |
| `limit(n)` / `offset(k)` | Pagination slicing. |
| `with_(name)` / `with_([names])` | Eager-load named relations. |
| `first()` | First row, or null. |
| `count()` / `exists()` | Aggregates. |
| `update(map)` | Mass update matching rows. |
| `delete()` | Mass delete matching rows. |
| `paginate({page, perPage})` | Returns a `Paginator<T>`. |

Because `QueryBuilder<T, D>` implements `Selectable<T>`, all of Drift's
terminal methods work too: `.get()`, `.watch()`, `.getSingleOrNull()`,
`.watchSingleOrNull()`, plus the `map` / `asyncMap` overloads for
custom result transformations.

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
`InvalidArgumentException` (e.g. `LIKE` on an integer column, `>` on a
boolean column).

For anything beyond the operator string set, drop to `whereRaw` with a
typed Drift expression:

```dart
import 'package:drift/drift.dart' show OrderingTerm;

User.query().whereRaw((u) => u.email.like('%@example.com')).get();
```

### Aggregates

`count()` and `exists()` are cheap aggregate shorthands:

```dart
final total  = await User.count();
final hasAny = await User.exists();
final admins = await User.where('role', 'admin').count();
```

### Reactive streams

`watch()` re-emits whenever the table is written to. This pairs with
`StreamBuilder` in Flutter:

```dart
final users$ = User.watch();   // Stream<List<User>>
final one$  = User.where('id', 1).watchSingleOrNull();   // Stream<User?>

// Anywhere:
StreamBuilder<List<User>>(
  stream: User.watch(),
  builder: (ctx, snap) => ListView(children: /* snap.data!.map(...) */),
);
```

Streams are powered by Drift's reactive query engine, so any write that
touches the underlying table — including raw SQL via `customInsert`,
`customUpdate`, or `customWriteReturning` — triggers a re-emission.

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

`Eloquent.transaction()` runs the action inside a Drift transaction:

```dart
await Eloquent.transaction(() async {
  final u = await User.create({'email': 'x@y', 'name': 'x'});
  await Post.create({'user_id': u.toMap()['id'], 'title': 'first'});
  if (somethingWentWrong) {
    throw StateError('rolled back');   // everything unwinds
  }
});
```

Nested transactions: nested `transaction` calls reuse the outer
transaction in Drift, so this composes naturally.

### Raw SQL

When you need to escape the wrapper:

```dart
// DML / DDL that returns nothing
await Eloquent.raw(
  'UPDATE users SET active = ? WHERE last_login < ?',
  [false, DateTime.now().subtract(Duration(days: 90))],
);

// Ad-hoc SELECTs
final rows = await Eloquent.rawSelect(
  'SELECT email, COUNT(*) AS n FROM users GROUP BY email HAVING n > 1',
);
// rows: List<Map<String, Object?>>
```

For reactive SELECTs that should re-emit on table writes, use Drift's
native `customSelect`:

```dart
final stream = Eloquent.db
    .customSelect('SELECT * FROM users', readsFrom: {Eloquent.db.users})
    .watch();
```

### Relationships

Declare relationships on the model as instance methods:

```dart
class User extends Model<User, UserRow> {
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
}

class Post extends Model<Post, PostRow> {
  BelongsTo<User, UserRow> user() => BelongsTo<User, UserRow>(
    local: this,
    relatedTable: AppRegistry.users,
    foreignKey: 'user_id',
    creator: User.new,
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

The pivot table defaults to `'<local_singular>_<related_singular>'`
(e.g. `role_user`) — override with `pivotTable:`. Foreign-key columns
default to `'<local_singular>_id'` / `'<related_singular>_id'` — use
`foreignPivotKey:` and `relatedPivotKey:` for non-standard naming.

### Eager loading

Eager loading batches the related fetches into one query per relation,
so `User.query().with_(['posts', 'profile']).get()` runs three
queries instead of `1 + N`.

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

Hooks fire in this order on instance `save()` / `update()` / `delete()`:

```
creating → INSERT → created
updating → UPDATE → updated
deleting → DELETE → deleted
```

`ModelQuery.create()` bypasses the cancel path (`creating`) because it
inserts via Drift directly, then fires `created` post-insert. If you
need cancellation, use `Model.save()` from an instance.

Returning `false` from `creating` / `updating` / `deleting` aborts the
operation and throws `OperationCancelledException`.

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

The `Schema` facade emits SQL via a Blueprint DSL. SQLite storage types
are inferred from the column helpers; modifiers are chainable.

```dart
await Schema.create('users', (t) {
  t.id();
  t.string('email').unique_();
  t.string('name');
  t.boolean('active').default_(true);
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
// lib/migrations/m_2026_08_31_create_users.dart
class CreateUsers extends Migration {
  const CreateUsers();

  @override
  Future<void> up() async {
    await Schema.create('users', (t) {
      t.id();
      t.string('email').unique_();
      t.string('name');
      t.boolean('active').default_(true);
      t.timestamps();
    });
  }

  @override
  Future<void> down() async {
    await Schema.drop('users');
  }
}

// lib/migrations/migrations.dart
List<Migration> allMigrations() => const <Migration>[
  CreateUsers(),
  // append new migrations here as you ship them
];

Future<void> migrate() async =>
    (Migrator()..register(allMigrations())).migrate();
```

The `Migrator` keeps an `_migrations(name, batch)` ledger table; each
migration is run inside `Eloquent.transaction(...)` so a partial
failure rolls back the schema change. Re-running `migrate()` only
applies new migrations.

```dart
final m = Migrator()..register(allMigrations());

await m.migrate();                  // apply pending
await m.rollback(steps: 1);         // run down() on the last batch
await m.migrate();                  // re-apply
await m.fresh();                    // drop every table + re-migrate
```

#### Changing tables over time

The workflow for evolving an existing schema is the same as in Laravel:
write a new migration, append it to the list, ship.

**Add a column:**

```dart
class AddUserPhone extends Migration {
  const AddUserPhone();

  @override
  Future<void> up() async {
    await Schema.table('users', (t) {
      t.addColumn('string', 'phone', defaultValue: '');
    });
  }

  @override
  Future<void> down() async {
    await Schema.table('users', (t) {
      t.dropColumn('phone');
    });
  }
}
```

Then append it:

```dart
List<Migration> allMigrations() => const <Migration>[
  CreateUsers(),
  AddUserPhone(),
];
```

**Drop a column:**

```dart
@override
Future<void> up() async {
  await Schema.table('users', (t) {
    t.dropColumn('legacy_field');
  });
}
```

Requires SQLite 3.35+ (March 2021) for `ALTER TABLE ... DROP COLUMN`.

**Rename a column:**

```dart
@override
Future<void> up() async {
  await Schema.table('users', (t) {
    t.renameColumn('name', 'full_name');
  });
}
```

After renaming, update the Drift `Table` definition and re-run
`build_runner` so the generated row class matches.

**Drop an index:**

```dart
@override
Future<void> up() async {
  await Schema.table('users', (t) {
    t.dropIndex(['email']);    // matches `idx_users_email`
  });
}
```

`Schema.table()` accepts any combination of `addColumn`, `dropColumn`,
`renameColumn`, and `dropIndex` calls in a single closure — each is
emitted as its own `ALTER TABLE` statement in order.

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
| `Eloquent.dispose()` | Close the database and reset state. Mostly for tests. |

### `Model<T, D>`

Abstract base.

| Member | Description |
|---|---|
| `$data` | The current row data. Mutable. |
| `$table` | Abstract: the Drift `TableInfo` for this model's table. |
| `$wrap(d)` | Abstract: wrap a row into this model. |
| `$primaryKey` | Primary-key column name. Defaults to `'id'`. |
| `toMap()` | Abstract: serialize `$data` to `Map<String, dynamic>`. |
| `$relations` | Registry of named relations, used by `with_(...)`. |
| `$observers` | Lifecycle hooks (see Observers). |
| `save()` | Insert (if no PK) or update (if PK present). Fires observers. |
| `update(map)` | Merge `map` into `toMap()` and update the row. |
| `delete()` | Delete the row from the database. |
| `refresh()` | Re-fetch the row from the database. |
| `getLoaded<T>(name)` / `isLoaded(name)` | Inspect an eagerly-loaded relation. |

### `ModelQuery<T, D>`

One per model — declared as `static final _q = ModelQuery(...)` inside
the model. The forwarding statics template wraps these.

| Method | Description |
|---|---|
| `all()` / `find(id)` / `findOrFail(id)` / `first()` | Standard lookups. |
| `count()` / `exists()` | Aggregates. |
| `watch()` | `Stream<List<T>>` that re-emits on any write to the table. |
| `create(map)` / `createMany(rows)` | Insert one or many. Fires `created` after the row exists. |
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

`Migration` is the abstract base. `Migrator` runs them.

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
`InvalidArgumentException`.

---

## Limitations

1. **`distinct()`** — Drift's `SimpleSelectStatement.distinct` is
   `final`, so we can't toggle it post-construction. For
   `SELECT DISTINCT …` use `Eloquent.db.customSelect(sql,
   readsFrom: {...}).watch()` directly.
2. **`ModelQuery.create()` does not fire `creating`** — it inserts
   directly, then fires `created` post-insert. Use `Model.save()` from
   an instance if you need the cancel path.
3. **Forwarding statics** — ~10 lines of boilerplate per model. The v2
   roadmap includes a codegen builder that collapses this.
4. **`ALTER TABLE DROP COLUMN`** requires SQLite 3.35+ (March 2021) or
   newer. Older runtimes fail at execute time, not at parse time.
5. **SQLite only** — Drift itself targets SQLite (native), PostgreSQL
   (server) and Cloud Spanner. The wrapper is exercised against
   `NativeDatabase.memory()` and should work on any Drift backend, but
   the Blueprint DSL emits SQLite-flavored DDL.

---

## v2 roadmap

- Local scopes (`static QueryBuilder<User, UserRow> active() => where('active', true);`)
- Soft deletes (`deleted_at` mixin)
- Model casts (JSON / date / enum)
- `selectRaw`, `whereRaw(String)` for raw SQL with bindings
- Codegen of forwarding statics (`eloquent_flutter_codegen` builder)
- Full sync engine / offline-first
- PostgreSQL/Cloud Spanner parity tests

---

## License

MIT.