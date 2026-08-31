/// Auto-managed `created_at` / `updated_at` mixin.
library;

import 'package:drift/drift.dart';

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

  /// Apply timestamps to [values] directly using [table] as the schema
  /// reference. The same logic as [applyTimestamps] but callable from places
  /// (e.g. `Model.save`) that don't go through the mixin instance methods.
  ///
  /// Mutates and returns [values]. No-ops if the table is missing one or
  /// both timestamp columns.
  static Map<String, dynamic> applyTo(
    Map<String, dynamic> values, {
    required bool isInsert,
    required TableInfo<Table, Object> table,
  }) {
    if (hasColumn(table, 'updated_at')) {
      values['updated_at'] = DateTime.now();
    }
    if (isInsert &&
        values['created_at'] == null &&
        hasColumn(table, 'created_at')) {
      values['created_at'] = DateTime.now();
    }
    return values;
  }

  /// Apply timestamps to [map] before persistence. Mutates in place.
  void applyTimestamps(Map<String, dynamic> map, {required bool isInsert}) {
    WithTimestamps.applyTo(
      map,
      isInsert: isInsert,
      table: model.$table,
    );
  }
}
