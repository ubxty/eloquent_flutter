/// Initial migration — creates all five tables and the column constraints.
///
/// Demonstrates the Eloquent-style DDL: `Schema.create('table', (t) { ... })`
/// with the Blueprint DSL (`t.id()`, `t.string()`, `t.foreign()`,
/// `t.compositePrimary()`, etc.).
library;

import 'package:eloquent_flutter/eloquent_flutter.dart';

class CreateInitialTables extends Migration {
  const CreateInitialTables();

  @override
  Future<void> up() async {
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

    await Schema.create('profiles', (t) {
      t.id();
      t.integer('user_id');
      t.text('bio').default_('');
      t.foreign('user_id', references: 'users.id', onDelete: 'CASCADE');
    });

    await Schema.create('roles', (t) {
      t.id();
      t.string('name').unique_();
    });

    await Schema.create('role_users', (t) {
      t.integer('user_id');
      t.integer('role_id');
      t.compositePrimary(['user_id', 'role_id']);
    });
  }

  @override
  Future<void> down() async {
    await Schema.drop('role_users');
    await Schema.drop('roles');
    await Schema.drop('profiles');
    await Schema.drop('posts');
    await Schema.drop('users');
  }
}