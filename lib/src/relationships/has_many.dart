/// `hasMany` relationship.
library;

import 'package:drift/drift.dart';

import '../eloquent.dart';
import '../internal/column_lookup.dart';
import '../model.dart';
import 'relationship.dart';

/// One-to-many: a parent has zero or more children pointing at it.
///
/// Use it from a model:
///
///     HasMany<Post> posts() => HasMany<Post>(
///       local: this,
///       relatedTable: postsTable,
///       foreignKey: 'user_id',
///       creator: Post.new,
///     );
class HasMany<R extends Model<R, Object>, D extends Object>
    extends Relationship<R> {
  HasMany({
    required super.local,
    required super.relatedTable,
    required super.foreignKey,
    required this.creator,
    super.localKey,
  });

  /// Wraps a raw row into the model type R.
  final R Function(D) creator;

  /// Fetch all related rows.
  Future<List<R>> get() async {
    final value = localKeyValue;
    if (value == null) return <R>[];
    final stmt = _buildStatement(value);
    final rows = await stmt.get();
    return rows.map(creator).toList(growable: false);
  }

  /// Reactive variant — emits the current result on listen, then re-emits
  /// when the underlying table is written to.
  Stream<List<R>> watch() {
    final value = localKeyValue;
    if (value == null) return Stream<List<R>>.value(<R>[]);
    final stmt = _buildStatement(value);
    return stmt.watch().map(
          (rows) => rows.map(creator).toList(growable: false),
        );
  }

  /// Create a new related row with the foreign key automatically set to
  /// [local]'s primary-key value.
  Future<R> create(Map<String, dynamic> values) async {
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

  /// Used by [QueryBuilder] to batch-fetch children for many parents.
  ///
  /// Returns a map of `parent.$primaryKeyValue -> List<R>`.
  Future<Map<Object?, List<R>>> eagerLoadForParents(
    Iterable<Model> parents,
  ) async {
    final ids = <Object>[
      for (final p in parents) ...[
        if (p.toMap()[localKey] != null) p.toMap()[localKey] as Object,
      ],
    ];
    if (ids.isEmpty) {
      return {for (final p in parents) p.toMap()[localKey]: <R>[]};
    }
    final relatedTableName = relatedTable.actualTableName;
    final placeholder = List.filled(ids.length, '?').join(', ');
    final wrappedRows = await Eloquent.db
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

    final byParent = <Object?, List<R>>{
      for (final p in parents) p.toMap()[localKey]: <R>[],
    };
    for (final wrapped in wrappedRows) {
      final fkValue = wrapped.toMap()[foreignKey];
      (byParent[fkValue] ??= <R>[]).add(wrapped);
    }
    return byParent;
  }

  /// Build the typed select statement for fetching related rows.
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