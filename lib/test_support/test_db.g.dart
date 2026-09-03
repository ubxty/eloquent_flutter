// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_db.dart';

// ignore_for_file: type=lint
class $WidgetsTable extends Widgets with TableInfo<$WidgetsTable, WidgetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WidgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _metaMeta = const VerificationMeta('meta');
  @override
  late final GeneratedColumn<String> meta = GeneratedColumn<String>(
      'meta', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _stockMeta = const VerificationMeta('stock');
  @override
  late final GeneratedColumn<int> stock = GeneratedColumn<int>(
      'stock', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, meta, stock, deletedAt, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'widgets';
  @override
  VerificationContext validateIntegrity(Insertable<WidgetRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('meta')) {
      context.handle(
          _metaMeta, meta.isAcceptableOrUnknown(data['meta']!, _metaMeta));
    }
    if (data.containsKey('stock')) {
      context.handle(
          _stockMeta, stock.isAcceptableOrUnknown(data['stock']!, _stockMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WidgetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WidgetRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      meta: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}meta']),
      stock: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}stock'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $WidgetsTable createAlias(String alias) {
    return $WidgetsTable(attachedDatabase, alias);
  }
}

class WidgetRow extends DataClass implements Insertable<WidgetRow> {
  final int id;
  final String name;
  final String? meta;
  final int stock;
  final DateTime? deletedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  const WidgetRow(
      {required this.id,
      required this.name,
      this.meta,
      required this.stock,
      this.deletedAt,
      this.createdAt,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || meta != null) {
      map['meta'] = Variable<String>(meta);
    }
    map['stock'] = Variable<int>(stock);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  WidgetsCompanion toCompanion(bool nullToAbsent) {
    return WidgetsCompanion(
      id: Value(id),
      name: Value(name),
      meta: meta == null && nullToAbsent ? const Value.absent() : Value(meta),
      stock: Value(stock),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory WidgetRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WidgetRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      meta: serializer.fromJson<String?>(json['meta']),
      stock: serializer.fromJson<int>(json['stock']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'meta': serializer.toJson<String?>(meta),
      'stock': serializer.toJson<int>(stock),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  WidgetRow copyWith(
          {int? id,
          String? name,
          Value<String?> meta = const Value.absent(),
          int? stock,
          Value<DateTime?> deletedAt = const Value.absent(),
          Value<DateTime?> createdAt = const Value.absent(),
          Value<DateTime?> updatedAt = const Value.absent()}) =>
      WidgetRow(
        id: id ?? this.id,
        name: name ?? this.name,
        meta: meta.present ? meta.value : this.meta,
        stock: stock ?? this.stock,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  WidgetRow copyWithCompanion(WidgetsCompanion data) {
    return WidgetRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      meta: data.meta.present ? data.meta.value : this.meta,
      stock: data.stock.present ? data.stock.value : this.stock,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WidgetRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('meta: $meta, ')
          ..write('stock: $stock, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, meta, stock, deletedAt, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WidgetRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.meta == this.meta &&
          other.stock == this.stock &&
          other.deletedAt == this.deletedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WidgetsCompanion extends UpdateCompanion<WidgetRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> meta;
  final Value<int> stock;
  final Value<DateTime?> deletedAt;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> updatedAt;
  const WidgetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.meta = const Value.absent(),
    this.stock = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WidgetsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.meta = const Value.absent(),
    this.stock = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<WidgetRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? meta,
    Expression<int>? stock,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (meta != null) 'meta': meta,
      if (stock != null) 'stock': stock,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WidgetsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String?>? meta,
      Value<int>? stock,
      Value<DateTime?>? deletedAt,
      Value<DateTime?>? createdAt,
      Value<DateTime?>? updatedAt}) {
    return WidgetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      meta: meta ?? this.meta,
      stock: stock ?? this.stock,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (meta.present) {
      map['meta'] = Variable<String>(meta.value);
    }
    if (stock.present) {
      map['stock'] = Variable<int>(stock.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WidgetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('meta: $meta, ')
          ..write('stock: $stock, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CommentsTable extends Comments
    with TableInfo<$CommentsTable, CommentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CommentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _widgetIdMeta =
      const VerificationMeta('widgetId');
  @override
  late final GeneratedColumn<int> widgetId = GeneratedColumn<int>(
      'widget_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
      'body', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, widgetId, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comments';
  @override
  VerificationContext validateIntegrity(Insertable<CommentRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('widget_id')) {
      context.handle(_widgetIdMeta,
          widgetId.isAcceptableOrUnknown(data['widget_id']!, _widgetIdMeta));
    } else if (isInserting) {
      context.missing(_widgetIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
          _bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CommentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CommentRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      widgetId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}widget_id'])!,
      body: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}body'])!,
    );
  }

  @override
  $CommentsTable createAlias(String alias) {
    return $CommentsTable(attachedDatabase, alias);
  }
}

class CommentRow extends DataClass implements Insertable<CommentRow> {
  final int id;
  final int widgetId;
  final String body;
  const CommentRow(
      {required this.id, required this.widgetId, required this.body});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['widget_id'] = Variable<int>(widgetId);
    map['body'] = Variable<String>(body);
    return map;
  }

  CommentsCompanion toCompanion(bool nullToAbsent) {
    return CommentsCompanion(
      id: Value(id),
      widgetId: Value(widgetId),
      body: Value(body),
    );
  }

  factory CommentRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CommentRow(
      id: serializer.fromJson<int>(json['id']),
      widgetId: serializer.fromJson<int>(json['widgetId']),
      body: serializer.fromJson<String>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'widgetId': serializer.toJson<int>(widgetId),
      'body': serializer.toJson<String>(body),
    };
  }

  CommentRow copyWith({int? id, int? widgetId, String? body}) => CommentRow(
        id: id ?? this.id,
        widgetId: widgetId ?? this.widgetId,
        body: body ?? this.body,
      );
  CommentRow copyWithCompanion(CommentsCompanion data) {
    return CommentRow(
      id: data.id.present ? data.id.value : this.id,
      widgetId: data.widgetId.present ? data.widgetId.value : this.widgetId,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CommentRow(')
          ..write('id: $id, ')
          ..write('widgetId: $widgetId, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, widgetId, body);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CommentRow &&
          other.id == this.id &&
          other.widgetId == this.widgetId &&
          other.body == this.body);
}

class CommentsCompanion extends UpdateCompanion<CommentRow> {
  final Value<int> id;
  final Value<int> widgetId;
  final Value<String> body;
  const CommentsCompanion({
    this.id = const Value.absent(),
    this.widgetId = const Value.absent(),
    this.body = const Value.absent(),
  });
  CommentsCompanion.insert({
    this.id = const Value.absent(),
    required int widgetId,
    required String body,
  })  : widgetId = Value(widgetId),
        body = Value(body);
  static Insertable<CommentRow> custom({
    Expression<int>? id,
    Expression<int>? widgetId,
    Expression<String>? body,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (widgetId != null) 'widget_id': widgetId,
      if (body != null) 'body': body,
    });
  }

  CommentsCompanion copyWith(
      {Value<int>? id, Value<int>? widgetId, Value<String>? body}) {
    return CommentsCompanion(
      id: id ?? this.id,
      widgetId: widgetId ?? this.widgetId,
      body: body ?? this.body,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (widgetId.present) {
      map['widget_id'] = Variable<int>(widgetId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CommentsCompanion(')
          ..write('id: $id, ')
          ..write('widgetId: $widgetId, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }
}

abstract class _$TestDb extends GeneratedDatabase {
  _$TestDb(QueryExecutor e) : super(e);
  $TestDbManager get managers => $TestDbManager(this);
  late final $WidgetsTable widgets = $WidgetsTable(this);
  late final $CommentsTable comments = $CommentsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [widgets, comments];
}

typedef $$WidgetsTableCreateCompanionBuilder = WidgetsCompanion Function({
  Value<int> id,
  required String name,
  Value<String?> meta,
  Value<int> stock,
  Value<DateTime?> deletedAt,
  Value<DateTime?> createdAt,
  Value<DateTime?> updatedAt,
});
typedef $$WidgetsTableUpdateCompanionBuilder = WidgetsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String?> meta,
  Value<int> stock,
  Value<DateTime?> deletedAt,
  Value<DateTime?> createdAt,
  Value<DateTime?> updatedAt,
});

class $$WidgetsTableFilterComposer extends Composer<_$TestDb, $WidgetsTable> {
  $$WidgetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get meta => $composableBuilder(
      column: $table.meta, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get stock => $composableBuilder(
      column: $table.stock, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$WidgetsTableOrderingComposer extends Composer<_$TestDb, $WidgetsTable> {
  $$WidgetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get meta => $composableBuilder(
      column: $table.meta, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get stock => $composableBuilder(
      column: $table.stock, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$WidgetsTableAnnotationComposer
    extends Composer<_$TestDb, $WidgetsTable> {
  $$WidgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get meta =>
      $composableBuilder(column: $table.meta, builder: (column) => column);

  GeneratedColumn<int> get stock =>
      $composableBuilder(column: $table.stock, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WidgetsTableTableManager extends RootTableManager<
    _$TestDb,
    $WidgetsTable,
    WidgetRow,
    $$WidgetsTableFilterComposer,
    $$WidgetsTableOrderingComposer,
    $$WidgetsTableAnnotationComposer,
    $$WidgetsTableCreateCompanionBuilder,
    $$WidgetsTableUpdateCompanionBuilder,
    (WidgetRow, BaseReferences<_$TestDb, $WidgetsTable, WidgetRow>),
    WidgetRow,
    PrefetchHooks Function()> {
  $$WidgetsTableTableManager(_$TestDb db, $WidgetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WidgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WidgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WidgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> meta = const Value.absent(),
            Value<int> stock = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<DateTime?> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              WidgetsCompanion(
            id: id,
            name: name,
            meta: meta,
            stock: stock,
            deletedAt: deletedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String?> meta = const Value.absent(),
            Value<int> stock = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<DateTime?> createdAt = const Value.absent(),
            Value<DateTime?> updatedAt = const Value.absent(),
          }) =>
              WidgetsCompanion.insert(
            id: id,
            name: name,
            meta: meta,
            stock: stock,
            deletedAt: deletedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WidgetsTableProcessedTableManager = ProcessedTableManager<
    _$TestDb,
    $WidgetsTable,
    WidgetRow,
    $$WidgetsTableFilterComposer,
    $$WidgetsTableOrderingComposer,
    $$WidgetsTableAnnotationComposer,
    $$WidgetsTableCreateCompanionBuilder,
    $$WidgetsTableUpdateCompanionBuilder,
    (WidgetRow, BaseReferences<_$TestDb, $WidgetsTable, WidgetRow>),
    WidgetRow,
    PrefetchHooks Function()>;
typedef $$CommentsTableCreateCompanionBuilder = CommentsCompanion Function({
  Value<int> id,
  required int widgetId,
  required String body,
});
typedef $$CommentsTableUpdateCompanionBuilder = CommentsCompanion Function({
  Value<int> id,
  Value<int> widgetId,
  Value<String> body,
});

class $$CommentsTableFilterComposer extends Composer<_$TestDb, $CommentsTable> {
  $$CommentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get widgetId => $composableBuilder(
      column: $table.widgetId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnFilters(column));
}

class $$CommentsTableOrderingComposer
    extends Composer<_$TestDb, $CommentsTable> {
  $$CommentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get widgetId => $composableBuilder(
      column: $table.widgetId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnOrderings(column));
}

class $$CommentsTableAnnotationComposer
    extends Composer<_$TestDb, $CommentsTable> {
  $$CommentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get widgetId =>
      $composableBuilder(column: $table.widgetId, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$CommentsTableTableManager extends RootTableManager<
    _$TestDb,
    $CommentsTable,
    CommentRow,
    $$CommentsTableFilterComposer,
    $$CommentsTableOrderingComposer,
    $$CommentsTableAnnotationComposer,
    $$CommentsTableCreateCompanionBuilder,
    $$CommentsTableUpdateCompanionBuilder,
    (CommentRow, BaseReferences<_$TestDb, $CommentsTable, CommentRow>),
    CommentRow,
    PrefetchHooks Function()> {
  $$CommentsTableTableManager(_$TestDb db, $CommentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CommentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CommentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CommentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> widgetId = const Value.absent(),
            Value<String> body = const Value.absent(),
          }) =>
              CommentsCompanion(
            id: id,
            widgetId: widgetId,
            body: body,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int widgetId,
            required String body,
          }) =>
              CommentsCompanion.insert(
            id: id,
            widgetId: widgetId,
            body: body,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CommentsTableProcessedTableManager = ProcessedTableManager<
    _$TestDb,
    $CommentsTable,
    CommentRow,
    $$CommentsTableFilterComposer,
    $$CommentsTableOrderingComposer,
    $$CommentsTableAnnotationComposer,
    $$CommentsTableCreateCompanionBuilder,
    $$CommentsTableUpdateCompanionBuilder,
    (CommentRow, BaseReferences<_$TestDb, $CommentsTable, CommentRow>),
    CommentRow,
    PrefetchHooks Function()>;

class $TestDbManager {
  final _$TestDb _db;
  $TestDbManager(this._db);
  $$WidgetsTableTableManager get widgets =>
      $$WidgetsTableTableManager(_db, _db.widgets);
  $$CommentsTableTableManager get comments =>
      $$CommentsTableTableManager(_db, _db.comments);
}
