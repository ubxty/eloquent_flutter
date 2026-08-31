/// Base class for all models.
library;

import 'package:drift/drift.dart';

import 'casts/casts.dart';
import 'companion_builder.dart';
import 'eloquent.dart';
import 'exceptions.dart';
import 'internal/column_lookup.dart';
import 'observers.dart';
import 'relationships/relationship.dart';
import 'timestamps.dart';

/// Base class for every eloquent model.
///
/// Each subclass declares its own `D` (the drift row data type) and `T`
/// (itself, used for covariant return types).
abstract class Model<T extends Model<T, D>, D extends Object> {
  Model(this.$data) {
    _snapshotOriginal();
  }

  /// The current row data. Re-assign after a save/update to refresh.
  D $data;

  /// Pending attribute writes staged via [setAttribute]. Read by
  /// [getAttribute] / [toMapWithPending] and cleared by `_snapshotOriginal`.
  final Map<String, Object?> _pending = <String, Object?>{};

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

  /// Like [toMap] but with any pending [setAttribute] writes applied on
  /// top. Used internally by [save] and [update] to compute the
  /// persistence payload.
  Map<String, dynamic> toMapWithPending() {
    final base = toMap();
    if (_pending.isEmpty) return base;
    final merged = Map<String, dynamic>.from(base)..addAll(_pending);
    return merged;
  }

  /// Registry of per-column casts. Keys are column names, values are
  /// [CastType] constants (`'int'`, `'json'`, `'datetime'`, etc.).
  ///
  /// Override in your subclass:
  ///
  ///     @override
  ///     Map<String, String> get $casts => {
  ///       'age': 'int',
  ///       'is_admin': 'bool',
  ///       'meta': 'json',
  ///     };
  Map<String, String> get $casts => const {};

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

  // ===== Internal: "quiet" flag for individual saves / deletes =====

  /// When true, the in-flight [save] / [delete] call skips observer
  /// dispatch on this instance. Flipped by [saveQuietly] / [deleteQuietly]
  /// around the operation and reset in `finally`.
  bool _quiet = false;

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

  // ===== Attribute accessors with cast support =====

  /// Read a column by [key], applying the cast registered in [$casts].
  ///
  /// Pending writes from [setAttribute] shadow the underlying `$data`
  /// value. Returns null if the underlying value is null and no pending
  /// write exists. Throws [InvalidArgumentException] if [key] is not a
  /// column on this model's table.
  Object? getAttribute(String key) {
    _ensureColumnExists(key);
    if (_pending.containsKey(key)) {
      final pending = _pending[key];
      final typeName = $casts[key];
      return typeName == null ? pending : Casts.cast(pending, typeName);
    }
    final raw = toMap()[key];
    final typeName = $casts[key];
    if (typeName == null) return raw;
    return Casts.cast(raw, typeName);
  }

  /// Write [value] to column [key], applying the inverse cast registered
  /// in [$casts].
  ///
  /// The value is staged in a pending-writes map and does not mutate
  /// `$data` directly (Drift row classes are immutable). [save] /
  /// [update] / [toMapWithPending] apply the pending writes.
  /// Marks the column dirty and records the change for [wasChanged].
  ///
  /// Throws [InvalidArgumentException] if [key] is not a column on this
  /// model's table.
  void setAttribute(String key, Object? value) {
    _ensureColumnExists(key);
    final typeName = $casts[key];
    _pending[key] = typeName == null ? value : Casts.uncast(value, typeName);
    _dirty.add(key);
    _changes.add(key);
  }

  // ===== Dirty / original tracking =====

  final Map<String, Object?> _original = <String, Object?>{};
  final Set<String> _dirty = <String>{};
  final Set<String> _changes = <String>{};

  /// Snapshot of `$data` taken the last time `save()` / `update()` /
  /// `refresh()` (or model construction) completed successfully. Used by
  /// [getOriginal], [isDirty], [isClean], and [wasChanged].
  Map<String, Object?> get $original => Map.unmodifiable(_original);

  /// Columns whose current value differs from the snapshot in
  /// [$original]. Cleared by `save()` / `refresh()`.
  Set<String> get $dirty => Set.unmodifiable(_dirty);

  /// Columns that have been written via [setAttribute] since the last
  /// snapshot, regardless of whether the value actually changed.
  /// Cleared by `save()` / `refresh()`.
  Set<String> get $changes => Set.unmodifiable(_changes);

  /// True if [key] has been mutated since the last snapshot.
  ///
  /// When called without arguments, returns true if any column is dirty.
  bool isDirty([String? key]) {
    if (key == null) return _dirty.isNotEmpty;
    return _dirty.contains(key);
  }

  /// Inverse of [isDirty]. Returns true if [key] (or every column, when
  /// called without an argument) is clean.
  bool isClean([String? key]) => !isDirty(key);

  /// True if [key] (or any column) was written via [setAttribute] during
  /// the most recent lifecycle (between snapshots). Same semantics as
  /// Laravel's `$model->wasChanged`.
  bool wasChanged([String? key]) {
    if (key == null) return _changes.isNotEmpty;
    return _changes.contains(key);
  }

  /// The value of [key] at the last snapshot. Returns `null` for unknown
  /// columns or unset values.
  Object? getOriginal(String key) {
    if (!_original.containsKey(key)) {
      _ensureColumnExists(key);
    }
    return _original[key];
  }

  /// Take a fresh snapshot of the current `$data`, flush pending writes,
  /// and clear dirty / changes state. Called by `save()` / `update()` /
  /// `refresh()`.
  void _snapshotOriginal() {
    _original
      ..clear()
      ..addAll(toMap());
    _pending.clear();
    _dirty.clear();
    _changes.clear();
  }

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
      if (!_quiet && !dispatchCancelable('creating', this)) {
        cancelOperation('creating', this);
      }
      final values = _timestampValues(toMap(), isInsert: true);
      final id = await Eloquent.db.into($table).insert(
            CompanionBuilder.fromMap(
              table: $table,
              values: values,
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
      _snapshotOriginal();
      if (!_quiet) dispatchVoid('created', this);
      return wrapped;
    } else {
      if (!_quiet && !dispatchCancelable('updating', this)) {
        cancelOperation('updating', this);
      }
      final values = _timestampValues(toMap(), isInsert: false);
      final stmt = Eloquent.db.update($table)
        ..where((_) => resolveColumn($table as TableInfo<Table, Object>,
                $primaryKey)
            .equals(pkValue));
      await stmt.write(
        CompanionBuilder.fromMap(
          table: $table,
          values: values,
          nullToAbsent: true,
        ),
      );
      _snapshotOriginal();
      if (!_quiet) dispatchVoid('updated', this);
      return this as T;
    }
  }

  /// Build a values map that has had timestamp columns applied (when this
  /// model opts in via `WithTimestamps`). For non-timestamped models this
  /// is a straight copy of [base] so the call sites stay simple.
  Map<String, dynamic> _timestampValues(
    Map<String, dynamic> base, {
    required bool isInsert,
  }) {
    if (this is WithTimestamps) {
      return WithTimestamps.applyTo(
        Map<String, dynamic>.from(base),
        isInsert: isInsert,
        table: $table,
      );
    }
    return Map<String, dynamic>.from(base);
  }

  /// Update this model's row with [values] merged into the current data,
  /// then refresh from the database.
  Future<T> update(Map<String, dynamic> values) async {
    if (!dispatchCancelable('updating', this)) {
      cancelOperation('updating', this);
    }
    final merged = Map<String, dynamic>.from(toMapWithPending())
      ..addAll(values);
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
    if (!_quiet && !dispatchCancelable('deleting', this)) {
      cancelOperation('deleting', this);
    }
    final stmt = Eloquent.db.delete($table)
      ..where((_) => resolveColumn($table as TableInfo<Table, Object>,
              $primaryKey)
          .equals(pkValue));
    await stmt.go();
    if (!_quiet) dispatchVoid('deleted', this);
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
    _snapshotOriginal();
    return this as T;
  }

  // ===== Quiet variants =====

  /// Like [save] but no lifecycle observers fire. Useful for seeding and
  /// migrations where the per-row hook overhead is unwanted.
  Future<T> saveQuietly() async {
    _quiet = true;
    try {
      return await save();
    } finally {
      _quiet = false;
    }
  }

  /// Like [delete] but no lifecycle observers fire.
  Future<void> deleteQuietly() async {
    _quiet = true;
    try {
      await delete();
    } finally {
      _quiet = false;
    }
  }

  // ===== Global event suppression =====

  /// Run [action] with every lifecycle observer globally suppressed.
  ///
  /// Inside the callback, both per-instance quiet flags and the global
  /// muted switch combine: no `creating` / `created` / `updating` /
  /// `updated` / `deleting` / `deleted` hook will fire. The switch is
  /// restored in a `finally`, so a thrown error inside [action] still
  /// leaves subsequent operations firing normally.
  ///
  /// Example:
  ///
  ///     await Model.withoutEvents(() async {
  ///       for (final row in seedRows) {
  ///         await User.create(row);
  ///       }
  ///     });
  static Future<T> withoutEvents<T>(Future<T> Function() action) async {
    setEventsMuted(true);
    try {
      return await action();
    } finally {
      setEventsMuted(false);
    }
  }

  /// Helper used by [ModelQuery.create]: wraps a freshly-inserted row and
  /// takes a baseline snapshot.
  T wrap(D data) {
    final wrapped = $wrap(data);
    wrapped._snapshotOriginal();
    return wrapped;
  }

  // ===== internal: column introspection =====

  /// Throw [InvalidArgumentException] if [key] is not a column on the
  /// underlying Drift table.
  void _ensureColumnExists(String key) {
    final tableObj = $table as TableInfo<Table, Object>;
    if (!hasColumn(tableObj, key)) {
      throw InvalidArgumentException(
        'Column "$key" is not defined on table '
        '"${tableObj.actualTableName}".',
      );
    }
  }
}
