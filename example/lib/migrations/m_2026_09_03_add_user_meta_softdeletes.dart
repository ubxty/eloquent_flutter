/// Third migration — adds a `meta` JSON column and `deleted_at` to `users`.
///
/// Demonstrates ALTER TABLE after the initial schema shipped. The matching
/// `User` model uses `with SoftDeletes<...>`, `with WithTimestamps`, and a
/// `$casts` entry on `meta` to round-trip JSON through the wrapper.
library;

import 'package:eloquent_flutter/eloquent_flutter.dart';

class AddUserMetaAndSoftDeletes extends Migration {
  const AddUserMetaAndSoftDeletes();

  @override
  Future<void> up() async {
    await Schema.table('users', (t) {
      t.addColumn('text', 'meta').nullable_();
      t.addColumn('dateTime', 'deleted_at').nullable_();
    });
  }

  @override
  Future<void> down() async {
    await Schema.table('users', (t) {
      t.dropColumn('deleted_at');
      t.dropColumn('meta');
    });
  }
}
