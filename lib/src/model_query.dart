/// Per-model query helper that owns the table + creator.
library;

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import 'companion_builder.dart';
import 'eloquent.dart';
import 'exceptions.dart';
import 'internal/column_lookup.dart';
import 'model.dart';
import 'observers.dart';
import 'query_builder.dart';

/// One instance per model. Holds the [TableInfo] and the [creator]
/// function used to wrap raw rows into the model.
///
/// Declare one as a `static final` on each model class. Then add forwarding
/// statics for the methods you want to expose (a template is in the
/// README).
@immutable
class ModelQuery<T extends Model<T, D>, D extends Object> {
  ModelQuery({
    required this.table,
    required this.creator,
    this.primaryKey = 'id',
  });

  /// The Drift [TableInfo] for this model's table.
  final TableInfo<Table, D> table;

  /// Wraps a raw row into the model type [T].
  final T Function(D) creator;

  /// Name of the primary-key column.
  final String primaryKey;

  // ===== Terminal helpers =====

  /// All rows in this table.
  Future<List<T>> all() async {
    final rows = await Eloquent.db.select(table).get();
    return rows.map(creator).toList(growable: false);
  }

  /// Find a row by primary-key value, or null if not present.
  Future<T?> find(Object id) async {
    final stmt = Eloquent.db.select(table)
      ..where((_) => _pkColumn().equals(id))
      ..limit(1);
    final row = await stmt.getSingleOrNull();
    return row == null ? null : creator(row);
  }

  /// Like [find] but throws [ModelNotFoundException] when no row matches.
  Future<T> findOrFail(Object id) async {
    final found = await find(id);
    if (found == null) {
      throw ModelNotFoundException(
        modelName: T.toString(),
        id: id,
      );
    }
    return found;
  }

  /// First row ordered by [orderBy] (defaults to [primaryKey] ascending).
  /// Returns null if the table is empty.
  Future<T?> first({String? orderBy}) async {
    final stmt = Eloquent.db.select(table);
    final col = orderBy ?? primaryKey;
    stmt.orderBy([(_) => OrderingTerm(expression: _colByName(col))]);
    stmt.limit(1);
    final row = await stmt.getSingleOrNull();
    return row == null ? null : creator(row);
  }

  /// Total row count.
  Future<int> count() async {
    final row = await Eloquent.db
        .customSelect(
          'SELECT COUNT(*) AS c FROM '
          '${(table as TableInfo<Table, Object>).actualTableName}',
          readsFrom: {table},
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// True if the table has any row.
  Future<bool> exists() async {
    final c = await count();
    return c > 0;
  }

  /// Reactive variant — emits the current list on listen, then re-emits
  /// on any write that touches [table].
  Stream<List<T>> watch() {
    final stmt = Eloquent.db.select(table);
    return stmt.watch().map(
          (rows) => rows.map(creator).toList(growable: false),
        );
  }

  // ===== Writes =====

  /// Insert a new row and return the wrapped model instance.
  ///
  /// Fires the `created` observer on the freshly-inserted model. Note
  /// that `creating` cannot fire here because the insert has already
  /// happened — to get cancellation support, construct a model with a
  /// blank row and call `Model.save({...values})` instead.
  Future<T> create(Map<String, dynamic> values) async {
    final id = await Eloquent.db.into(table).insert(
          CompanionBuilder.fromMap(
            table: table,
            values: values,
            nullToAbsent: true,
          ),
        );
    // Re-fetch the row so defaulted columns (auto-increment, defaults) are
    // populated.
    final stmt = Eloquent.db.select(table)
      ..where((_) => _pkColumn().equals(id))
      ..limit(1);
    final row = await stmt.getSingle();
    final model = creator(row);
    dispatchVoid('created', model);
    return model;
  }

  /// Insert many rows in a single batch. Returns the number of rows
  /// inserted.
  Future<int> createMany(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return 0;
    final batch = Eloquent.db.batch((b) {
      b.insertAll(
        table,
        rows.map(
          (m) => CompanionBuilder.fromMap(
            table: table,
            values: m,
            nullToAbsent: true,
          ),
        ),
      );
    });
    await batch;
    return rows.length;
  }

  /// Mass update matching the predicate (`whereColumn == whereValue`).
  Future<int> update(
    Map<String, dynamic> values, {
    required String whereColumn,
    required Object whereValue,
  }) {
    final stmt = Eloquent.db.update(table)
      ..where((_) => _colByName(whereColumn).equals(whereValue));
    return stmt.write(
      CompanionBuilder.fromMap(
        table: table,
        values: values,
        nullToAbsent: true,
      ),
    );
  }

  /// Mass delete matching the predicate (`whereColumn == whereValue`).
  Future<int> delete({
    required String whereColumn,
    required Object whereValue,
  }) {
    final stmt = Eloquent.db.delete(table)
      ..where((_) => _colByName(whereColumn).equals(whereValue));
    return stmt.go();
  }

  // ===== Chainable =====

  /// Start a `where()` chain. Equivalent to `query().where(...)`.
  QueryBuilder<T, D> where(
    String column, [
    Object? value,
    String op = '=',
  ]) {
    return query().where(column, value, op);
  }

  /// Start an empty chain.
  QueryBuilder<T, D> query() => QueryBuilder<T, D>(
        table: table,
        creator: creator,
        primaryKey: primaryKey,
      );

  // ===== Find-or-create / upsert =====

  /// Search for the first row matching [attributes]; if none exists, insert
  /// a new row built from `attributes + creating` merged and return the
  /// wrapped model.
  ///
  /// Equivalent to Laravel's `Model::firstOrCreate()`. Fires the `created`
  /// observer when a new row is inserted (the insert path goes through
  /// [create]).
  Future<T> firstOrCreate(
    Map<String, dynamic> attributes, [
    Map<String, dynamic> creating = const {},
  ]) async {
    final found = await _findFirstByAttributes(attributes);
    if (found != null) return found;
    final merged = <String, dynamic>{...attributes, ...creating};
    return create(merged);
  }

  /// Like [firstOrCreate] but does not persist a missing row. The returned
  /// model is a wrapped instance — the underlying row is removed before
  /// return so no DB state remains, but the in-memory instance is populated
  /// so callers can mutate it and call [Model.save] to insert.
  Future<T> firstOrNew(
    Map<String, dynamic> attributes, [
    Map<String, dynamic> creating = const {},
  ]) async {
    final found = await _findFirstByAttributes(attributes);
    if (found != null) return found;
    final merged = <String, dynamic>{...attributes, ...creating};
    // Insert briefly to obtain a populated wrapped instance, then delete
    // so the row never persists. We bypass [create]'s observer dispatch
    // because the row is not actually saved — matches Laravel's semantics
    // where `firstOrNew` does not fire `created`. The rollback delete also
    // skips the model-level `deleting`/`deleted` observers so a custom
    // observer can't accidentally fail the call.
    final model = await _insertAndFetch(merged);
    final pkValue = model.$primaryKeyValue;
    if (pkValue != null) {
      final stmt = Eloquent.db.delete(table)
        ..where((_) => _pkColumn().equals(pkValue));
      await stmt.go();
    }
    return model;
  }

  /// Search for the first row matching [attributes]; if found, update it
  /// with [values] (relative to its current state). Otherwise insert a
  /// fresh row using `attributes + values` merged.
  Future<T> updateOrCreate(
    Map<String, dynamic> attributes,
    Map<String, dynamic> values,
  ) async {
    final found = await _findFirstByAttributes(attributes);
    if (found != null) {
      await found.update(values);
      return found;
    }
    final merged = <String, dynamic>{...attributes, ...values};
    return create(merged);
  }

  /// Upsert [rows] using Drift's `insertOnConflictUpdate`. [uniqueBy] is
  /// accepted for Laravel API parity — Drift's `insertOnConflictUpdate`
  /// always resolves conflicts on the table's primary key, so the
  /// `uniqueBy` columns are not used in the current implementation.
  Future<int> upsert(
    List<Map<String, dynamic>> rows, [
    List<String> uniqueBy = const [],
  ]) async {
    if (rows.isEmpty) return 0;
    for (final row in rows) {
      await Eloquent.db.into(table).insertOnConflictUpdate(
        CompanionBuilder.fromMap(
          table: table,
          values: row,
          nullToAbsent: true,
        ),
      );
    }
    return rows.length;
  }

  // ===== internal =====

  GeneratedColumn<Object> _pkColumn() => _colByName(primaryKey);

  GeneratedColumn<Object> _colByName(String name) =>
      resolveColumn(table as TableInfo<Table, Object>, name);

  /// Lookup helper: returns the first row matching the k=v predicates in
  /// [attributes]. ANDed together; empty map returns the first row of the
  /// table (matching Laravel's `firstOrCreate([])` semantics).
  Future<T?> _findFirstByAttributes(Map<String, dynamic> attributes) async {
    var q = query();
    for (final entry in attributes.entries) {
      q = q.where(entry.key, entry.value);
    }
    return q.first();
  }

  /// Insert a row from [values] and return the wrapped model without
  /// firing the `created` observer. Used by `firstOrNew` so we can roll
  /// the row back before returning.
  Future<T> _insertAndFetch(Map<String, dynamic> values) async {
    final id = await Eloquent.db.into(table).insert(
          CompanionBuilder.fromMap(
            table: table,
            values: values,
            nullToAbsent: true,
          ),
        );
    final stmt = Eloquent.db.select(table)
      ..where((_) => _pkColumn().equals(id))
      ..limit(1);
    final row = await stmt.getSingle();
    return creator(row);
  }
}