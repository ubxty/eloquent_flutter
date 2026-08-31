/// `belongsToMany` relationship with pivot table.
library;

import 'package:drift/drift.dart';

import '../eloquent.dart';
import '../model.dart';
import 'relationship.dart';

/// Many-to-many: a parent has zero or more children via a pivot table.
///
/// The pivot table holds two foreign keys:
///   - [foreignPivotKey] (default: `<local simpleName>_id`) — points at [local].
///   - [relatedPivotKey] (default: `<related singular>_id`) — points at the related row.
class BelongsToMany<R extends Model<R, Object>, D extends Object>
    extends Relationship<R> {
  // ignore: use_super_parameters
  BelongsToMany({
    required Model local,
    required TableInfo<Table, Object> relatedTable,
    required this.creator,
    required this.pivotTable,
    String? foreignPivotKey,
    String? relatedPivotKey,
    String localKey = 'id',
    String? relatedKey,
  })  : foreignPivotKey = foreignPivotKey ?? defaultForeignPivotKey(local),
        relatedPivotKey =
            relatedPivotKey ?? defaultRelatedPivotKey(relatedTable),
        relatedKey = relatedKey ?? 'id',
        super(
          local: local,
          relatedTable: relatedTable,
          foreignKey: foreignPivotKey ?? defaultForeignPivotKey(local),
          localKey: localKey,
        );

  /// Wraps a raw row into the model type R.
  final R Function(D) creator;

  /// Name of the pivot table (e.g. `'role_user'`).
  final String pivotTable;

  /// FK column on the pivot table pointing at [local].
  final String foreignPivotKey;

  /// FK column on the pivot table pointing at the related row.
  final String relatedPivotKey;

  /// PK column on the related table. Defaults to `'id'`.
  final String relatedKey;

  /// Fetch all rows currently attached to [local].
  Future<List<R>> get() async {
    final value = localKeyValue;
    if (value == null) return <R>[];
    final stmt = _buildInner(value);
    final rows = await stmt.get();
    return rows.map(creator).toList(growable: false);
  }

  /// Reactive variant.
  Stream<List<R>> watch() {
    final value = localKeyValue;
    if (value == null) return Stream<List<R>>.value(<R>[]);
    final stmt = _buildInner(value);
    return stmt.watch().map(
          (rows) => rows.map(creator).toList(growable: false),
        );
  }

  /// Insert a pivot row linking [local] to a related row.
  Future<void> attach(Object relatedId) async {
    await Eloquent.db.customStatement(
      'INSERT OR IGNORE INTO $pivotTable '
      '($foreignPivotKey, $relatedPivotKey) VALUES (?, ?)',
      [localKeyValue!, relatedId],
    );
  }

  /// Remove the pivot row linking [local] to the given related row.
  /// Returns the number of pivot rows deleted.
  Future<int> detach(Object relatedId) async {
    return Eloquent.db.customUpdate(
      'DELETE FROM $pivotTable WHERE $foreignPivotKey = ? AND $relatedPivotKey = ?',
      variables: [
        Variable<Object>(localKeyValue!),
        Variable<Object>(relatedId),
      ],
      updates: {relatedTable},
    );
  }

  /// Replace the set of attached related rows with [relatedIds].
  Future<void> sync(List<Object> relatedIds) async {
    final current = await get();
    final currentIds =
        current.map((r) => r.toMap()[relatedKey] as Object).toSet();
    final desired = relatedIds.toSet();
    for (final id in currentIds.difference(desired)) {
      await detach(id);
    }
    for (final id in desired.difference(currentIds)) {
      await attach(id);
    }
  }

  /// Eager-load related rows for many parents.
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

    final placeholder = List.filled(ids.length, '?').join(', ');
    final relatedTableName = relatedTable.actualTableName;

    final relatedRows = await Eloquent.db
        .customSelect(
          'SELECT r.* FROM $relatedTableName r '
          'INNER JOIN $pivotTable p ON p.$relatedPivotKey = r.$relatedKey '
          'WHERE p.$foreignPivotKey IN ($placeholder)',
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

    final pivotRows = await Eloquent.db.customSelect(
      'SELECT $foreignPivotKey AS parent_id, $relatedPivotKey AS related_id '
      'FROM $pivotTable WHERE $foreignPivotKey IN ($placeholder)',
      variables: [
        for (final id in ids) Variable<Object>(id),
      ],
    ).get();

    final relatedById = <Object?, R>{};
    for (final r in relatedRows) {
      relatedById[r.toMap()[relatedKey]] = r;
    }

    final byParent = <Object?, List<R>>{
      for (final p in parents) p.toMap()[localKey]: <R>[],
    };
    for (final p in pivotRows) {
      final parentId = p.data['parent_id'];
      final relatedId = p.data['related_id'];
      final wrapped = relatedById[relatedId];
      if (wrapped != null) {
        (byParent[parentId] ??= <R>[]).add(wrapped);
      }
    }
    return byParent;
  }

  // ---- internal ----

  Selectable<D> _buildInner(Object localPk) {
    final relatedTableName = relatedTable.actualTableName;
    return Eloquent.db.customSelect(
      'SELECT r.* FROM $relatedTableName r '
      'INNER JOIN $pivotTable p ON p.$relatedPivotKey = r.$relatedKey '
      'WHERE p.$foreignPivotKey = ?',
      variables: [Variable<Object>(localPk)],
      readsFrom: {relatedTable},
    ).asyncMap<D>((row) async {
      final d = await relatedTable.map(row.data);
      return d as D;
    });
  }

  /// Default FK naming: `<lowercase local simpleName>_id`.
  static String defaultForeignPivotKey(Model local) {
    final name = local.runtimeType.toString();
    final base = name.toLowerCase();
    return '${base}_id';
  }

  /// Default FK naming: `<lowercase related tableName (singularised)>_id`.
  static String defaultRelatedPivotKey(TableInfo<Table, Object> relatedTable) {
    final tableName = relatedTable.actualTableName;
    var base = tableName;
    if (base.endsWith('s') && base.length > 1) {
      base = base.substring(0, base.length - 1);
    }
    return '${base}_id';
  }
}