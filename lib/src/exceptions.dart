/// Exception hierarchy for all `eloquent_flutter` errors.
library;

/// Base class for every exception thrown by `eloquent_flutter`.
abstract class EloquentException implements Exception {
  const EloquentException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a query references a column that does not exist on the table.
///
/// Lists the available columns in the message so typos are easy to fix.
class ColumnNotFoundException extends EloquentException {
  ColumnNotFoundException({
    required this.column,
    required this.table,
    required this.availableColumns,
  }) : super(
          'Column "$column" not found on table "$table". '
          'Available: ${availableColumns.join(', ')}.',
        );

  final String column;
  final String table;
  final List<String> availableColumns;
}

/// Thrown when a table is referenced that has not been registered.
class TableNotFoundException extends EloquentException {
  TableNotFoundException(String table)
      : super(
          'Table "$table" not registered. '
          'Did you call Eloquent.init() with a database that exposes it?',
        );
}

/// Thrown by `findOrFail` when no row matches the given primary key.
class ModelNotFoundException extends EloquentException {
  ModelNotFoundException({
    required this.modelName,
    required this.id,
  }) : super('No $modelName found with id=$id.');

  final String modelName;
  final Object id;
}

/// Thrown when a `where()` clause is given an unknown operator string.
class UnsupportedOperatorException extends EloquentException {
  UnsupportedOperatorException({
    required this.operator,
    required this.supported,
  }) : super(
          'Unsupported operator "$operator". '
          'Supported: ${supported.join(', ')}.',
        );

  final String operator;
  final List<String> supported;
}

/// Thrown when `with_('xxx')` references a relation not declared in
/// `$relations`.
class RelationNotFoundException extends EloquentException {
  RelationNotFoundException({
    required this.relation,
    required this.availableRelations,
  }) : super(
          'Relation "$relation" is not registered on this model. '
          'Available: ${availableRelations.isEmpty ? '(none)' : availableRelations.join(', ')}.',
        );

  final String relation;
  final List<String> availableRelations;
}

/// Thrown when a lifecycle observer returns `false` from `creating()`,
/// `updating()`, or `deleting()`.
class OperationCancelledException extends EloquentException {
  OperationCancelledException({
    required this.stage,
    required this.modelName,
  }) : super(
          'Operation cancelled by $stage observer on $modelName.',
        );

  final String stage; // "creating" | "updating" | "deleting"
  final String modelName;
}

/// Thrown for generic argument-validation failures.
///
/// Used wherever we want to reject an obviously invalid input (negative
/// page numbers, malformed relation declarations, etc.) without inventing
/// a more specific exception.
class InvalidArgumentException extends EloquentException {
  InvalidArgumentException(super.message);
}