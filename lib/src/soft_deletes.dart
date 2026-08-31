/// Laravel-style soft-delete mixin for eloquent models.
library;

import 'package:drift/drift.dart';

import 'companion_builder.dart';
import 'eloquent.dart';
import 'exceptions.dart';
import 'internal/column_lookup.dart';
import 'model.dart';
import 'observers.dart';

/// Mixin that implements Laravel's `SoftDeletes` trait on top of Drift.
///
/// Apply to any model that has a `deleted_at` column on its table:
///
/// ```dart
/// class User extends Model<User, UserRow>
///     with SoftDeletes<User, UserRow> {
///   // ...
/// }
/// ```
///
/// When the mixin is present:
///
/// - [Model.delete] sets `deleted_at = now()` instead of removing the row.
/// - [forceDelete] removes the row from the database.
/// - [restore] clears `deleted_at`.
/// - [QueryBuilder] / [ModelQuery] automatically exclude soft-deleted rows
///   unless `withTrashed()` or `onlyTrashed()` is used.
mixin SoftDeletes<T extends Model<T, D>, D extends Object> on Model<T, D> {
  /// Override to use a different column name for the soft-delete timestamp.
  String get $deletedAtColumn => 'deleted_at';

  /// True when a [forceDelete] call is in progress. Internal — used by the
  /// overridden [delete] to dispatch to either the soft- or hard-delete path.
  bool get $forceDeleting => _forceDeleting;
  bool _forceDeleting = false;

  /// True if this model's row is currently soft-deleted.
  bool get trashed {
    final map = toMap();
    return map[$deletedAtColumn] != null;
  }

  /// True if the soft-delete operations should skip observer events.
  ///
  /// Reads through `dynamic` so the mixin is forward-compatible with any
  /// `quiet` getter a model may expose later (Laravel convention). When no
  /// `quiet` getter is present, this returns `false` and observers always
  /// fire.
  bool get $softDeletesQuiet {
    try {
      final dyn = this as dynamic;
      final v = dyn.quiet;
      return v is bool ? v : false;
    } catch (_) {
      return false;
    }
  }

  /// Soft-delete this model: sets `deleted_at` to `DateTime.now()`.
  ///
  /// Fires `deleting` (cancelable) then `deleted` observer events, unless
  /// `$softDeletesQuiet` is true. When [forceDelete] is in progress, this
  /// delegates to the base class's hard-delete implementation instead.
  @override
  Future<void> delete() async {
    if ($forceDeleting) {
      // Hard-delete path — defer to the base Model.delete().
      await super.delete();
      return;
    }
    if (!$softDeletesQuiet) {
      if (!dispatchCancelable('deleting', this as Model)) {
        cancelOperation('deleting', this as Model);
      }
    }
    final pkValue = $primaryKeyValue;
    if (pkValue == null) {
      throw InvalidArgumentException(
        'Cannot soft-delete() a model with no primary-key value.',
      );
    }
    await _writeDeletedAt(DateTime.now());
    await refresh();
    if (!$softDeletesQuiet) {
      dispatchVoid('deleted', this as Model);
    }
  }

  /// Permanently delete this model: bypasses the soft-delete shim.
  ///
  /// Fires `forceDeleting` (cancelable) then `forceDeleted` observer
  /// events, unless `$softDeletesQuiet` is true.
  Future<void> forceDelete() async {
    _forceDeleting = true;
    try {
      if (!$softDeletesQuiet) {
        if (!dispatchCancelable('forceDeleting', this as Model)) {
          cancelOperation('forceDeleting', this as Model);
        }
      }
      final pkValue = $primaryKeyValue;
      if (pkValue == null) {
        throw InvalidArgumentException(
          'Cannot forceDelete() a model with no primary-key value.',
        );
      }
      final stmt = Eloquent.db.delete($table)
        ..where((_) => resolveColumn(
              $table as TableInfo<Table, Object>,
              $primaryKey,
            ).equals(pkValue));
      await stmt.go();
      if (!$softDeletesQuiet) {
        dispatchVoid('forceDeleted', this as Model);
      }
    } finally {
      _forceDeleting = false;
    }
  }

  /// Restore a soft-deleted model: clears `deleted_at`.
  ///
  /// Fires `restoring` (cancelable) then `restored` observer events,
  /// unless `$softDeletesQuiet` is true.
  Future<T> restore() async {
    if (!$softDeletesQuiet) {
      if (!dispatchCancelable('restoring', this as Model)) {
        cancelOperation('restoring', this as Model);
      }
    }
    final pkValue = $primaryKeyValue;
    if (pkValue == null) {
      throw InvalidArgumentException(
        'Cannot restore() a model with no primary-key value.',
      );
    }
    await _writeDeletedAt(null);
    await refresh();
    if (!$softDeletesQuiet) {
      dispatchVoid('restored', this as Model);
    }
    return this as T;
  }

  Future<void> _writeDeletedAt(DateTime? value) async {
    final pkValue = $primaryKeyValue;
    if (pkValue == null) {
      throw InvalidArgumentException(
        'Cannot set ${$deletedAtColumn} on a model with no primary-key value.',
      );
    }
    final stmt = Eloquent.db.update($table)
      ..where((_) => resolveColumn(
            $table as TableInfo<Table, Object>,
            $primaryKey,
          ).equals(pkValue));
    await stmt.write(
      CompanionBuilder.fromMap(
        table: $table,
        values: {$deletedAtColumn: value},
        nullToAbsent: false,
      ),
    );
  }
}
