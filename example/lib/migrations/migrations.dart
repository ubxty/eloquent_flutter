/// Barrel export for migrations + helper to wire them up in main().
library;

import 'package:eloquent_flutter/eloquent_flutter.dart';

import 'm_2026_08_31_create_initial.dart';
import 'm_2026_09_01_add_user_phone.dart';
import 'm_2026_09_03_add_user_meta_softdeletes.dart';

/// All migrations in the order they should run.
///
/// Append new migrations at the bottom — the migrator only runs migrations
/// that aren't already recorded in the `_migrations` ledger.
List<Migration> allMigrations() => const <Migration>[
      CreateInitialTables(),
      AddUserPhone(),
      AddUserMetaAndSoftDeletes(),
    ];

/// Run pending migrations against the database currently registered with
/// `Eloquent.init`.
Future<void> migrate() async {
  final migrator = Migrator()..register(allMigrations());
  await migrator.migrate();
}