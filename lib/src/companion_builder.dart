/// Builds Drift [Insertable]s from plain Maps.
library;

import 'package:drift/drift.dart';

import 'exceptions.dart';
import 'internal/column_lookup.dart';

/// Converts a `Map<String, dynamic>` into a Drift [Insertable] that
/// [Into] statements can consume.
///
/// Drift's column metadata (read from [TableInfo.columnsByName]) does the
/// type coercion — we just wrap each value in a [Variable].
class CompanionBuilder {
  CompanionBuilder._();

  /// Build an [Insertable] from [values], using [table] as the schema
  /// reference.
  ///
  /// If [nullToAbsent] is true (the default), `null` values in [values] are
  /// omitted from the resulting columns map. This matches Drift's `Value`
  /// semantics where `Value(null)` means "set to NULL" and absent means
  /// "leave unchanged". Use [nullToAbsent]: false to explicitly write NULLs.
  ///
  /// Throws [ColumnNotFoundException] if [values] contains a key not
  /// present in `table.columnsByName`.
  static Insertable<D> fromMap<D>({
    required TableInfo<Table, D> table,
    required Map<String, dynamic> values,
    bool nullToAbsent = true,
  }) {
    return _MapInsertable<D>(
      table: table,
      values: values,
      nullToAbsent: nullToAbsent,
    );
  }

  /// Build an [Insertable] from a single column/value pair.
  ///
  /// Useful for update statements that need to set a single column.
  static Insertable<D> singleColumn<D, V>({
    required TableInfo<Table, D> table,
    required String column,
    required V value,
  }) {
    return fromMap(table: table, values: {column: value});
  }
}

class _MapInsertable<D> implements Insertable<D> {
  _MapInsertable({
    required TableInfo<Table, D> table,
    required Map<String, dynamic> values,
    required this.nullToAbsent,
  })  : _table = table,
        _values = Map.unmodifiable(values);

  final TableInfo<Table, D> _table;
  final Map<String, dynamic> _values;
  final bool nullToAbsent;

  @override
  Map<String, Expression<Object>> toColumns(bool nullToAbsent) {
    final result = <String, Expression<Object>>{};
    for (final entry in _values.entries) {
      final column = _lookupColumn(entry.key);
      final rawValue = entry.value;
      // Skip nulls only when both drift's caller AND the instance asked
      // for nullToAbsent semantics — matches Laravel's "explicit null
      // to set, otherwise absent" convention and lets users force a
      // NULL write on update by passing `nullToAbsent: false` to
      // [CompanionBuilder.fromMap].
      if (rawValue == null && nullToAbsent && this.nullToAbsent) {
        continue;
      }
      // Skip auto-incremented primary keys when the user hasn't supplied
      // a real value (0 is the placeholder drift writes for a freshly
      // constructed row). Without this guard the second insert would
      // collide on `id = 0` because SQLite's `INTEGER PRIMARY KEY
      // AUTOINCREMENT` treats 0 as a literal rowid, not a request for
      // the next available id. Users who actually want to import a
      // specific id can still set one — they'd just need to pass a
      // non-zero value.
      if (column.hasAutoIncrement &&
          (rawValue == null || rawValue == 0)) {
        continue;
      }
      // Drift's `Variable<Object>` rejects `null` (it expects an
      // `Object`), so emit a literal `NULL` expression when the value
      // is null. The `Expression<Object>` type is satisfied via the
      // null-literal subclass below.
      result[column.name] = rawValue == null
          ? const _NullLiteralExpression()
          : Variable<Object>(rawValue as Object);
    }
    return result;
  }

  GeneratedColumn<Object> _lookupColumn(String name) {
    return resolveColumn(_table as TableInfo<Table, Object>, name);
  }
}

/// Writes the SQL literal `NULL`. Used by [CompanionBuilder] when the
/// caller explicitly passes a null value (and bypassed the
/// `nullToAbsent` filter) so the resulting column expression is still
/// a valid `Expression<Object>` instead of `Variable<Object>` (which
/// refuses nulls).
class _NullLiteralExpression extends Expression<Object> {
  const _NullLiteralExpression();

  @override
  Precedence get precedence => Precedence.primary;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('NULL');
  }

  @override
  int get hashCode => 'NULL'.hashCode;

  @override
  bool operator ==(Object other) => other is _NullLiteralExpression;
}
