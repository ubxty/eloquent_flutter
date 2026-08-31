/// `belongsTo` relationship.
library;

import 'package:drift/drift.dart';

import '../eloquent.dart';
import '../internal/column_lookup.dart';
import '../model.dart';
import 'relationship.dart';

/// Inverse of hasOne/hasMany: the foreign key lives on this model's table.
///
///     BelongsTo<User> user() => BelongsTo<User>(
///       local: this,
///       relatedTable: usersTable,
///       foreignKey: 'user_id',
///       creator: User.new,
///     );
class BelongsTo<R extends Model<R, Object>, D extends Object>
    extends Relationship<R> {
  BelongsTo({
    required super.local,
    required super.relatedTable,
    required super.foreignKey,
    required this.creator,
    super.localKey,
  });

  /// Wraps a raw row into the model type R.
  final R Function(D) creator;

  /// Fetch the related row by matching `relatedTable.id = local.foreignKey`.
  Future<R?> get() async {
    final fkValue = _fkValue();
    if (fkValue == null) return null;
    final stmt = _buildStatement(fkValue);
    stmt.limit(1);
    final row = await stmt.getSingleOrNull();
    return row == null ? null : creator(row);
  }

  /// Reactive variant.
  Stream<R?> watch() {
    final fkValue = _fkValue();
    if (fkValue == null) {
      return Stream<R?>.value(null);
    }
    final stmt = _buildStatement(fkValue);
    stmt.limit(1);
    return stmt.watchSingleOrNull().asyncMap((row) async {
      return row == null ? null : creator(row);
    });
  }

  /// Eager-load for many parents. Returns a map of
  /// `childRow.foreignKey -> R?`.
  Future<Map<Object?, R?>> eagerLoadForParents(
    Iterable<Model> parents,
  ) async {
    final ids = <Object>[
      for (final p in parents) ...[
        if (p.toMap()[foreignKey] != null) p.toMap()[foreignKey] as Object,
      ],
    ];
    if (ids.isEmpty) {
      return {for (final p in parents) p.toMap()[foreignKey]: null};
    }
    final relatedTableName = relatedTable.actualTableName;
    final placeholder = List.filled(ids.length, '?').join(', ');
    final pkName = resolveColumn(relatedTable, localKey).name;
    final rows = await Eloquent.db
        .customSelect(
          'SELECT * FROM $relatedTableName WHERE '
          '$pkName IN ($placeholder)',
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
      for (final p in parents) p.toMap()[foreignKey]: null,
    };
    for (final r in rows) {
      final id = r.toMap()[localKey];
      byParent[id] = r;
    }
    return byParent;
  }

  Object? _fkValue() => local.toMap()[foreignKey];

  SimpleSelectStatement<Table, D> _buildStatement(Object fkValue) {
    final casted = relatedTable as TableInfo<Table, D>;
    final stmt = Eloquent.db.select(casted);
    final pk = resolveColumn(relatedTable, localKey);
    stmt.where((_) => pk.equals(fkValue));
    return stmt;
  }
}