/// Example entry point for `eloquent_flutter`.
///
/// Wires up an in-memory SQLite database, runs the Eloquent-style
/// migrations, then exercises every feature of the wrapper (CRUD,
/// forwarding statics, chainable queries, relationships, eager loading,
/// pagination, observers, reactive streams, transactions, raw SQL, and
/// schema rollback).
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

  // 3. Bootstrap a few rows.
  print('\n=== Seeding ===');
  final alice = await User.create({
    'email': 'alice@example.com',
    'name': 'Alice',
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

  // 4. Forwarding statics.
  print('\n=== Forwarding statics ===');
  print('All users: ${(await User.all()).length}');
  print('Find alice: '
      '${(await User.find(alice.toMap()['id']))?.toMap()['email']}');
  print('Count: ${await User.count()}');
  print('Exists: ${await User.exists()}');

  // 5. Chainable query — full operator set.
  print('\n=== Chainable query ===');
  final alices = await User.where('email', '%alice%', 'like').get();
  print('LIKE alice: ${alices.length}');
  final oneUser = await User.where('active', true).first();
  print('First active: ${oneUser?.toMap()['name']}');
  final inSet = await User.where('id', [alice.toMap()['id'], 999], 'in').get();
  print('IN: ${inSet.length}');
  final between = await User.query().whereBetween('id', 1, 100).get();
  print('BETWEEN 1..100: ${between.length}');

  // 6. Relationships.
  print('\n=== Relationships ===');
  final alicePosts = await alice.posts().get();
  print('alice.posts(): ${alicePosts.length}');
  final aliceProfile = await alice.profile().get();
  print('alice.profile(): ${aliceProfile?.toMap()['bio']}');
  final firstPost = alicePosts.first;
  final postOwner = await firstPost.user().get();
  print('firstPost.user(): ${postOwner?.toMap()['email']}');

  // 7. BelongsToMany — attach, sync.
  print('\n=== BelongsToMany ===');
  final adminRole = await Role.create({'name': 'admin'});
  final editorRole = await Role.create({'name': 'editor'});
  await alice.roles().attach(adminRole.toMap()['id']);
  await alice.roles().attach(editorRole.toMap()['id']);
  print('alice.roles(): ${(await alice.roles().get()).length}');
  await alice.roles().sync([adminRole.toMap()['id']]);
  print('alice.roles() after sync to [admin]: '
      '${(await alice.roles().get()).length}');

  // 8. Eager loading.
  print('\n=== Eager loading ===');
  final users = await User.query().with_(['posts', 'profile']).get();
  for (final u in users) {
    final loaded = u.isLoaded('posts') ? u.getLoaded('posts') : null;
    print('User ${u.toMap()['name']}: loaded $loaded');
  }

  // 9. Pagination.
  print('\n=== Pagination ===');
  for (var page = 1; page <= 2; page++) {
    final p = await User.query().paginate(page: page, perPage: 1);
    print('Page $page: data=${p.data.length} last=${p.lastPage} '
        'hasMore=${p.hasMore}');
  }

  // 10. Observer fired for `created`.
  print('\n=== Observer fired for `created` ===');
  await User.create({'email': 'dave@example.com', 'name': 'Dave'});
  // (Watch stdout for the "User created: id=..." line printed by the
  // observer's `created` hook on User.)

  // 11. Reactive stream.
  print('\n=== Reactive stream ===');
  final sub = User.watch().listen((list) {
    print('Stream emitted: ${list.length} users');
  });
  await User.create({'email': 'eve@example.com', 'name': 'Eve'});
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await sub.cancel();

  // 12. Transaction + raw SQL.
  print('\n=== Transaction ===');
  await Eloquent.transaction(() async {
    await User.create({'email': 'carol@example.com', 'name': 'Carol'});
    await Post.create({
      'user_id': bob.toMap()['id'],
      'title': 'Bob post',
    });
  });
  print('Total users after txn: ${await User.count()}');

  // 13. Schema rollback — drop the second migration's column, inspect,
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

  // 14. Cleanup.
  await Eloquent.dispose();
  print('\n=== Done ===');
}