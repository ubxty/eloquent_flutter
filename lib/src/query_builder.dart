/// Chainable query builder that implements Drift's [Selectable] surface.
library;

import 'dart:async';

import 'package:drift/drift.dart';

import 'companion_builder.dart';
import 'eloquent.dart';
import 'exceptions.dart';
import 'internal/column_lookup.dart';
import 'model.dart';
import 'operators.dart';
import 'paginator.dart';
import 'relationships/relationship.dart';

/// A chainable Eloquent-style query builder.
///
/// Implements Drift's [Selectable] so the underlying `.get()` / `.watch()`
/// / `.getSingleOrNull()` methods come for free.
class QueryBuilder<T extends Model<T, Object>, D extends Object>
    implements Selectable<T> {
  QueryBuilder({
    required this.table,
    required this.creator,
    this.primaryKey = 'id',
  });

  /// The underlying Drift table.
  final TableInfo<Table, D> table;

  /// Wraps a raw row into the model type [T].
  final T Function(D) creator;

  /// Primary-key column name.
  final String primaryKey;

  final List<Expression<bool>> _predicates = <Expression<bool>>[];
  final List<_OrderClause> _orderBy = <_OrderClause>[];
  int _limit = -1;
  int _offset = 0;
  final List<String> _eagerLoad = <String>[];

  // ===== Chainable =====

  QueryBuilder<T, D> where(
    String column, [
    Object? value,
    String op = '=',
  ]) {
    _predicates.add(applyOperator(_colByName(column), op, value));
    return this;
  }

  QueryBuilder<T, D> orWhere(
    String column, [
    Object? value,
    String op = '=',
  ]) {
    if (_predicates.isEmpty) {
      _predicates.add(applyOperator(_colByName(column), op, value));
    } else {
      final last = _predicates.removeLast();
      _predicates.add(last | applyOperator(_colByName(column), op, value));
    }
    return this;
  }

  QueryBuilder<T, D> whereIn(String column, List<Object?> values) {
    final nonNull = values.whereType<Object>().toList();
    _predicates.add(_colByName(column).isIn(nonNull));
    return this;
  }

  QueryBuilder<T, D> whereNotIn(String column, List<Object?> values) {
    final nonNull = values.whereType<Object>().toList();
    _predicates.add(_colByName(column).isIn(nonNull).not());
    return this;
  }

  QueryBuilder<T, D> whereNull(String column) {
    _predicates.add(_colByName(column).isNull());
    return this;
  }

  QueryBuilder<T, D> whereNotNull(String column) {
    _predicates.add(_colByName(column).isNotNull());
    return this;
  }

  QueryBuilder<T, D> whereBetween(String column, Object a, Object b) {
    _predicates.add(applyOperator(_colByName(column), 'between', [a, b]));
    return this;
  }

  QueryBuilder<T, D> whereRaw(Expression<bool> expr) {
    _predicates.add(expr);
    return this;
  }

  QueryBuilder<T, D> orderBy(String column, {bool descending = false}) {
    _orderBy.add(
      _OrderClause(column: column, descending: descending),
    );
    return this;
  }

  QueryBuilder<T, D> orderByDesc(String column) =>
      orderBy(column, descending: true);

  QueryBuilder<T, D> limit(int n) {
    _limit = n;
    return this;
  }

  QueryBuilder<T, D> offset(int n) {
    _offset = n;
    return this;
  }

  QueryBuilder<T, D> distinct() {
    // distinct is final on SimpleSelectStatement, so we can't toggle it.
    // v1 callers that need SELECT DISTINCT should use customSelect directly.
    return this;
  }

  QueryBuilder<T, D> with_(Object relationOrList) {
    if (relationOrList is String) {
      _eagerLoad.add(relationOrList);
    } else if (relationOrList is Iterable<String>) {
      _eagerLoad.addAll(relationOrList);
    } else {
      throw InvalidArgumentException(
        'with_() expects a String or List<String>, got '
        '${relationOrList.runtimeType}.',
      );
    }
    return this;
  }

  // ===== Selectable<T> surface =====

  @override
  Future<List<T>> get() async {
    return _runWithEagerLoad();
  }

  @override
  Future<T> getSingle() async {
    final stmt = _buildStatement();
    _applyTo(stmt);
    stmt.limit(1);
    final row = await stmt.getSingle();
    return creator(row);
  }

  @override
  Future<T?> getSingleOrNull() async {
    final stmt = _buildStatement();
    _applyTo(stmt);
    stmt.limit(1);
    final row = await stmt.getSingleOrNull();
    return row == null ? null : creator(row);
  }

  @override
  Stream<List<T>> watch() {
    final stmt = _buildStatement();
    _applyTo(stmt);
    return stmt.watch().asyncMap((rows) async {
      final models = rows.map(creator).toList(growable: false);
      if (_eagerLoad.isNotEmpty) {
        await _applyEagerLoad(models);
      }
      return models;
    });
  }

  @override
  Stream<T> watchSingle() {
    return watch().map((rows) => rows.first);
  }

  @override
  Stream<T?> watchSingleOrNull() {
    return watch().map((rows) => rows.isEmpty ? null : rows.first);
  }

  @override
  Selectable<R> map<R>(R Function(T) mapper) {
    return _MapOverSelectable<T, R>(this, mapper);
  }

  @override
  Selectable<R> asyncMap<R>(FutureOr<R> Function(T) mapper) {
    return _AsyncMapOverSelectable<T, R>(this, (rows) async {
      if (rows.isEmpty) {
        throw StateError(
          'asyncMap on QueryBuilder requires at least one row.',
        );
      }
      return mapper(rows.first);
    });
  }

  // ===== Terminal =====

  Future<T?> first() async {
    final stmt = _buildStatement();
    _applyTo(stmt);
    stmt.limit(1);
    final row = await stmt.getSingleOrNull();
    return row == null ? null : creator(row);
  }

  Future<int> count() async {
    final stmt = Eloquent.db.customSelect(
      'SELECT COUNT(*) AS c FROM '
      '${(table as TableInfo<Table, Object>).actualTableName}',
      readsFrom: {table},
    );
    final row = await stmt.getSingle();
    return row.read<int>('c');
  }

  Future<bool> exists() async {
    final stmt = _buildStatement();
    _applyTo(stmt);
    stmt.limit(1);
    final row = await stmt.getSingleOrNull();
    return row != null;
  }

  Future<int> update(Map<String, dynamic> values) {
    final stmt = Eloquent.db.update(table);
    for (final p in _predicates) {
      stmt.where((_) => p);
    }
    return stmt.write(
      CompanionBuilder.fromMap(
        table: table,
        values: values,
        nullToAbsent: true,
      ),
    );
  }

  Future<int> delete() {
    final stmt = Eloquent.db.delete(table);
    for (final p in _predicates) {
      stmt.where((_) => p);
    }
    return stmt.go();
  }

  Future<Paginator<T>> paginate({required int page, required int perPage}) {
    if (page < 1) {
      throw InvalidArgumentException('page must be >= 1, got $page.');
    }
    if (perPage < 1) {
      throw InvalidArgumentException('perPage must be >= 1, got $perPage.');
    }
    return _paginateImpl(page: page, perPage: perPage);
  }

  // ===== internal =====

  Future<Paginator<T>> _paginateImpl({
    required int page,
    required int perPage,
  }) async {
    final total = await count();
    final offset = (page - 1) * perPage;

    final stmt = _buildStatement();
    _applyTo(stmt);
    stmt.limit(perPage, offset: offset);

    final rows = await stmt.get();
    final models = rows.map(creator).toList(growable: false);
    if (_eagerLoad.isNotEmpty) {
      await _applyEagerLoad(models);
    }

    return Paginator<T>(
      data: models,
      currentPage: page,
      perPage: perPage,
      total: total,
      query: this,
    );
  }

  SimpleSelectStatement<Table, D> _buildStatement() {
    // Note: SimpleSelectStatement.distinct is final, so we can't toggle it
    // post-construction. Distinct queries in v1 fall back to raw SELECT
    // DISTINCT * via the Eloquent.db.customSelect escape hatch (see
    // count() for an example).
    return Eloquent.db.select(table);
  }

  void _applyTo(SimpleSelectStatement<Table, D> stmt) {
    for (final p in _predicates) {
      stmt.where((_) => p);
    }
    if (_orderBy.isNotEmpty) {
      stmt.orderBy([
        for (final clause in _orderBy)
          (Table _) => clause.descending
              ? OrderingTerm.desc(_colByName(clause.column))
              : OrderingTerm.asc(_colByName(clause.column)),
      ]);
    }
    if (_limit > 0) {
      if (_offset > 0) {
        stmt.limit(_limit, offset: _offset);
      } else {
        stmt.limit(_limit);
      }
    } else if (_offset > 0) {
      stmt.limit(1 << 30, offset: _offset);
    }
  }

  Future<List<T>> _runWithEagerLoad() async {
    final stmt = _buildStatement();
    _applyTo(stmt);
    final rows = await stmt.get();
    final models = rows.map(creator).toList(growable: false);
    if (_eagerLoad.isNotEmpty) {
      await _applyEagerLoad(models);
    }
    return models;
  }

  Future<void> _applyEagerLoad(List<T> models) async {
    if (models.isEmpty) return;
    final first = models.first;
    final relations = first.$relations;
    for (final name in _eagerLoad) {
      final rel = relations[name];
      if (rel == null) {
        throw RelationNotFoundException(
          relation: name,
          availableRelations: relations.keys.toList()..sort(),
        );
      }
      final loaded = await _dispatchEagerLoad(rel, models);
      for (final entry in loaded.entries) {
        for (final m in models) {
          if (identical(m, entry.key)) {
            m.setLoaded(name, entry.value);
          }
        }
      }
    }
  }

  Future<Map<Model, Object?>> _dispatchEagerLoad(
    Relationship<dynamic> template,
    List<T> models,
  ) async {
    final dyn = template as dynamic;
    final rawMap = await dyn.eagerLoadForParents(models)
        as Map<Object?, Object?>;
    final byId = <Object?, Model>{
      for (final m in models) m.$primaryKeyValue: m,
    };
    final result = <Model, Object?>{};
    for (final entry in rawMap.entries) {
      final m = byId[entry.key];
      if (m != null) result[m] = entry.value;
    }
    return result;
  }

  GeneratedColumn<Object> _colByName(String name) =>
      resolveColumn(table as TableInfo<Table, Object>, name);
}

class _OrderClause {
  const _OrderClause({required this.column, required this.descending});
  final String column;
  final bool descending;
}

/// Maps a [Selectable] element-by-element.
class _MapOverSelectable<S, T>
    implements Selectable<T> {
  _MapOverSelectable(this._source, this._mapper);

  final Selectable<S> _source;
  final T Function(S) _mapper;

  @override
  Future<List<T>> get() async {
    final rows = await _source.get();
    return rows.map(_mapper).toList(growable: false);
  }

  @override
  Stream<List<T>> watch() {
    return _source.watch().map(
          (rows) => rows.map(_mapper).toList(growable: false),
        );
  }

  @override
  Future<T> getSingle() async => (await get()).single;

  @override
  Stream<T> watchSingle() {
    return watch().asyncMap((rows) async => rows.single);
  }

  @override
  Future<T?> getSingleOrNull() async {
    final list = await get();
    if (list.isEmpty) return null;
    return list.single;
  }

  @override
  Stream<T?> watchSingleOrNull() {
    return watch().asyncMap((rows) async => rows.isEmpty ? null : rows.single);
  }

  @override
  Selectable<R> map<R>(R Function(T) mapper) =>
      _MapOverSelectable<T, R>(this, mapper);

  @override
  Selectable<R> asyncMap<R>(FutureOr<R> Function(T) mapper) =>
      _AsyncMapOverSelectable<T, R>(this, (rows) async => mapper(rows.first));
}

/// Single-element projection: collapses a [List] into one value via [mapper].
class _AsyncMapOverSelectable<S, T>
    implements Selectable<T> {
  _AsyncMapOverSelectable(this._source, this._mapper);

  final Selectable<S> _source;
  final Future<T> Function(List<S>) _mapper;

  @override
  Future<List<T>> get() async {
    final rows = await _source.get();
    final v = await _mapper(rows);
    return <T>[v];
  }

  @override
  Stream<List<T>> watch() {
    return _source.watch().asyncMap((rows) async {
      final v = await _mapper(rows);
      return <T>[v];
    });
  }

  @override
  Future<T> getSingle() async => (await get()).single;

  @override
  Stream<T> watchSingle() {
    return watch().asyncMap((rows) async => rows.single);
  }

  @override
  Future<T?> getSingleOrNull() async {
    final list = await get();
    if (list.isEmpty) return null;
    return list.single;
  }

  @override
  Stream<T?> watchSingleOrNull() {
    return watch().asyncMap((rows) async => rows.isEmpty ? null : rows.single);
  }

  @override
  Selectable<R> map<R>(R Function(T) mapper) =>
      _MapOverSelectable<T, R>(this, mapper);

  @override
  Selectable<R> asyncMap<R>(FutureOr<R> Function(T) mapper) =>
      _AsyncMapOverSelectable<T, R>(this, (rows) async => mapper(rows.first));
}