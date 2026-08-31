/// Migrator — runs Laravel-style migrations with an `_migrations` ledger
/// and `up()` / `down()` semantics.
library;

import 'package:drift/drift.dart';

import '../eloquent.dart';
import 'schema.dart';

/// Abstract base class for one migration.
///
/// Migrations are registered with [Migrator.register] (typically in app
/// boot) and then run with [Migrator.migrate]. Each migration has a
/// unique [name] (default: `runtimeType.toString()`) used to track
/// whether it has been applied.
abstract class Migration {
  const Migration();

  /// Unique identifier for this migration.
  String get name => '$runtimeType';

  /// Schema changes to apply.
  Future<void> up();

  /// Inverse of [up]. Used by [Migrator.rollback].
  Future<void> down();
}

/// Run a registered list of [Migration]s.
class Migrator {
  Migrator();

  final List<Migration> _registered = <Migration>[];

  /// Register migrations in the order they should run. Earlier
  /// registrations run first.
  void register(List<Migration> migrations) {
    _registered.addAll(migrations);
  }

  /// Apply any migrations that have not been recorded yet.
  ///
  /// Creates the `_migrations` ledger table on first run.
  Future<void> migrate() async {
    await _ensureLedger();
    final applied = await _appliedNames();
    final batch = (await _lastBatch()) + 1;
    for (final m in _registered) {
      if (applied.contains(m.name)) continue;
      await Eloquent.transaction(() async {
        await m.up();
        await Eloquent.db.customInsert(
          'INSERT INTO _migrations (name, batch) VALUES (?, ?)',
          variables: [
            Variable<Object>(m.name),
            Variable<int>(batch),
          ],
        );
      });
    }
  }

  /// Roll back the most recent `steps` migrations (default 1).
  Future<void> rollback({int steps = 1}) async {
    await _ensureLedger();
    final rows = await Eloquent.db
        .customSelect(
          'SELECT name, batch FROM _migrations ORDER BY batch DESC, rowid DESC '
          'LIMIT ?',
          variables: [Variable<int>(steps)],
        )
        .get();
    // Reverse order so a batch's last-applied goes first.
    for (final row in rows.toList().reversed) {
      final name = row.data['name'] as String;
      final m = _registered.firstWhere(
        (m) => m.name == name,
        orElse: () => _UnknownMigration(name),
      );
      await Eloquent.transaction(() async {
        await m.down();
        await Eloquent.db.customStatement(
          'DELETE FROM _migrations WHERE name = ?',
          [name],
        );
      });
    }
  }

  /// Re-run every migration: rollback all then migrate all.
  Future<void> fresh() async {
    await Schema.dropAll();
    final applied = await _appliedNames();
    if (applied.isNotEmpty) {
      await Eloquent.db.customStatement('DELETE FROM _migrations');
    }
    await migrate();
  }

  Future<void> _ensureLedger() async {
    final exists = await Schema.hasTable('_migrations');
    if (exists) return;
    await Eloquent.db.customStatement('''
      CREATE TABLE _migrations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        batch INTEGER NOT NULL
      )
    ''');
  }

  Future<Set<String>> _appliedNames() async {
    if (!await Schema.hasTable('_migrations')) return <String>{};
    final rows = await Eloquent.db
        .customSelect('SELECT name FROM _migrations')
        .get();
    return {for (final r in rows) r.data['name'] as String};
  }

  Future<int> _lastBatch() async {
    if (!await Schema.hasTable('_migrations')) return 0;
    final r = await Eloquent.db
        .customSelect('SELECT MAX(batch) AS m FROM _migrations')
        .getSingleOrNull();
    if (r == null) return 0;
    final v = r.data['m'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}

class _UnknownMigration extends Migration {
  const _UnknownMigration(this.name);

  @override
  final String name;

  @override
  Future<void> up() async => throw StateError('Unknown migration $name');

  @override
  Future<void> down() async => throw StateError('Unknown migration $name');
}
