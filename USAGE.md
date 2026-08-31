# Usage guide

A focused reference for common `eloquent_flutter` patterns. For the full
API surface and rationale, see [README.md](./README.md).

## Setup checklist

```text
[ ] pubspec.yaml: drift + eloquent_flutter
[ ] lib/database.dart: declare Drift tables + @DriftDatabase
[ ] dart run build_runner build        # generate database.g.dart
[ ] lib/migrations/*.dart: write migrations
[ ] lib/migrations/migrations.dart: register them
[ ] lib/registry.dart: AppRegistry init + getters
[ ] lib/models/*.dart: extend Model<T, D>, add forwarding statics
[ ] lib/main.dart: Eloquent.init, AppRegistry.init, migrate()
```

---

## CRUD

```dart
// Create
final u = await User.create({'email': 'a@b', 'name': 'A'});

// Read
final all   = await User.all();
final one   = await User.find(1);
final need  = await User.findOrFail(1);    // throws ModelNotFoundException
final first = await User.where('active', true).first();

// Update
await u.update({'name': 'New'});
await User.where('active', false).update({'active': true});  // mass update

// Delete
await u.delete();
await User.where('id', [1, 2, 3], 'in').delete();           // mass delete

// Refresh from DB
await u.refresh();
```

---

## Querying

```dart
final result = await User
    .where('active', true)              // =
    .where('age', '>', 18)              // >, >=, <, <=
    .where('email', '%@example.com', 'like')   // LIKE / NOT LIKE
    .where('id', [1, 2, 3], 'in')       // IN / NOT IN
    .whereNull('verified_at')           // IS NULL / IS NOT NULL
    .whereBetween('age', 18, 65)        // BETWEEN a AND b
    .orWhere('role', 'admin')           // OR-join
    .orderBy('name')                    // ASC
    .orderByDesc('created_at')          // DESC
    .limit(20)
    .offset(40)
    .get();
```

```dart
// Drop to Drift for anything else
User.query()
    .whereRaw((u) => u.email.like('%@example.com') | u.name.like('Admin%'))
    .get();

// Aggregates
final total  = await User.count();
final hasAny = await User.exists();
```

Supported operators: `=`, `==`, `!=`, `<>`, `>`, `>=`, `<`, `<=`,
`like`, `not like`, `in`, `not in`, `is null`, `is not null`, `between`.

---

## Pagination

```dart
final page = await User.where('active', true).paginate(page: 2, perPage: 20);

page.data;          // List<User>
page.currentPage;   // 2
page.lastPage;      // 5
page.total;         // 100
page.perPage;       // 20
page.hasMore;       // true
page.hasPrevious;   // true

final next = await page.nextPage();
final prev = await page.previousPage();
```

---

## Reactive streams

```dart
// Re-emits whenever the underlying table is written to.
final users$ = User.watch();                           // Stream<List<User>>
final one$  = User.where('id', 1).watchSingleOrNull(); // Stream<User?>

// Flutter
StreamBuilder<List<User>>(
  stream: users$,
  builder: (ctx, snap) => /* ... */,
);

// Any write touches the stream — including raw SQL via Drift's
// customInsert / customUpdate / customWriteReturning.
```

---

## Transactions

```dart
await Eloquent.transaction(() async {
  final u = await User.create({'email': 'x@y', 'name': 'x'});
  await Post.create({'user_id': u.toMap()['id'], 'title': 'first'});
  if (bad) throw StateError('rolled back');   // everything unwinds
});

// Nested calls reuse the outer transaction.
```

---

## Raw SQL

```dart
// DML / DDL — returns rowid for inserts
await Eloquent.raw(
  'UPDATE users SET active = ? WHERE last_login < ?',
  [false, DateTime.now().subtract(Duration(days: 90))],
);

// Ad-hoc SELECT
final rows = await Eloquent.rawSelect(
  'SELECT email, COUNT(*) AS n FROM users GROUP BY email HAVING n > 1',
);
// rows: List<Map<String, Object?>>

// Reactive raw SELECT — re-emits on table writes
final stream = Eloquent.db
    .customSelect('SELECT * FROM users', readsFrom: {Eloquent.db.users})
    .watch();
```

---

## Relationships

### Declare

```dart
class User extends Model<User, UserRow> {
  HasMany<Post, PostRow>    posts()   => HasMany<Post, PostRow>(
    local: this, relatedTable: AppRegistry.posts,
    foreignKey: 'user_id', creator: Post.new,
  );

  HasOne<Profile, ProfileRow> profile() => HasOne<Profile, ProfileRow>(
    local: this, relatedTable: AppRegistry.profiles,
    foreignKey: 'user_id', creator: Profile.new,
  );

  BelongsToMany<Role, RoleRow> roles() => BelongsToMany<Role, RoleRow>(
    local: this, relatedTable: AppRegistry.roles,
    creator: Role.new,
    pivotTable: 'role_users',
    foreignPivotKey: 'user_id', relatedPivotKey: 'role_id',
  );
}

class Post extends Model<Post, PostRow> {
  BelongsTo<User, UserRow> user() => BelongsTo<User, UserRow>(
    local: this, relatedTable: AppRegistry.users,
    foreignKey: 'user_id', creator: User.new,
  );
}
```

### Use

```dart
final posts   = await alice.posts().get();           // List<Post>
final profile = await alice.profile().get();         // Profile?
final owner   = await firstPost.user().get();        // User?

// Streams
final liveOwner = firstPost.user().watch();          // Stream<User?>

// HasMany / HasOne auto-fill the FK on create
final p = await alice.posts().create({'title': 'hi', 'body': '...'});  // p.user_id == alice.id

// BelongsToMany — pivot manipulation
await alice.roles().attach(adminId);
await alice.roles().detach(editorId);
await alice.roles().sync([adminId]);                  // full replace
final roles = await alice.roles().get();
```

---

## Eager loading

```dart
final users = await User.query().with_(['posts', 'profile']).get();

for (final u in users) {
  if (u.isLoaded('posts')) {
    for (final p in u.getLoaded<List<Post>>('posts')) {
      print('  - ${p.toMap()['title']}');
    }
  }
}
```

Keys must match `$relations` on the model; otherwise
`RelationNotFoundException` lists available relations.

---

## Observers

```dart
class User extends Model<User, UserRow> {
  @override
  ObserverSet get $observers => ObserverSet(
    // Return false to cancel — throws OperationCancelledException.
    creating: (u) => (u.toMap()['email'] as String).contains('@'),
    created:  (u) => print('saved ${u.toMap()["id"]}'),
    updating: (u) => true,
    updated:  (u) => print('updated ${u.toMap()["id"]}'),
    deleting: (u) => true,
    deleted:  (u) => print('deleted ${u.toMap()["id"]}'),
  );
}
```

Order on `save()` / `update()` / `delete()`:

```
creating → INSERT → created
updating → UPDATE → updated
deleting → DELETE → deleted
```

`ModelQuery.create()` inserts via Drift directly and fires `created`
without `creating`. To cancel, use `Model.save()` from an instance.

---

## Auto timestamps

```dart
class User extends Model<User, UserRow> with WithTimestamps { … }
```

Sets `created_at = now()` on first `save()` (if null) and bumps
`updated_at = now()` on every `save()` / `update()`. No-ops if the
columns are missing.

---

## Schema

### Declare tables

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
  t.index(['user_id', 'created_at']);
});
```

### Inspect / drop

```dart
final hasUsers = await Schema.hasTable('users');
final cols     = await Schema.getColumns('users');      // ['id', 'email', ...]
final hasEmail = await Schema.hasColumn('users', 'email');

await Schema.drop('posts');
await Schema.dropAll();
```

### Column helpers + modifiers

| Helper | Storage |
|---|---|
| `t.id()` | `INTEGER PRIMARY KEY AUTOINCREMENT` |
| `t.string(n)` | `TEXT` |
| `t.text(n)` | `TEXT` |
| `t.integer(n)` | `INTEGER` |
| `t.real(n)` | `REAL` |
| `t.boolean(n)` | `INTEGER` (0/1) |
| `t.dateTime(n)` | `TEXT` |
| `t.blob(n)` | `BLOB` |
| `t.timestamps()` | nullable `created_at` + `updated_at` |

```dart
t.string('email').unique_();
t.string('nickname').nullable_();
t.string('slug').default_('untitled');
t.boolean('verified').default_(false);
```

### Constraints

```dart
t.compositePrimary(['user_id', 'role_id']);
t.foreign('user_id', references: 'users.id', onDelete: 'CASCADE');
t.index(['user_id', 'created_at']);
t.unique(['user_id', 'slug']);
```

---

## Migrations

### Define one

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

### Register + run

```dart
List<Migration> allMigrations() => const <Migration>[
  CreateUsers(),
  AddUserPhone(),
  // append new migrations here as you ship them
];

Future<void> migrate() async =>
    (Migrator()..register(allMigrations())).migrate();
```

### Evolving tables

```dart
// Drop
await Schema.table('users', (t) { t.dropColumn('legacy'); });

// Rename (then update Drift table def + re-run build_runner)
await Schema.table('users', (t) { t.renameColumn('name', 'full_name'); });

// Drop index
await Schema.table('users', (t) { t.dropIndex(['email']); });
```

### Run lifecycle

```dart
final m = Migrator()..register(allMigrations());

await m.migrate();                  // apply pending
await m.rollback(steps: 1);         // last batch's down()
await m.migrate();                  // re-apply
await m.fresh();                    // drop everything + re-migrate
```

The migrator keeps an `_migrations(name, batch)` ledger and runs each
migration inside `Eloquent.transaction(...)` so a partial failure
rolls back the schema change.

---

## Error cheat sheet

| Exception | When |
|---|---|
| `ModelNotFoundException` | `findOrFail` misses. |
| `ColumnNotFoundException` | Unknown column in a Map / `Companion`. |
| `TableNotFoundException` | Drift-side lookup misses. |
| `RelationNotFoundException` | `with_(name)` not in `$relations`. |
| `UnsupportedOperatorException` | Operator string not in the supported set. |
| `InvalidArgumentException` | Operator/value type mismatch (e.g. LIKE on int). |
| `OperationCancelledException` | Observer returned `false`. |