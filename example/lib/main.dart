/// Example entry point for `eloquent_flutter`.
///
/// Wires up an in-memory SQLite database, runs the Eloquent-style
/// migrations, then exercises every feature of the wrapper (CRUD,
/// forwarding statics, chainable queries, relationships, eager loading,
/// pagination, observers, reactive streams, transactions, raw SQL,
/// schema rollback, casts, soft deletes, dirty tracking, withCount,
/// saveQuietly, firstOrCreate, updateOrCreate, pluck / value / sole).
///
/// Run with:
///   cd example
///   dart pub get
///   dart run build_runner build
///   dart run lib/main.dart
library;

import 'package:drift/native.dart';
import 'package:eloquent_flutter/eloquent_flutter.dart';

import 'database.dart';
import 'migrations/migrations.dart';
import 'models/post.dart';
import 'models/profile.dart';
import 'models/role.dart';
import 'models/user.dart';
import 'registry.dart';

Future<void> main() async {
  // 1. Open an in-memory database and register it with Eloquent.
  final db = AppDatabase(NativeDatabase.memory());
  Eloquent.init(db);
  AppRegistry.init(db);

  // 2. Run all pending migrations. The Migrator owns the schema lifecycle
  //    — Drift's built-in `MigrationStrategy` is a no-op.
  print('=== Migrations ===');
  await migrate();
  print('users columns: ${await Schema.getColumns('users')}');
  print('role_users columns: ${await Schema.getColumns('role_users')}');

  // 3. Bootstrap a few rows. JSON cast via $casts round-trips through
  //    the wrapper.
  print('\n=== Seeding ===');
  final alice = await User.create({
    'email': 'alice@example.com',
    'name': 'Alice',
    'meta': {'theme': 'dark', 'plan': 'pro'},
  });
  final bob = await User.create({
    'email': 'bob@example.com',
    'name': 'Bob',
  });
  await Post.create({'user_id': alice.toMap()['id'], 'title': 'First post'});
  await Post.create({'user_id': alice.toMap()['id'], 'title': 'Second post'});
  await Profile.create({
    'user_id': alice.toMap()['id'],
    'bio': 'Hello, world',
  });

  // 4. Casts: read a JSON column through the cast registry.
  print('\n=== Casts ===');
  final meta = alice.getAttribute('meta') as Map<String, dynamic>;
  print('alice.meta: $meta');

  // 5. Forwarding statics.
  print('\n=== Forwarding statics ===');
  print('All users: ${(await User.all()).length}');
  print('Find alice: '
      '${(await User.find(alice.toMap()['id']))?.toMap()['email']}');
  print('Count: ${await User.count()}');
  print('Exists: ${await User.exists()}');

  // 6. Chainable query — full operator set.
  print('\n=== Chainable query ===');
  final alices = await User.where('email', '%alice%', 'like').get();
  print('LIKE alice: ${alices.length}');
  final oneUser = await User.where('active', true).first();
  print('First active: ${oneUser?.toMap()['name']}');
  final inSet = await User.where('id', [alice.toMap()['id'], 999], 'in').get();
  print('IN: ${inSet.length}');
  final between = await User.query().whereBetween('id', 1, 100).get();
  print('BETWEEN 1..100: ${between.length}');

  // 7. Relationships.
  print('\n=== Relationships ===');
  final alicePosts = await alice.posts().get();
  print('alice.posts(): ${alicePosts.length}');
  final aliceProfile = await alice.profile().get();
  print('alice.profile(): ${aliceProfile?.toMap()['bio']}');
  final firstPost = alicePosts.first;
  final postOwner = await firstPost.user().get();
  print('firstPost.user(): ${postOwner?.toMap()['email']}');

  // 8. Aggregates — count / min / max / avg / sum.
  print('\n=== Aggregates ===');
  print('user count: ${await User.count()}');
  print('user max id: ${await User.query().max('id')}');
  print('user min id: ${await User.query().min('id')}');
  print('post count: ${await Post.count()}');

  // 9. BelongsToMany — attach, sync.
  print('\n=== BelongsToMany ===');
  final adminRole = await Role.create({'name': 'admin'});
  final editorRole = await Role.create({'name': 'editor'});
  await alice.roles().attach(adminRole.toMap()['id']);
  await alice.roles().attach(editorRole.toMap()['id']);
  print('alice.roles(): ${(await alice.roles().get()).length}');
  await alice.roles().sync([adminRole.toMap()['id']]);
  print('alice.roles() after sync to [admin]: '
      '${(await alice.roles().get()).length}');

  // 10. Eager loading.
  print('\n=== Eager loading ===');
  final users = await User.query().with_(['posts', 'profile']).get();
  for (final u in users) {
    final loaded = u.isLoaded('posts') ? u.getLoaded('posts') : null;
    print('User ${u.toMap()['name']}: loaded $loaded');
  }

  // 11. withCount / withSum / withAvg / whereHas need a RelationSpec
  //     passed to QueryBuilder — the model's $relations registry is
  //     used by `with_(...)` (eager loading) but not by the has/whereHas
  //     /withCount family, which need a `relations: { ... }` map on the
  //     QueryBuilder constructor. See `test/p0_features_test.dart` for
  //     the relation-spec example. Skipped here to keep the demo
  //     focused on the static API.

  // 12. Pagination.
  print('\n=== Pagination ===');
  for (var page = 1; page <= 2; page++) {
    final p = await User.query().paginate(page: page, perPage: 1);
    print('Page $page: data=${p.data.length} last=${p.lastPage} '
        'hasMore=${p.hasMore}');
  }

  // 13. Observer fired for `created`.
  print('\n=== Observer fired for `created` ===');
  await User.create({'email': 'dave@example.com', 'name': 'Dave'});
  // (Watch stdout for the "User created: id=..." line printed by the
  // observer's `created` hook on User.)

  // 14. Reactive stream.
  print('\n=== Reactive stream ===');
  final sub = User.watch().listen((list) {
    print('Stream emitted: ${list.length} users');
  });
  await User.create({'email': 'eve@example.com', 'name': 'Eve'});
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await sub.cancel();

  // 15. Dirty tracking.
  print('\n=== Dirty tracking ===');
  alice.setAttribute('name', 'Alice in Wonderland');
  print('isDirty(name): ${alice.isDirty('name')}');
  print('wasChanged would-be: ${alice.wasChanged()}');
  await alice.save();
  print('after save — isDirty: ${alice.isDirty()}, '
      'wasChanged: ${alice.wasChanged()}');
  await alice.refresh();
  print('after refresh — isDirty: ${alice.isDirty()}, '
      'wasChanged: ${alice.wasChanged()}');

  // 16. Soft deletes.
  print('\n=== Soft deletes ===');
  print('before delete — User.count: ${await User.count()}, '
      'withTrashed: ${(await User.withTrashed().get()).length}');
  await bob.delete();
  await bob.refresh();
  print('bob.trashed: ${bob.trashed}');
  print('after delete — User.count: ${await User.count()}, '
      'withTrashed: ${(await User.withTrashed().get()).length}, '
      'onlyTrashed: ${(await User.onlyTrashed().get()).length}');
  await bob.restore();
  print('after restore — User.count: ${await User.count()}, '
      'bob.trashed: ${bob.trashed}');
  await bob.delete();
  await bob.refresh();
  await bob.forceDelete();
  print('after forceDelete — withTrashed: '
      '${(await User.withTrashed().get()).length}');

  // 17. saveQuietly + firstOrCreate / updateOrCreate.
  print('\n=== saveQuietly + firstOrCreate / updateOrCreate ===');
  await Model.withoutEvents(() async {
    await User.create({'email': 'silent@example.com', 'name': 'Silent'});
  });
  final carol = await User.firstOrCreate(
    {'email': 'carol@example.com'},
    {'name': 'Carol'},
  );
  print('firstOrCreate carol: id=${carol.toMap()['id']}');
  final carol2 = await User.firstOrCreate(
    {'email': 'carol@example.com'},
    {'name': 'Carol'},
  );
  print('firstOrCreate carol (idempotent): id=${carol2.toMap()['id']}');
  final upgraded =
      await User.updateOrCreate({'email': 'carol@example.com'}, {'name': 'Carol C'});
  print('updateOrCreate — name: ${upgraded.toMap()['name']}');

  // 18. pluck / value / sole.
  print('\n=== pluck / value / sole ===');
  final names = await User.query().pluck('name') as List<dynamic>;
  print('names: $names');
  final firstName = await User.query().orderBy('id').value('name');
  print('first name: $firstName');
  final sole = await (User.query()..where('email', 'alice@example.com')).sole();
  print('sole: ${sole.toMap()['email']}');

  // 19. Transaction + raw SQL.
  print('\n=== Transaction ===');
  await Eloquent.transaction(() async {
    await User.create({'email': 'frank@example.com', 'name': 'Frank'});
    await Post.create({
      'user_id': alice.toMap()['id'],
      'title': 'Bob post',
    });
  });
  print('Total users after txn: ${await User.count()}');

  // 20. Schema rollback — drop the third migration's columns, inspect,
  //     then re-apply it.
  print('\n=== Schema change workflow ===');
  print('users columns before rollback: '
      '${await Schema.getColumns('users')}');
  final migrator = Migrator()..register(allMigrations());
  await migrator.rollback(steps: 1);
  print('users columns after rollback: '
      '${await Schema.getColumns('users')}');
  await migrator.migrate();
  print('users columns after re-migrate: '
      '${await Schema.getColumns('users')}');

  // 21. Cleanup. Eloquent.dispose() does NOT close the database — the
  //     caller owns the lifecycle. We close db explicitly here because
  //     this is the end of the process.
  await Eloquent.dispose();
  await db.close();
  print('\n=== Done ===');
}
