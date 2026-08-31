/// Auto-managed `created_at` / `updated_at` mixin.
library;

import 'internal/column_lookup.dart';
import 'model.dart';

/// Opt-in mixin that auto-manages `created_at` and `updated_at` columns.
///
/// Apply to models that have those columns on their Drift table.
///
/// On `save()` (insert path):
///   - `created_at` is set to `DateTime.now()` if currently null
///   - `updated_at` is set to `DateTime.now()`
///
/// On `update(map)`:
///   - `updated_at` is set to `DateTime.now()`
///
/// If the table does not have one or both columns, the mixin no-ops
/// gracefully.
mixin WithTimestamps {
  /// The model this mixin is applied to.
  Model get model;

  /// Map representation of the current row (used to read/write columns).
  Map<String, dynamic> get modelMap;

  /// Re-wrap the row data after the timestamp mixin mutates the map.
  /// Implementations typically re-fetch from the database.
  Future<void> persistTimestamps();

  bool get _hasCreatedAt => _safeHasColumn('created_at');
  bool get _hasUpdatedAt => _safeHasColumn('updated_at');

  bool _safeHasColumn(String name) {
    try {
      // TableInfo is invariant in D, so TableInfo<Table, D> is not a subtype
      // of TableInfo<Table, Object>. Coerce through dynamic.
      return hasColumn(model.$table, name);
    } catch (_) {
      return false;
    }
  }

  /// Apply timestamps to [map] before persistence. Mutates in place.
  void applyTimestamps(Map<String, dynamic> map, {required bool isInsert}) {
    if (isInsert && map['created_at'] == null && _hasCreatedAt) {
      map['created_at'] = DateTime.now();
    }
    if (_hasUpdatedAt) {
      map['updated_at'] = DateTime.now();
    }
  }
}