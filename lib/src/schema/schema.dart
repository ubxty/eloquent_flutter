/// Schema facade — Laravel-style DDL helpers.
library;

import 'package:drift/drift.dart';

import '../eloquent.dart';
import 'blueprint.dart';

/// `Schema::create / drop / table / hasTable / hasColumn` — the
/// Eloquent-style DDL helpers. Pass a closure to receive a [Blueprint]
/// declaring columns and constraints.
class Schema {
  Schema._();

  /// Run `CREATE TABLE`.
  ///
  /// ```dart
  /// await Schema.create('users', (t) {
  ///   t.id();
  ///   t.string('email').unique_();
  ///   t.string('name');
  ///   t.boolean('active').default_(true);
  ///   t.timestamps();
  /// });
  /// ```
  static Future<void> create(
    String table,
    void Function(Blueprint t) columns,
  ) async {
    final bp = Blueprint(table);
    columns(bp);
    final sql = bp.toCreateSQL();
    // Split into individual statements so CREATE TABLE and any sibling
    // CREATE INDEX statements both run.
    for (final stmt in _splitStatements(sql)) {
      await Eloquent.db.customStatement(stmt);
    }
  }

  /// `DROP TABLE IF EXISTS`.
  static Future<void> drop(String table) async {
    await Eloquent.db.customStatement('DROP TABLE IF EXISTS $table');
  }

  /// `DROP TABLE` (no IF EXISTS). Errors if the table doesn't exist.
  static Future<void> dropUnlessExists(String table) async {
    await Eloquent.db.customStatement('DROP TABLE $table');
  }

  /// `ALTER TABLE`.
  ///
  /// Use the Blueprint's `addColumn`, `dropColumn`, `renameColumn`,
  /// `dropIndex` methods inside the closure to declare changes.
  static Future<void> table(
    String table,
    void Function(Blueprint t) changes,
  ) async {
    final bp = Blueprint(table);
    changes(bp);
    for (final stmt in bp.toAlterSQLList()) {
      await Eloquent.db.customStatement(stmt);
    }
  }

  /// True if `table` exists.
  static Future<bool> hasTable(String table) async {
    final r = await Eloquent.db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable<Object>(table)],
    ).getSingleOrNull();
    return r != null;
  }

  /// True if `table` has a column named `column`.
  static Future<bool> hasColumn(String table, String column) async {
    final r = await Eloquent.db.customSelect(
      'SELECT 1 FROM pragma_table_info(?) WHERE name = ? LIMIT 1',
      variables: [Variable<Object>(table), Variable<Object>(column)],
    ).getSingleOrNull();
    return r != null;
  }

  /// Names of columns in `table`.
  static Future<List<String>> getColumns(String table) async {
    final rows = await Eloquent.db.customSelect(
      'SELECT name FROM pragma_table_info(?) ORDER BY cid',
      variables: [Variable<Object>(table)],
    ).get();
    return [for (final r in rows) r.data['name'] as String];
  }

  /// Drop every application table in the database. Use with care.
  static Future<void> dropAll() async {
    final rows = await Eloquent.db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    for (final row in rows) {
      final name = row.data['name'] as String;
      if (name.startsWith('sqlite_')) continue;
      await Eloquent.db.customStatement('DROP TABLE IF EXISTS "$name"');
    }
  }

  /// Split a SQL string on `;` boundaries (ignoring semicolons inside
  /// single-quoted strings).
  static List<String> _splitStatements(String sql) {
    final out = <String>[];
    final buf = StringBuffer();
    var inSingle = false;
    for (var i = 0; i < sql.length; i++) {
      final ch = sql[i];
      if (ch == "'") {
        inSingle = !inSingle;
      } else if (ch == ';' && !inSingle) {
        final stmt = buf.toString().trim();
        if (stmt.isNotEmpty) out.add(stmt);
        buf.clear();
        continue;
      }
      buf.write(ch);
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) out.add(tail);
    return out;
  }
}
