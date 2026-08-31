/// Blueprint — column-level schema declarations for `Schema.create()` and
/// `Schema.table()`.
library;

/// All column types the Blueprint DSL understands.
enum ColumnType { integer, text, real, blob, boolean, dateTime }

/// Direction for index / unique constraints.
enum IndexDirection { asc, desc }

/// A single column declaration. Created by [Blueprint] column methods and
/// usable as a fluent builder for further modifiers.
///
/// Modifiers (`.nullable_()`, `.unique_()`, `.primary_()`, `.default_()`)
/// mutate the same instance in place and return it for chaining. The
/// [Blueprint] always holds the live reference, so modifiers applied
/// after the column is added still affect the rendered SQL.
class Column {
  Column._({
    required this.name,
    required this.type,
    this.nullable = false,
    this.autoIncrement = false,
    this.defaultValue,
  });

  /// Column name.
  final String name;

  /// SQLite storage type for `CREATE TABLE` (INTEGER / TEXT / REAL / BLOB).
  final ColumnType type;

  /// Whether the column may be NULL. Mutable — set via `.nullable_()`.
  bool nullable;

  /// Whether the column is `INTEGER PRIMARY KEY AUTOINCREMENT`.
  final bool autoIncrement;

  /// Whether the column is part of the PRIMARY KEY. Mutable.
  bool primary = false;

  /// Whether the column has a UNIQUE constraint. Mutable.
  bool unique = false;

  /// SQL literal or constant for `DEFAULT`. Mutable.
  Object? defaultValue;

  // ===== Modifiers (mutate and return `this` for chaining) =====

  /// Mark the column NULL-allowed. Returns the same instance.
  Column nullable_() {
    nullable = true;
    return this;
  }

  /// Mark the column as having a UNIQUE constraint.
  Column unique_() {
    unique = true;
    return this;
  }

  /// Mark the column as part of the PRIMARY KEY.
  Column primary_() {
    primary = true;
    return this;
  }

  /// Add a DEFAULT clause (raw SQL fragment is escaped at render time).
  Column default_(Object value) {
    defaultValue = value;
    return this;
  }

  /// Render this column as a `CREATE TABLE` column clause.
  String toCreateFragment() {
    final parts = <String>[name, _sqliteType()];
    if (autoIncrement) {
      parts.add('PRIMARY KEY AUTOINCREMENT');
    } else {
      if (primary) parts.add('PRIMARY KEY');
      if (!nullable) parts.add('NOT NULL');
    }
    if (unique) parts.add('UNIQUE');
    final d = defaultValue;
    if (d != null) {
      parts.add('DEFAULT ${_defaultLiteral(d)}');
    }
    return parts.join(' ');
  }

  /// Render this column as an `ALTER TABLE ... ADD COLUMN` clause.
  String toAddFragment() {
    final parts = <String>[name, _sqliteType()];
    if (!nullable) parts.add('NOT NULL');
    final d = defaultValue;
    if (d != null) {
      parts.add('DEFAULT ${_defaultLiteral(d)}');
    }
    return parts.join(' ');
  }

  String _sqliteType() {
    switch (type) {
      case ColumnType.integer:
        return 'INTEGER';
      case ColumnType.text:
        return 'TEXT';
      case ColumnType.real:
        return 'REAL';
      case ColumnType.blob:
        return 'BLOB';
      case ColumnType.boolean:
        // SQLite has no native boolean — store as INTEGER (0/1).
        return 'INTEGER';
      case ColumnType.dateTime:
        // SQLite stores DATETIME as ISO-8601 TEXT or INTEGER unix seconds.
        return 'TEXT';
    }
  }

  static String _defaultLiteral(Object value) {
    if (value is num || value is bool) {
      return value.toString();
    }
    // Escape single quotes.
    final s = value.toString().replaceAll("'", "''");
    return "'$s'";
  }
}

/// Declarative schema for one table. Pass a closure to [Schema.create]
/// or [Schema.table] to populate it.
class Blueprint {
  Blueprint(this.tableName);

  final String tableName;
  final List<Column> columns = <Column>[];
  final List<_ForeignKey> _foreignKeys = <_ForeignKey>[];
  final List<List<String>> indexes = <List<String>>[];
  final List<List<String>> uniques = <List<String>>[];
  final List<String> primaryKeys = <String>[];

  // ===== Column definitions =====

  /// `id INTEGER PRIMARY KEY AUTOINCREMENT`
  void id({String name = 'id'}) {
    columns.add(
      Column._(
        name: name,
        type: ColumnType.integer,
        autoIncrement: true,
      ),
    );
  }

  /// `text TEXT`. Use for short strings and enums.
  Column string(String name) =>
      _add(Column._(name: name, type: ColumnType.text));

  /// `text TEXT`. Use for long-form text.
  Column text(String name) => _add(Column._(name: name, type: ColumnType.text));

  /// `INTEGER`.
  Column integer(String name) =>
      _add(Column._(name: name, type: ColumnType.integer));

  /// `REAL` (double-precision floating point).
  Column real(String name) =>
      _add(Column._(name: name, type: ColumnType.real));

  /// `BLOB`.
  Column blob(String name) =>
      _add(Column._(name: name, type: ColumnType.blob));

  /// `INTEGER` (0/1) for booleans. SQLite has no native BOOL.
  Column boolean(String name) =>
      _add(Column._(name: name, type: ColumnType.boolean));

  /// `TEXT` for ISO-8601 datetimes.
  Column dateTime(String name) =>
      _add(Column._(name: name, type: ColumnType.dateTime));

  /// Add `created_at` and `updated_at` columns (nullable — the
  /// `WithTimestamps` mixin fills them in on save).
  void timestamps() {
    columns.add(
      Column._(name: 'created_at', type: ColumnType.dateTime, nullable: true),
    );
    columns.add(
      Column._(name: 'updated_at', type: ColumnType.dateTime, nullable: true),
    );
  }

  Column _add(Column c) {
    columns.add(c);
    return c;
  }

  // ===== Constraints =====

  /// Composite primary key (used for pivot tables).
  void compositePrimary(List<String> cols) {
    primaryKeys.addAll(cols);
  }

  /// FOREIGN KEY constraint. `references` is in `table.column` form.
  void foreign(
    String column, {
    required String references,
    String onDelete = 'RESTRICT',
    String onUpdate = 'RESTRICT',
  }) {
    _foreignKeys.add(_ForeignKey(
      column: column,
      references: references,
      onDelete: onDelete,
      onUpdate: onUpdate,
    ));
  }

  /// Multi-column INDEX (non-unique).
  void index(List<String> cols) => indexes.add(cols);

  /// Multi-column UNIQUE constraint.
  void unique(List<String> cols) => uniques.add(cols);

  // ===== Alterations (used by Schema.table) =====

  final List<Column> _addedColumns = <Column>[];
  final List<String> _droppedColumns = <String>[];
  final List<_RenameColumn> _renamedColumns = <_RenameColumn>[];
  final List<List<String>> _droppedIndexes = <List<String>>[];

  /// ALTER TABLE ADD COLUMN.
  Column addColumn(String type, String name, {Object? defaultValue}) {
    final t = _parseType(type);
    final c = Column._(
      name: name,
      type: t,
      defaultValue: defaultValue,
    );
    _addedColumns.add(c);
    return c;
  }

  /// ALTER TABLE DROP COLUMN (SQLite 3.35+).
  void dropColumn(String name) => _droppedColumns.add(name);

  /// ALTER TABLE RENAME COLUMN (SQLite 3.25+).
  void renameColumn(String from, String to) {
    _renamedColumns.add(_RenameColumn(from: from, to: to));
  }

  /// DROP INDEX.
  void dropIndex(List<String> cols) => _droppedIndexes.add(cols);

  ColumnType _parseType(String name) {
    switch (name.toLowerCase()) {
      case 'string':
      case 'text':
        return ColumnType.text;
      case 'integer':
      case 'int':
        return ColumnType.integer;
      case 'real':
      case 'double':
      case 'float':
        return ColumnType.real;
      case 'boolean':
      case 'bool':
        return ColumnType.boolean;
      case 'datetime':
      case 'dateTime':
      case 'timestamp':
        return ColumnType.dateTime;
      case 'blob':
        return ColumnType.blob;
      default:
        throw ArgumentError('Unknown column type "$name".');
    }
  }

  // ===== Render =====

  /// Render the full `CREATE TABLE` statement for this Blueprint.
  String toCreateSQL() {
    final buf = StringBuffer('CREATE TABLE $tableName (');
    final parts = <String>[];

    // Columns.
    for (final c in columns) {
      parts.add(c.toCreateFragment());
    }

    // Foreign keys.
    for (final fk in _foreignKeys) {
      parts.add(fk.toFragment());
    }

    // Composite primary key (skip when there's a single INTEGER PK column).
    if (primaryKeys.isNotEmpty &&
        !(primaryKeys.length == 1 &&
            columns.any(
              (c) => c.name == primaryKeys.first && c.autoIncrement,
            ))) {
      parts.add('PRIMARY KEY (${primaryKeys.join(', ')})');
    }

    // Multi-column uniques.
    for (final u in uniques) {
      parts.add('UNIQUE (${u.join(', ')})');
    }

    buf.write(parts.join(', '));
    buf.write(')');

    final sql = buf.toString();

    // Per-column UNIQUE handling: SQLite supports inline UNIQUE.
    // Multi-column UNIQUE has been handled above.

    // Append CREATE INDEX statements (SQLite supports inline indexes in
    // CREATE TABLE via the INDEXED BY / INDEX clauses used by older
    // versions; modern SQLite uses `CREATE INDEX IF NOT EXISTS`).
    final out = <String>[sql];

    for (final idx in indexes) {
      final cols = idx.map((c) => '"$c"').join(', ');
      out.add(
        'CREATE INDEX IF NOT EXISTS idx_${tableName}_${idx.join('_')} '
            'ON $tableName ($cols)',
      );
    }
    return '${out.join(';\n')};';
  }

  /// Render the list of `ALTER TABLE` statements for this Blueprint.
  List<String> toAlterSQLList() {
    final out = <String>[];
    for (final c in _addedColumns) {
      out.add('ALTER TABLE $tableName ADD COLUMN ${c.toAddFragment()}');
    }
    for (final r in _renamedColumns) {
      out.add('ALTER TABLE $tableName RENAME COLUMN ${r.from} TO ${r.to}');
    }
    for (final d in _droppedColumns) {
      out.add('ALTER TABLE $tableName DROP COLUMN $d');
    }
    for (final idx in _droppedIndexes) {
      out.add(
        'DROP INDEX IF EXISTS idx_${tableName}_${idx.join('_')}',
      );
    }
    return out;
  }
}

class _ForeignKey {
  const _ForeignKey({
    required this.column,
    required this.references,
    required this.onDelete,
    required this.onUpdate,
  });

  final String column;
  final String references;
  final String onDelete;
  final String onUpdate;

  String toFragment() {
    final ref = _normalizeReference(references);
    return 'FOREIGN KEY ($column) REFERENCES $ref '
        'ON DELETE $onDelete ON UPDATE $onUpdate';
  }

  /// Accept either `users.id` (Laravel-style) or `users(id)` and emit the
  /// SQLite `table(column)` form.
  static String _normalizeReference(String ref) {
    final dot = ref.indexOf('.');
    if (dot == -1) return ref;
    return '${ref.substring(0, dot)}(${ref.substring(dot + 1)})';
  }
}

class _RenameColumn {
  const _RenameColumn({required this.from, required this.to});
  final String from;
  final String to;
}