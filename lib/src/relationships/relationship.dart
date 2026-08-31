/// Base class for all relationships.
library;

import 'package:drift/drift.dart';

import '../model.dart';

/// Abstract base for [HasMany], [HasOne], [BelongsTo], [BelongsToMany].
///
/// Subclasses implement `get`, `watch`, `create`, etc. The base class only
/// carries the metadata needed to issue queries.
abstract class Relationship<R extends Model<R, Object>> {
  Relationship({
    required this.local,
    required this.relatedTable,
    required this.foreignKey,
    this.localKey = 'id',
  });

  /// The parent model instance the relationship is bound to.
  final Model local;

  /// The Drift [TableInfo] of the related table.
  final TableInfo<Table, Object> relatedTable;

  /// The foreign-key column name on the related table that points back at
  /// [local].
  final String foreignKey;

  /// The local primary-key column name on [local] ($primaryKey by default).
  final String localKey;

  /// Read the primary-key value from [local] as a plain Dart object.
  Object? get localKeyValue => local.toMap()[localKey];
}