/// Second migration — demonstrates changing a table after the initial
/// schema has shipped.
///
/// Adds a `phone` column to `users`. Use this as a template for adding /
/// renaming / dropping columns on existing tables.
library;

import 'package:eloquent_flutter/eloquent_flutter.dart';

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