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

/// Metadata describing one relation declared on this builder.
///
/// Pass a `Map<String, RelationSpec>` to [QueryBuilder]'s `relations`
/// parameter to enable the `has` / `whereHas` / `withCount` / `withSum` /
/// `withAvg` / `withMin` / `withMax` chainable methods. Keys are the same
/// strings you would pass to `with_('posts')`; values identify the related
/// Drift table and the foreign-key column on it.
///
/// ## Foreign-key convention
///
/// Each spec carries its own `foreignKey` and `localKey` so the user can
/// be explicit. The Laravel-style registry (`Model.$relations`) is richer
/// (it also gives you the model wrapper and a `creator` callback), but it
/// requires a model *instance*; this builder does not have one, so the
/// metadata is supplied explicitly per-call.
class RelationSpec {
  /// Construct a spec describing one relation.
  const RelationSpec({
    required this.relatedTable,
    required this.foreignKey,
    this.localKey = 'id',
  });

  /// The Drift table of the related model.
  final TableInfo<Table, Object> relatedTable;

  /// The foreign-key column on [relatedTable] pointing back at the parent.
  final String foreignKey;

  /// The local-key column on the parent table. Defaults to `'id'`.
  final String localKey;
}

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
    Map<String, RelationSpec>? relations,
  }) : _relations = relations ?? const <String, RelationSpec>{};

  /// The underlying Drift table.
  final TableInfo<Table, D> table;

  /// Wraps a raw row into the model type [T].
  final T Function(D) creator;

  /// Primary-key column name.
  final String primaryKey;

  /// Relation registry, captured at construction time. Used by `has` /
  /// `whereHas` / `withCount` / etc. to resolve relation names to the
  /// related table + foreign-key column.
  final Map<String, RelationSpec> _relations;

  final List<Expression<bool>> _predicates = <Expression<bool>>[];
  final List<_OrderClause> _orderBy = <_OrderClause>[];
  int _limit = -1;
  int _offset = 0;
  final List<String> _eagerLoad = <String>[];
  final List<_AggregateSpec> _aggregateSpecs = <_AggregateSpec>[];

  // ===== Soft-delete flags =====
  // Default behaviour (both false) matches Laravel: when the table has a
  // `deleted_at` column, soft-deleted rows are excluded automatically.
  bool _includeTrashed = false;
  bool _onlyTrashed = false;

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
    // Route through `applyOperator(op='in')` so the typed `isIn`
    // dispatch lives in one place (`operators.dart`).
    _predicates.add(applyOperator(_colByName(column), 'in', values));
    return this;
  }

  QueryBuilder<T, D> whereNotIn(String column, List<Object?> values) {
    _predicates.add(applyOperator(_colByName(column), 'not in', values));
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

  /// Include soft-deleted rows in the result set.
  ///
  /// Cancels the implicit `deleted_at IS NULL` filter applied when the
  /// table has a `deleted_at` column. On tables without that column, this
  /// is a no-op.
  QueryBuilder<T, D> withTrashed() {
    _includeTrashed = true;
    _onlyTrashed = false;
    return this;
  }

  /// Only return soft-deleted rows.
  ///
  /// Throws [ModelNotSoftDeletableException] if the underlying table has
  /// no `deleted_at` column.
  QueryBuilder<T, D> onlyTrashed() {
    final typed = table as TableInfo<Table, Object>;
    if (!hasColumn(typed, 'deleted_at')) {
      throw ModelNotSoftDeletableException(
        table: typed.actualTableName,
      );
    }
    _onlyTrashed = true;
    _includeTrashed = false;
    return this;
  }

  /// Explicitly exclude soft-deleted rows (the default behaviour).
  QueryBuilder<T, D> withoutTrashed() {
    _includeTrashed = false;
    _onlyTrashed = false;
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

  // ===== has / whereHas / doesntHave / whereDoesntHave =====
  //
  // Strategy: each `has` family call appends a single
  // [Expression<bool>] to _predicates. Drift folds these into the parent
  // WHERE via SimpleSelectStatement.where(...) — so the whole chain
  // (`.where(...).has(...).get()`) compiles to one query.
  //
  // The correlated subqueries' SQL is built by interpolating table and
  // column names. The `?` placeholders inside the user's callback-supplied
  // predicates are written first into a scratch [GenerationContext] so we
  // can grab the resulting SQL fragment; the outer statement then re-runs
  // `writeInto` so the bound variables line up correctly.

  /// Restrict the query to rows that have **at least one** related row.
  ///
  /// `has('posts')` is equivalent to "this row's `posts` relation is not
  /// empty". `has('posts', '>', 5)` means "at least 5 related rows". The
  /// comparison is applied to a `COUNT(*)` subquery against the related
  /// table.
  ///
  /// The relation name must exist in the `relations` map passed to the
  /// [QueryBuilder] constructor.
  QueryBuilder<T, D> has(
    String relation, [
    String op = '>=',
    int value = 1,
  ]) {
    _predicates.add(_buildCountPredicate(relation, op, value));
    return this;
  }

  /// Like [has], but allows adding extra constraints to the subquery via
  /// [callback]. The callback receives a fresh [QueryBuilder] bound to the
  /// related table; `.where(...)` calls inside it add constraints to the
  /// existence check.
  QueryBuilder<T, D> whereHas(
    String relation, [
    void Function(QueryBuilder<dynamic, dynamic> q)? callback,
  ]) {
    _predicates.add(_buildExistsPredicate(relation, callback));
    return this;
  }

  /// Inverse of [has]: only rows whose relation is empty.
  QueryBuilder<T, D> doesntHave(String relation) {
    _predicates.add(_buildNotExistsPredicate(relation, null));
    return this;
  }

  /// Like [doesntHave], but allows adding extra constraints to the
  /// subquery via [callback].
  QueryBuilder<T, D> whereDoesntHave(
    String relation, [
    void Function(QueryBuilder<dynamic, dynamic> q)? callback,
  ]) {
    _predicates.add(_buildNotExistsPredicate(relation, callback));
    return this;
  }

  /// OR-flavoured [has].
  QueryBuilder<T, D> orHas(
    String relation, [
    String op = '>=',
    int value = 1,
  ]) {
    _orAppend(_buildCountPredicate(relation, op, value));
    return this;
  }

  /// OR-flavoured [whereHas].
  QueryBuilder<T, D> orWhereHas(
    String relation, [
    void Function(QueryBuilder<dynamic, dynamic> q)? callback,
  ]) {
    _orAppend(_buildExistsPredicate(relation, callback));
    return this;
  }

  /// OR-flavoured [doesntHave].
  QueryBuilder<T, D> orDoesntHave(String relation) {
    _orAppend(_buildNotExistsPredicate(relation, null));
    return this;
  }

  /// OR-flavoured [whereDoesntHave].
  QueryBuilder<T, D> orWhereDoesntHave(
    String relation, [
    void Function(QueryBuilder<dynamic, dynamic> q)? callback,
  ]) {
    _orAppend(_buildNotExistsPredicate(relation, callback));
    return this;
  }

  // ===== withCount / withSum / withAvg / withMin / withMax =====
  //
  // Strategy: each `withX` appends an [_AggregateSpec] to
  // _aggregateSpecs. At terminal time, when there's at least one spec, we
  // pivot to `Eloquent.db.select(table)..addColumns([...])` so Drift adds
  // correlated-subquery columns to the parent's select list. We then read
  // each TypedResult, wrap via `creator`, and stash the aggregate values
  // on the model via `setLoaded` so callers can retrieve them.

  /// Add a correlated `COUNT(*)` subquery column named `{relation}_count`
  /// (or [alias] when given). The aggregate value is accessible after the
  /// query via `model.getLoaded<int>('{relation}_count')`.
  QueryBuilder<T, D> withCount(String relation, [String? alias]) {
    _aggregateSpecs.add(
      _AggregateSpec(
        relation: relation,
        fn: _AggregateFn.count,
        aliasName: alias,
      ),
    );
    return this;
  }

  /// Add a correlated `SUM({relation}.{column})` subquery column.
  QueryBuilder<T, D> withSum(
    String relation,
    String column, [
    String? alias,
  ]) {
    _aggregateSpecs.add(
      _AggregateSpec(
        relation: relation,
        fn: _AggregateFn.sum,
        column: column,
        aliasName: alias,
      ),
    );
    return this;
  }

  /// Add a correlated `AVG({relation}.{column})` subquery column.
  QueryBuilder<T, D> withAvg(
    String relation,
    String column, [
    String? alias,
  ]) {
    _aggregateSpecs.add(
      _AggregateSpec(
        relation: relation,
        fn: _AggregateFn.avg,
        column: column,
        aliasName: alias,
      ),
    );
    return this;
  }

  /// Add a correlated `MIN({relation}.{column})` subquery column.
  QueryBuilder<T, D> withMin(
    String relation,
    String column, [
    String? alias,
  ]) {
    _aggregateSpecs.add(
      _AggregateSpec(
        relation: relation,
        fn: _AggregateFn.min,
        column: column,
        aliasName: alias,
      ),
    );
    return this;
  }

  /// Add a correlated `MAX({relation}.{column})` subquery column.
  QueryBuilder<T, D> withMax(
    String relation,
    String column, [
    String? alias,
  ]) {
    _aggregateSpecs.add(
      _AggregateSpec(
        relation: relation,
        fn: _AggregateFn.max,
        column: column,
        aliasName: alias,
      ),
    );
    return this;
  }

  // ===== Selectable<T> surface =====

  @override
  Future<List<T>> get() async {
    return _runWithEagerLoad();
  }

  @override
  Future<T> getSingle() async {
    if (_aggregateSpecs.isNotEmpty) {
      final rows = await _runAggregates(limit: 1);
      if (rows.isEmpty) {
        throw StateError('getSingle() returned no rows.');
      }
      return rows.first;
    }
    final stmt = _buildStatement();
    _applyTo(stmt);
    stmt.limit(1);
    final row = await stmt.getSingle();
    return creator(row).wrap(row);
  }

  @override
  Future<T?> getSingleOrNull() async {
    if (_aggregateSpecs.isNotEmpty) {
      final rows = await _runAggregates(limit: 1);
      return rows.isEmpty ? null : rows.first;
    }
    final stmt = _buildStatement();
    _applyTo(stmt);
    stmt.limit(1);
    final row = await stmt.getSingleOrNull();
    return row == null ? null : creator(row).wrap(row);
  }

  @override
  Stream<List<T>> watch() {
    if (_aggregateSpecs.isNotEmpty) {
      // Reactive streams for aggregated queries fall back to a one-shot
      // get() — Drift's `addColumns` returns a different statement type
      // whose watch() we don't fully re-implement. v1 limitation.
      return Stream<List<T>>.fromFuture(_runAggregates());
    }
    final stmt = _buildStatement();
    _applyTo(stmt);
    return stmt.watch().asyncMap((rows) async {
      final models = rows
        .map((r) => creator(r).wrap(r))
        .toList(growable: false);
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
    if (_aggregateSpecs.isNotEmpty) {
      final rows = await _runAggregates(limit: 1);
      return rows.isEmpty ? null : rows.first;
    }
    final stmt = _buildStatement();
    _applyTo(stmt);
    stmt.limit(1);
    final row = await stmt.getSingleOrNull();
    return row == null ? null : creator(row).wrap(row);
  }

  Future<int> count() async {
    // Build a `WHERE ...` clause honoring the soft-delete filter plus any
    // user-supplied predicates so count() agrees with get() (rows that
    // would be hidden from `get()` are also hidden from `count()`).
    final typed = table as TableInfo<Table, Object>;
    final trashed = _trashedExpression();
    final allPreds = <Expression<bool>>[
      if (trashed != null) trashed,
      ..._predicates,
    ];
    String? whereSql;
    if (allPreds.isNotEmpty) {
      final ctx = GenerationContext.fromDb(Eloquent.db);
      ctx.buffer.write(' WHERE ');
      for (var i = 0; i < allPreds.length; i++) {
        if (i > 0) ctx.buffer.write(' AND ');
        allPreds[i].writeInto(ctx);
      }
      whereSql = ctx.buffer.toString();
    }
    final stmt = Eloquent.db.customSelect(
      'SELECT COUNT(*) AS c FROM "${typed.actualTableName}"$whereSql',
      readsFrom: {table},
    );
    final row = await stmt.getSingle();
    return row.read<int>('c');
  }

  /// Pluck a single column's value from each matching row.
  ///
  /// If [key] is null, returns a `List<dynamic>` of column values (one
  /// per row, in query order). If [key] is given, returns a
  /// `Map<dynamic, T>` keyed by the [key] column's value on each row.
  Future<dynamic> pluck(String column, [String? key]) async {
    // Validate columns up front so the user gets ColumnNotFoundException
    // instead of a silent null on a typo.
    _colByName(column);
    if (key != null) _colByName(key);

    final models = await _runWithEagerLoad();
    if (key == null) {
      return <dynamic>[
        for (final m in models) m.toMap()[column],
      ];
    }
    return <dynamic, T>{
      for (final m in models) m.toMap()[key]: m,
    };
  }

  /// Single value of [column] from the first matching row, or null if
  /// there are no rows. Equivalent to `first()?.toMap()[column]`.
  Future<Object?> value(String column) async {
    final model = await first();
    if (model == null) return null;
    return model.toMap()[column];
  }

  /// Run the query and assert that exactly one row matches.
  ///
  /// Throws [ModelNotFoundException] if zero rows match.
  /// Throws [MultipleRecordsFoundException] if more than one row matches.
  Future<T> sole() async {
    final models = await _runWithEagerLoad();
    if (models.isEmpty) {
      throw ModelNotFoundException(
        modelName: T.toString(),
        id: '<sole>',
      );
    }
    if (models.length > 1) {
      throw MultipleRecordsFoundException(
        modelName: T.toString(),
        count: models.length,
      );
    }
    return models.first;
  }

  /// Smallest value of [column] across the table. The column type must
  /// be INTEGER-compatible — calling on a REAL column will surface a
  /// SQLite type error. Use [sum] for a `num`-typed aggregate over
  /// numeric columns.
  Future<int> min(String column) async {
    _colByName(column);
    final stmt = Eloquent.db.customSelect(
      'SELECT MIN("$column") AS v FROM '
      '"${(table as TableInfo<Table, Object>).actualTableName}"',
      readsFrom: {table},
    );
    final row = await stmt.getSingle();
    return row.read<int>('v');
  }

  /// Largest value of [column] across the table. See [min] for column-type
  /// caveats.
  Future<int> max(String column) async {
    _colByName(column);
    final stmt = Eloquent.db.customSelect(
      'SELECT MAX("$column") AS v FROM '
      '"${(table as TableInfo<Table, Object>).actualTableName}"',
      readsFrom: {table},
    );
    final row = await stmt.getSingle();
    return row.read<int>('v');
  }

  /// Arithmetic mean of [column]. Returns `double.nan` if the table is
  /// empty (SQL AVG over zero rows is NULL). Reads through `row.data`
  /// because drift's typed reader for `double?` doesn't decode the
  /// `REAL` column value drift's customSelect returns for AVG.
  Future<double> avg(String column) async {
    _colByName(column);
    final stmt = Eloquent.db.customSelect(
      'SELECT AVG("$column") AS v FROM '
      '"${(table as TableInfo<Table, Object>).actualTableName}"',
      readsFrom: {table},
    );
    final row = await stmt.getSingle();
    final v = row.data['v'];
    return v is num ? v.toDouble() : double.nan;
  }

  /// Total of [column] across the table. Returns `0` if the table is
  /// empty (SQL SUM over zero rows is NULL). Reads through `row.data`
  /// rather than Drift's typed readers because `num` doesn't round-trip
  /// cleanly as a primitive — `int` and `double` both decode, and null
  /// is normalized to `0` here.
  Future<num> sum(String column) async {
    _colByName(column);
    final stmt = Eloquent.db.customSelect(
      'SELECT SUM("$column") AS v FROM '
      '"${(table as TableInfo<Table, Object>).actualTableName}"',
      readsFrom: {table},
    );
    final row = await stmt.getSingle();
    final v = row.data['v'];
    return v is num ? v : 0;
  }

  Future<bool> exists() async {
    if (_aggregateSpecs.isNotEmpty) {
      final rows = await _runAggregates(limit: 1);
      return rows.isNotEmpty;
    }
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

    if (_aggregateSpecs.isNotEmpty) {
      final models =
          await _runAggregates(limit: perPage, offset: offset);
      return Paginator<T>(
        data: models,
        currentPage: page,
        perPage: perPage,
        total: total,
        query: this,
      );
    }

    final stmt = _buildStatement();
    _applyTo(stmt);
    stmt.limit(perPage, offset: offset);

    final rows = await stmt.get();
    final models = rows
        .map((r) => creator(r).wrap(r))
        .toList(growable: false);
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
    final trashedExpr = _trashedExpression();
    if (trashedExpr != null) {
      stmt.where((_) => trashedExpr);
    }
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
    if (_aggregateSpecs.isNotEmpty) {
      return _runAggregates();
    }
    final stmt = _buildStatement();
    _applyTo(stmt);
    final rows = await stmt.get();
    final models = rows
        .map((r) => creator(r).wrap(r))
        .toList(growable: false);
    if (_eagerLoad.isNotEmpty) {
      await _applyEagerLoad(models);
    }
    return models;
  }

  /// Run the query with aggregate subquery columns attached.
  ///
  /// Uses `select(table)..addColumns(...)` so Drift switches to a
  /// `JoinedSelectStatement`; the result is `List<TypedResult>`. For each
  /// row we read back the table data into `D`, wrap via [creator], then
  /// attach the aggregate values to the model via `setLoaded(alias, ...)`.
  Future<List<T>> _runAggregates({int? limit, int? offset}) async {
    final casted = table;
    final stmt = Eloquent.db.select(casted);
    _applyTo(stmt);

    // Build one custom expression per aggregate spec, then attach via
    // addColumns; Drift auto-aliases them (`c0`, `c1`, ...).
    final aggregateExprs = <Expression<Object>>[
      for (final spec in _aggregateSpecs)
        _buildAggregateExpression(spec),
    ];
    final joined = stmt.addColumns(aggregateExprs);

    if (limit != null) {
      if (offset != null && offset > 0) {
        joined.limit(limit, offset: offset);
      } else {
        joined.limit(limit);
      }
    } else if (_limit > 0) {
      if (_offset > 0) {
        joined.limit(_limit, offset: _offset);
      } else {
        joined.limit(_limit);
      }
    } else if (_offset > 0) {
      joined.limit(1 << 30, offset: _offset);
    }

    final rows = await joined.get();
    // `addColumns` attaches each expression as an additional column on the
    // row; read each aggregate back via the expression we passed in. The
    // expression's declared return type (`int`, `num`, `double`) drives
    // drift's typed `read<T>` so we get back values of the matching
    // primitive type, not `Object`.
    final models = <T>[];
    for (final row in rows) {
      final d = row.readTable(casted);
      final model = creator(d).wrap(d);
      for (var i = 0; i < _aggregateSpecs.length; i++) {
        final spec = _aggregateSpecs[i];
        final expr = aggregateExprs[i];
        final Object? value;
        switch (spec.fn) {
          case _AggregateFn.count:
            value = row.read<int>(expr as Expression<int>);
          case _AggregateFn.avg:
            value = row.read<double>(expr as Expression<double>);
          case _AggregateFn.sum:
          case _AggregateFn.min:
          case _AggregateFn.max:
            value = row.read<num>(expr as Expression<num>);
        }
        model.setLoaded(spec.alias, value);
      }
      models.add(model);
    }
    if (_eagerLoad.isNotEmpty && models.isNotEmpty) {
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

  // ===== has / whereHas internals =====

  /// Build a `(SELECT COUNT(*) FROM rel WHERE <correlation>) op value`
  /// predicate for a `has` / `orHas` call.
  Expression<bool> _buildCountPredicate(
    String relation,
    String op,
    int value,
  ) {
    final rel = _requireRelation(relation);
    final relatedTableName = rel.relatedTable.actualTableName;
    final localTableName =
        (table as TableInfo<Table, Object>).actualTableName;
    final correlation =
        '$relatedTableName.${rel.foreignKey} = $localTableName.${rel.localKey}';
    final subquerySql =
        'SELECT COUNT(*) FROM $relatedTableName WHERE $correlation';
    return _SubqueryIntCompareExpression(
      subquerySql: subquerySql,
      op: op,
      value: value,
    );
  }

  /// Build an `EXISTS (SELECT 1 FROM rel WHERE <correlation> [AND extra])`
  /// predicate for `whereHas` / `orWhereHas`.
  Expression<bool> _buildExistsPredicate(
    String relation,
    void Function(QueryBuilder<dynamic, dynamic> q)? callback,
  ) {
    final rel = _requireRelation(relation);
    final relatedTableName = rel.relatedTable.actualTableName;
    final localTableName =
        (table as TableInfo<Table, Object>).actualTableName;
    final correlation =
        '$relatedTableName.${rel.foreignKey} = $localTableName.${rel.localKey}';
    final extra = _callbackExtraWhere(rel, callback);
    final subquerySql = extra.isEmpty
        ? 'SELECT 1 FROM $relatedTableName WHERE $correlation'
        : 'SELECT 1 FROM $relatedTableName WHERE ($correlation) AND $extra';
    return _SubqueryExistsExpression(subquerySql: subquerySql);
  }

  /// Build a `NOT EXISTS (...)` predicate for `doesntHave` /
  /// `whereDoesntHave`.
  Expression<bool> _buildNotExistsPredicate(
    String relation,
    void Function(QueryBuilder<dynamic, dynamic> q)? callback,
  ) {
    final rel = _requireRelation(relation);
    final relatedTableName = rel.relatedTable.actualTableName;
    final localTableName =
        (table as TableInfo<Table, Object>).actualTableName;
    final correlation =
        '$relatedTableName.${rel.foreignKey} = $localTableName.${rel.localKey}';
    final extra = _callbackExtraWhere(rel, callback);
    final subquerySql = extra.isEmpty
        ? 'SELECT 1 FROM $relatedTableName WHERE $correlation'
        : 'SELECT 1 FROM $relatedTableName WHERE ($correlation) AND $extra';
    return _SubqueryNotExistsExpression(subquerySql: subquerySql);
  }

  /// Build an `(SELECT AGG FROM related WHERE correlation)` expression
  /// suitable for passing to `addColumns` (the `withCount` / `withSum` /
  /// etc. pathway). The returned expression is typed (int / num / double)
  /// so drift can bind it to a SQL type at read-time.
  Expression<Object> _buildAggregateExpression(_AggregateSpec spec) {
    final rel = _requireRelation(spec.relation);
    final relatedTableName = rel.relatedTable.actualTableName;
    final localTableName =
        (table as TableInfo<Table, Object>).actualTableName;
    final correlation =
        '$relatedTableName.${rel.foreignKey} = $localTableName.${rel.localKey}';
    switch (spec.fn) {
      case _AggregateFn.count:
        return _IntSubqueryAggregateExpression(
          functionSql: 'COUNT(*)',
          relatedTableName: relatedTableName,
          correlation: correlation,
        );
      case _AggregateFn.avg:
        return _DoubleSubqueryAggregateExpression(
          functionSql: 'AVG($relatedTableName.${spec.column})',
          relatedTableName: relatedTableName,
          correlation: correlation,
        );
      case _AggregateFn.sum:
        return _NumSubqueryAggregateExpression(
          functionSql: 'SUM($relatedTableName.${spec.column})',
          relatedTableName: relatedTableName,
          correlation: correlation,
        );
      case _AggregateFn.min:
        return _NumSubqueryAggregateExpression(
          functionSql: 'MIN($relatedTableName.${spec.column})',
          relatedTableName: relatedTableName,
          correlation: correlation,
        );
      case _AggregateFn.max:
        return _NumSubqueryAggregateExpression(
          functionSql: 'MAX($relatedTableName.${spec.column})',
          relatedTableName: relatedTableName,
          correlation: correlation,
        );
    }
  }

  /// Look up [relation] in `_relations` and throw a
  /// [RelationNotFoundException] (with the available-relations list) if it
  /// isn't there.
  RelationSpec _requireRelation(String relation) {
    final rel = _relations[relation];
    if (rel == null) {
      throw RelationNotFoundException(
        relation: relation,
        availableRelations: _relations.keys.toList()..sort(),
      );
    }
    return rel;
  }

  /// OR-append [p] to `_predicates`, mirroring `orWhere`'s
  /// "combine with the prior predicate; or just push if empty" rule.
  void _orAppend(Expression<bool> p) {
    if (_predicates.isEmpty) {
      _predicates.add(p);
    } else {
      final last = _predicates.removeLast();
      _predicates.add(last | p);
    }
  }

  /// Materialise the [callback]'s predicates into a single SQL fragment
  /// (already joined by AND, in parentheses if more than one). Returns an
  /// empty string when there is no callback or no predicates.
  ///
  /// The `?` placeholders and their [Variable]s are written into a
  /// scratch [GenerationContext]; they're then re-emitted when the outer
  /// [Statement] re-runs `writeInto` on the enclosing expression. This
  /// matters because Drift's variable-index bookkeeping is per-context.
  String _callbackExtraWhere(
    RelationSpec rel,
    void Function(QueryBuilder<dynamic, dynamic> q)? callback,
  ) {
    if (callback == null) return '';
    // Build a scratch QueryBuilder bound to the related table. We use the
    // unconstrained `dynamic, dynamic` form so callers don't need a real
    // model class to chain `.where(...)` against — only the
    // `RelationSpec.relatedTable` is required.
    // ignore: type_argument_not_matching_bounds
    final tempBuilder = QueryBuilder<dynamic, dynamic>(
      table: rel.relatedTable,
      creator: (d) => d,
      primaryKey: rel.localKey,
    );
    callback(tempBuilder);
    if (tempBuilder._predicates.isEmpty) return '';
    final ctx = GenerationContext.fromDb(Eloquent.db);
    final fragments = <String>[];
    for (var i = 0; i < tempBuilder._predicates.length; i++) {
      if (i > 0) fragments.add(' AND ');
      final startLen = ctx.buffer.length;
      tempBuilder._predicates[i].writeInto(ctx);
      fragments.add(ctx.buffer.toString().substring(startLen));
    }
    return fragments.length == 1
        ? fragments.single
        : '(${fragments.join()})';
  }

  GeneratedColumn<Object> _colByName(String name) =>
      resolveColumn(table as TableInfo<Table, Object>, name);

  /// Returns the soft-delete predicate derived from the `_includeTrashed`
  /// / `_onlyTrashed` flags, or `null` to leave the query alone.
  ///
  /// Resolves to `null` whenever the table does not have a `deleted_at`
  /// column — soft-delete filtering is opt-in based on schema.
  Expression<bool>? _trashedExpression() {
    final typed = table as TableInfo<Table, Object>;
    if (!hasColumn(typed, 'deleted_at')) return null;
    final col = resolveColumn(typed, 'deleted_at');
    if (_onlyTrashed) {
      return col.isNotNull();
    }
    if (!_includeTrashed) {
      return col.isNull();
    }
    return null;
  }
}

class _OrderClause {
  const _OrderClause({required this.column, required this.descending});
  final String column;
  final bool descending;
}

// ===== internal: aggregate spec =====

enum _AggregateFn { count, sum, avg, min, max }

/// Describes one `withCount` / `withSum` / `withAvg` / `withMin` /
/// `withMax` call.
class _AggregateSpec {
  _AggregateSpec({
    required this.relation,
    required this.fn,
    this.column,
    this.aliasName,
  });

  final String relation;
  final _AggregateFn fn;
  final String? column;

  /// Caller-supplied alias (optional). Falls back to a function-specific
  /// default below.
  final String? aliasName;

  /// The alias the aggregate column will be stored under on the model
  /// (via `setLoaded`).
  String get alias {
    if (aliasName != null) return aliasName!;
    switch (fn) {
      case _AggregateFn.count:
        return '${relation}_count';
      case _AggregateFn.sum:
        return '${relation}_sum_${column ?? ''}';
      case _AggregateFn.avg:
        return '${relation}_avg_${column ?? ''}';
      case _AggregateFn.min:
        return '${relation}_min_${column ?? ''}';
      case _AggregateFn.max:
        return '${relation}_max_${column ?? ''}';
    }
  }
}

// ===== internal: custom Expression subclasses =====

/// `(<subquery>) <op> <value>` — wraps a correlated COUNT subquery and
/// applies an integer comparison operator to it. Writes a single `?`
/// placeholder for `value`, registered with the outer [GenerationContext].
class _SubqueryIntCompareExpression extends Expression<bool> {
  _SubqueryIntCompareExpression({
    required this.subquerySql,
    required this.op,
    required this.value,
  });

  final String subquerySql;
  final String op;
  final int value;

  @override
  Precedence get precedence => Precedence.comparisonEq;

  @override
  void writeInto(GenerationContext context) {
    final v = Variable<int>(value);
    context.buffer.write('(');
    context.buffer.write(subquerySql);
    context.buffer.write(')');
    context.buffer.write(' $op ');
    v.writeInto(context);
  }

  @override
  int get hashCode => Object.hash(subquerySql, op, value);

  @override
  bool operator ==(Object other) {
    if (other is! _SubqueryIntCompareExpression) return false;
    return other.subquerySql == subquerySql &&
        other.op == op &&
        other.value == value;
  }
}

/// `EXISTS (<subquery>)` — writes no `?` placeholders of its own; any
/// inside [subquerySql] were already registered by the original
/// callback's `writeInto` and will be re-emitted when this expression is
/// itself `writeInto`'d.
class _SubqueryExistsExpression extends Expression<bool> {
  _SubqueryExistsExpression({required this.subquerySql});
  final String subquerySql;

  @override
  Precedence get precedence => Precedence.comparisonEq;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('EXISTS (');
    context.buffer.write(subquerySql);
    context.buffer.write(')');
  }

  @override
  int get hashCode => subquerySql.hashCode;

  @override
  bool operator ==(Object other) {
    return other is _SubqueryExistsExpression &&
        other.subquerySql == subquerySql;
  }
}

/// `NOT EXISTS (<subquery>)` — same variable-handling rules as
/// [_SubqueryExistsExpression].
class _SubqueryNotExistsExpression extends Expression<bool> {
  _SubqueryNotExistsExpression({required this.subquerySql});
  final String subquerySql;

  @override
  Precedence get precedence => Precedence.comparisonEq;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('NOT EXISTS (');
    context.buffer.write(subquerySql);
    context.buffer.write(')');
  }

  @override
  int get hashCode => subquerySql.hashCode;

  @override
  bool operator ==(Object other) {
    return other is _SubqueryNotExistsExpression &&
        other.subquerySql == subquerySql;
  }
}

/// `(SELECT <agg-fn> FROM <related> WHERE <correlation>)` — used as a
/// SELECT-column expression by `withCount` / `withSum` / etc.
///
/// Three specialised subclasses — `IntSubqueryAggregateExpression`,
/// `_DoubleSubqueryAggregateExpression`, `_NumSubqueryAggregateExpression`
/// — declare the Dart return type so drift can match it against a SQL
/// type when `TypedResult.read<T>` is called. `Expression<Object>` (the
/// natural parent) has no SQL-type mapping and would throw at read time.
///
/// Each subclass extends the corresponding `Expression<T>` directly rather
/// than sharing a base class: Dart disallows implementing two
/// `Expression<...>` instantiations with different type parameters.

/// `COUNT(*)` — always INTEGER. Exposed via `read<int>` on the result.
class _IntSubqueryAggregateExpression extends Expression<int> {
  _IntSubqueryAggregateExpression({
    required this.functionSql,
    required this.relatedTableName,
    required this.correlation,
  });

  final String functionSql;
  final String relatedTableName;
  final String correlation;

  @override
  Precedence get precedence => Precedence.primary;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('(SELECT ');
    context.buffer.write(functionSql);
    context.buffer.write(' FROM ');
    context.buffer.write(relatedTableName);
    context.buffer.write(' WHERE ');
    context.buffer.write(correlation);
    context.buffer.write(')');
  }

  @override
  int get hashCode =>
      Object.hash(functionSql, relatedTableName, correlation);

  @override
  bool operator ==(Object other) {
    return other is _IntSubqueryAggregateExpression &&
        other.functionSql == functionSql &&
        other.relatedTableName == relatedTableName &&
        other.correlation == correlation;
  }
}

/// `AVG(col)` — always REAL. Exposed via `read<double>` on the result.
class _DoubleSubqueryAggregateExpression extends Expression<double> {
  _DoubleSubqueryAggregateExpression({
    required this.functionSql,
    required this.relatedTableName,
    required this.correlation,
  });

  final String functionSql;
  final String relatedTableName;
  final String correlation;

  @override
  Precedence get precedence => Precedence.primary;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('(SELECT ');
    context.buffer.write(functionSql);
    context.buffer.write(' FROM ');
    context.buffer.write(relatedTableName);
    context.buffer.write(' WHERE ');
    context.buffer.write(correlation);
    context.buffer.write(')');
  }

  @override
  int get hashCode =>
      Object.hash(functionSql, relatedTableName, correlation);

  @override
  bool operator ==(Object other) {
    return other is _DoubleSubqueryAggregateExpression &&
        other.functionSql == functionSql &&
        other.relatedTableName == relatedTableName &&
        other.correlation == correlation;
  }
}

/// `SUM` / `MIN` / `MAX` over an INTEGER column — INTEGER. Exposed via
/// `read<num>`.
class _NumSubqueryAggregateExpression extends Expression<num> {
  _NumSubqueryAggregateExpression({
    required this.functionSql,
    required this.relatedTableName,
    required this.correlation,
  });

  final String functionSql;
  final String relatedTableName;
  final String correlation;

  @override
  Precedence get precedence => Precedence.primary;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write('(SELECT ');
    context.buffer.write(functionSql);
    context.buffer.write(' FROM ');
    context.buffer.write(relatedTableName);
    context.buffer.write(' WHERE ');
    context.buffer.write(correlation);
    context.buffer.write(')');
  }

  @override
  int get hashCode =>
      Object.hash(functionSql, relatedTableName, correlation);

  @override
  bool operator ==(Object other) {
    return other is _NumSubqueryAggregateExpression &&
        other.functionSql == functionSql &&
        other.relatedTableName == relatedTableName &&
        other.correlation == correlation;
  }
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
