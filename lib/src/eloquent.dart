/// Static facade for the package — bootstrap, transactions, raw SQL.
library;

import 'package:drift/drift.dart';

import 'exceptions.dart';

/// Static entry point for `eloquent_flutter`.
///
/// Call [init] once at app start with the user's `@DriftDatabase` instance.
/// All other entry points (`transaction`, `raw`, `rawSelect`, `db`) require
/// this to have been called first.
class Eloquent {
  Eloquent._();

  static GeneratedDatabase? _db;

  /// The underlying Drift database. Throws if [init] has not been called.
  static GeneratedDatabase get db {
    final instance = _db;
    if (instance == null) {
      throw InvalidArgumentException(
        'Eloquent.init() must be called before Eloquent.db. '
        'Call Eloquent.init(yourDriftDatabase) at app start.',
      );
    }
    return instance;
  }

  /// Wire up the package. Call once at app start with the user's
  /// `MyDatabase` (or any other [GeneratedDatabase] subclass produced by
  /// Drift codegen).
  static void init(GeneratedDatabase database) {
    _db = database;
  }

  /// Run [action] inside a Drift transaction. Nested transactions are
  /// supported via Drift's default behaviour.
  static Future<T> transaction<T>(Future<T> Function() action) {
    return db.transaction(action);
  }

  /// Execute a raw SQL statement that does not return rows.
  ///
  /// `customStatement` returns `Future<void>` (it does not report the
  /// affected-row count on SQLite), so this returns `void` too. For the
  /// affected-row count, use [db.customUpdate] or [db.customInsert]
  /// directly.
  static Future<void> raw(
    String sql, [
    List<Object?> variables = const [],
  ]) {
    return db.customStatement(sql, variables);
  }

  /// Execute a raw SQL `SELECT` and return the rows as a list of plain maps.
  ///
  /// Variables are bound as positional `?` placeholders. A `null` in
  /// [variables] becomes a SQL `NULL`; non-null values become a bound
  /// `Variable`. The SQL itself is passed straight to drift — never
  /// interpolate user input into it. Use `?` placeholders.
  ///
  /// For reactive streams, use [db.customSelect] directly with a
  /// `readsFrom: {table}` argument.
  static Future<List<Map<String, Object?>>> rawSelect(
    String sql, [
    List<Object?> variables = const [],
  ]) async {
    final rows = await db.customSelect(
      sql,
      variables: [for (final v in variables) Variable<Object>(v)],
    ).get();
    return rows.map((row) => row.data).toList(growable: false);
  }

  /// Drop the package's reference to the database. Mostly for tests.
  ///
  /// This does **not** close the database — the database is owned by the
  /// caller, who created it and is responsible for its lifecycle. Closing
  /// it here would surprise app code that holds a separate reference and
  /// expects to keep using the database after teardown.
  static Future<void> dispose() async {
    _db = null;
  }
}