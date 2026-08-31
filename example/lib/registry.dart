/// Tiny registry that holds the AppDatabase instance and exposes its
/// table accessors as top-level constants.
///
/// Set once at app start via `AppRegistry.init(db)`. Models reference
/// these constants instead of carrying their own table handles.
library;

import 'package:drift/drift.dart';

import 'database.dart';

class AppRegistry {
  AppRegistry._();

  static AppDatabase? _db;

  /// Wire the database. Call this from `main()` after creating the
  /// `AppDatabase` instance.
  static void init(AppDatabase db) {
    _db = db;
  }

  static AppDatabase get _instance {
    final db = _db;
    if (db == null) {
      throw StateError(
        'AppRegistry.init(db) must be called before any model is used.',
      );
    }
    return db;
  }

  static TableInfo<Users, UserRow> get users => _instance.users;
  static TableInfo<Posts, PostRow> get posts => _instance.posts;
  static TableInfo<Profiles, ProfileRow> get profiles => _instance.profiles;
  static TableInfo<Roles, RoleRow> get roles => _instance.roles;
}
