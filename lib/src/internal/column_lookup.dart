/// Internal helper for resolving column names to [GeneratedColumn]s.
library;

import 'package:drift/drift.dart';

import '../exceptions.dart';

/// Resolve [name] on [table] to its [GeneratedColumn].
///
/// Throws [ColumnNotFoundException] with the list of valid columns if the
/// name is not present in `table.columnsByName`.
GeneratedColumn<Object> resolveColumn(
  TableInfo<Table, Object> table,
  String name,
) {
  final lower = name.toLowerCase();
  for (final column in table.columnsByName.values) {
    if (column.name.toLowerCase() == lower) return column;
  }
  throw ColumnNotFoundException(
    column: name,
    table: table.actualTableName,
    availableColumns:
        table.columnsByName.values.map((c) => c.name).toList()..sort(),
  );
}

/// Returns true if [table] has a column with the given [name].
bool hasColumn(TableInfo<Table, Object> table, String name) {
  final lower = name.toLowerCase();
  return table.columnsByName.values
      .any((c) => c.name.toLowerCase() == lower);
}