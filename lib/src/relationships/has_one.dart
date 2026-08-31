/// `hasOne` relationship.
library;

import 'package:drift/drift.dart';

import '../eloquent.dart';
import '../exceptions.dart';
import '../internal/column_lookup.dart';
import '../model.dart';
import 'relationship.dart';

/// One-to-one: a parent has zero or one child pointing at it.
///
///     HasOne<Profile> profile() => HasOne<Profile>(
///       local: this,
///       relatedTable: profilesTable,
///       foreignKey: 'user_id',
///       creator: Profile.new,
///     );
class HasOne<R extends Model<R, Object>, D extends Object>
    extends Relationship<R> {
  HasOne({
    required super.local,
    required super.relatedTable,
    required super.foreignKey,
    required this.creator,
    super.localKey,
  });

  /// Wraps a raw row into the model type R.
  final R Function(D) creator;

  /// Fetch the related row, or `null` if none exists.
  Future<R?> get() async {
    final value = localKeyValue;
    if (value == null) return null;
    final stmt = _buildStatement(value);
    stmt.limit(1);
    final row = await stmt.getSingleOrNull();
    return row == null ? null : creator(row);
  }

  /// Reactive variant.
  Stream<R?> watch() {
    final value = localKeyValue;
    if (value == null) {
      return Stream<R?>.value(null);
    }
    final stmt = _buildStatement(value);
    stmt.limit(1);
    return stmt.watchSingleOrNull().asyncMap((row) async {
      return row == null ? null : creator(row);
    });
  }

  /// Create the related row with the FK auto-set. Errors if one already
  /// exists (since hasOne is one-to-one).
  Future<R> createOrFail(Map<String, dynamic> values) async {
    final existing = await get();
    if (existing != null) {
      throw InvalidArgumentException(
        'hasOne.createOrFail called on $localKeyValue, '
        'but a related row already exists.',
      );
    }
    final merged = Map<String, dynamic>.from(values);
    merged[foreignKey] = localKeyValue;
    final id = await Eloquent.db.into(relatedTable).insert(
          _InsertableFromMap(
            table: relatedTable,
            values: merged,
          ),
        );
    final stmt = _buildStatement(localKeyValue!)
      ..where((t) => resolveColumn(relatedTable, 'id').equals(id))
      ..limit(1);
    final row = await stmt.getSingle();
    return creator(row);
  }

  /// Eager-load for many parents. Returns a map of
  /// `parent.$primaryKeyValue -> R?`.
  Future<Map<Object?, R?>> eagerLoadForParents(
    Iterable<Model> parents,
  ) async {
    final ids = <Object>[
      for (final p in parents) ...[
        if (p.toMap()[localKey] != null) p.toMap()[localKey] as Object,
      ],
    ];
    if (ids.isEmpty) {
      return {for (final p in parents) p.toMap()[localKey]: null};
    }
    final relatedTableName = relatedTable.actualTableName;
    final placeholder = List.filled(ids.length, '?').join(', ');
    final rows = await Eloquent.db
        .customSelect(
          'SELECT * FROM $relatedTableName WHERE $foreignKey IN ($placeholder)',
          variables: [
            for (final id in ids) Variable<Object>(id),
          ],
          readsFrom: {relatedTable},
        )
        .asyncMap<R>((row) async {
          final d = await relatedTable.map(row.data);
          return creator(d as D);
        })
        .get();

    final byParent = <Object?, R?>{
      for (final p in parents) p.toMap()[localKey]: null,
    };
    for (final r in rows) {
      byParent[r.toMap()[foreignKey]] = r;
    }
    return byParent;
  }

  SimpleSelectStatement<Table, D> _buildStatement(Object localPk) {
    final casted = relatedTable as TableInfo<Table, D>;
    final stmt = Eloquent.db.select(casted);
    stmt.where((_) => _fkColumn().equals(localPk));
    return stmt;
  }

  GeneratedColumn<Object> _fkColumn() =>
      resolveColumn(relatedTable, foreignKey);
}

class _InsertableFromMap<D> implements Insertable<D> {
  _InsertableFromMap({required this.table, required this.values});

  final TableInfo<Table, D> table;
  final Map<String, dynamic> values;

  @override
  Map<String, Expression<Object>> toColumns(bool nullToAbsent) {
    final result = <String, Expression<Object>>{};
    for (final entry in values.entries) {
      final c = resolveColumn(table as TableInfo<Table, Object>, entry.key);
      if (entry.value == null && nullToAbsent) continue;
      result[c.name] = Variable<Object>(entry.value as Object);
    }
    return result;
  }
}