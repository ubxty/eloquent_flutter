/// Base class for all models.
library;

import 'package:drift/drift.dart';

import 'companion_builder.dart';
import 'eloquent.dart';
import 'exceptions.dart';
import 'internal/column_lookup.dart';
import 'observers.dart';
import 'relationships/relationship.dart';

/// Base class for every eloquent model.
///
/// Each subclass declares its own `D` (the drift row data type) and `T`
/// (itself, used for covariant return types).
abstract class Model<T extends Model<T, D>, D extends Object> {
  Model(this.$data);

  /// The current row data. Re-assign after a save/update to refresh.
  D $data;

  // ===== Abstract / overridable =====

  /// The Drift [TableInfo] for this model's table.
  TableInfo<Table, D> get $table;

  /// Wrap a row data instance into this model.
  T $wrap(D data);

  /// The primary-key column name. Override if your table uses a different
  /// column name (e.g. `'uuid'`).
  String get $primaryKey => 'id';

  /// Convert the current row data to a plain Dart map.
  ///
  /// The keys must match the column names in `$table.columnsByName`.
  Map<String, dynamic> toMap();

  /// Registry of relationships, keyed by the string used in `with_(...)`.
  ///
  /// Override in your subclass:
  ///
  ///     @override
  ///     Map<String, Relationship<dynamic>> get $relations => {
  ///       'posts': posts(),
  ///       'profile': profile(),
  ///     };
  Map<String, Relationship<dynamic>> get $relations => const {};

  /// Registry of lifecycle observer callbacks.
  ObserverSet get $observers => const ObserverSet();

  // ===== Internal: eager-loaded relations cache =====

  final Map<String, Object?> _loadedRelations = <String, Object?>{};

  /// Returns the eagerly-loaded relation value (set by `with_(...)`), or
  /// null if it has not been loaded yet.
  Object? getLoaded(String name) => _loadedRelations[name];

  /// Returns true if [name] was loaded by an earlier `with_(...)` call.
  bool isLoaded(String name) => _loadedRelations.containsKey(name);

  /// Internal — called by [QueryBuilder.get] / [QueryBuilder.first] /
  /// [QueryBuilder.find] after the parent rows have been eager-loaded.
  void setLoaded(String name, Object? value) {
    _loadedRelations[name] = value;
  }

  // ===== Convenience =====

  /// The value of the primary-key column for this row.
  Object? get $primaryKeyValue => toMap()[$primaryKey];

  // ===== Instance CRUD =====

  /// Save this model. Inserts if there is no primary-key value, otherwise
  /// updates the existing row.
  ///
  /// Fires `creating`/`created` (insert path) or `updating`/`updated`
  /// (update path) observers. Returning `false` from a cancelable hook
  /// aborts the operation and throws [OperationCancelledException].
  Future<T> save() async {
    final pkValue = $primaryKeyValue;
    if (pkValue == null) {
      if (!dispatchCancelable('creating', this)) {
        cancelOperation('creating', this);
      }
      final id = await Eloquent.db.into($table).insert(
            CompanionBuilder.fromMap(
              table: $table,
              values: toMap(),
              nullToAbsent: true,
            ),
          );
      // Re-fetch to populate auto-incremented / defaulted columns.
      final stmt = Eloquent.db.select($table)
        ..where((_) => resolveColumn($table as TableInfo<Table, Object>,
                $primaryKey)
            .equals(id))
        ..limit(1);
      final fresh = await stmt.getSingle();
      final wrapped = $wrap(fresh);
      // Mutate in place so callers holding the original reference see
      // the new state.
      $data = wrapped.$data;
      dispatchVoid('created', this);
      return wrapped;
    } else {
      if (!dispatchCancelable('updating', this)) {
        cancelOperation('updating', this);
      }
      final stmt = Eloquent.db.update($table)
        ..where((_) => resolveColumn($table as TableInfo<Table, Object>,
                $primaryKey)
            .equals(pkValue));
      await stmt.write(
        CompanionBuilder.fromMap(
          table: $table,
          values: toMap(),
          nullToAbsent: true,
        ),
      );
      dispatchVoid('updated', this);
      return this as T;
    }
  }

  /// Update this model's row with [values] merged into the current data,
  /// then refresh from the database.
  Future<T> update(Map<String, dynamic> values) async {
    if (!dispatchCancelable('updating', this)) {
      cancelOperation('updating', this);
    }
    final merged = Map<String, dynamic>.from(toMap())..addAll(values);
    // Strip the PK so it doesn't get overwritten.
    merged.remove($primaryKey);
    final pkValue = $primaryKeyValue;
    if (pkValue == null) {
      throw InvalidArgumentException(
        'Cannot update() a model with no primary-key value. '
        'Call save() first to insert the row.',
      );
    }
    final stmt = Eloquent.db.update($table)
      ..where((_) => resolveColumn($table as TableInfo<Table, Object>,
              $primaryKey)
          .equals(pkValue));
    await stmt.write(
      CompanionBuilder.fromMap(
        table: $table,
        values: merged,
        nullToAbsent: true,
      ),
    );
    await refresh();
    dispatchVoid('updated', this);
    return this as T;
  }

  /// Delete this model's row from the database.
  Future<void> delete() async {
    final pkValue = $primaryKeyValue;
    if (pkValue == null) {
      throw InvalidArgumentException(
        'Cannot delete() a model with no primary-key value.',
      );
    }
    if (!dispatchCancelable('deleting', this)) {
      cancelOperation('deleting', this);
    }
    final stmt = Eloquent.db.delete($table)
      ..where((_) => resolveColumn($table as TableInfo<Table, Object>,
              $primaryKey)
          .equals(pkValue));
    await stmt.go();
    dispatchVoid('deleted', this);
  }

  /// Re-fetch this model's row from the database. Mutates `$data` in place.
  Future<T> refresh() async {
    final pkValue = $primaryKeyValue;
    if (pkValue == null) {
      throw InvalidArgumentException(
        'Cannot refresh() a model with no primary-key value.',
      );
    }
    final stmt = Eloquent.db.select($table)
      ..where((_) => resolveColumn($table as TableInfo<Table, Object>,
              $primaryKey)
          .equals(pkValue))
      ..limit(1);
    final row = await stmt.getSingle();
    $data = row;
    return this as T;
  }

  /// Helper used by [ModelQuery.create]: wraps a freshly-inserted row.
  T wrap(D data) => $wrap(data);
}