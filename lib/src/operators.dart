/// Maps Eloquent-style operator strings to Drift [Expression]s.
library;

import 'package:drift/drift.dart';

import 'exceptions.dart';

/// Every operator string the package understands.
///
/// `=` and `==` are aliases. `<>` and `!=` are aliases.
const Set<String> kSupportedOperators = {
  '=',
  '==',
  '!=',
  '<>',
  '>',
  '>=',
  '<',
  '<=',
  'like',
  'not like',
  'in',
  'not in',
  'is null',
  'is not null',
  'between',
};

/// Returns true if [op] is recognised by [applyOperator].
bool isValidOperator(String op) =>
    kSupportedOperators.contains(op.toLowerCase());

/// Apply [op] to [column] using [value] as the right-hand operand.
///
/// Drift exposes most of its typed comparator methods as extensions on
/// `Expression<Comparable>` / `Expression<int>` / etc. — those extensions
/// only resolve when the static type is known, so we upcast the column to
/// each concrete subtype and dispatch from there. The `is`-checks below
/// surface clear errors when the column type doesn't match the operator.
///
/// Throws [UnsupportedOperatorException] if [op] is not in
/// [kSupportedOperators].
Expression<bool> applyOperator(
  GeneratedColumn<Object> column,
  String op,
  Object? value,
) {
  final lower = op.toLowerCase();
  switch (lower) {
    case '=':
    case '==':
      return column.equals(value as Object);
    case '!=':
    case '<>':
      if (value == null) {
        return column.isNull();
      }
      return column.equals(value).not();
    case '>':
      return _compare(column, value, _ComparableOp.biggerThan);
    case '>=':
      return _compare(column, value, _ComparableOp.biggerOrEqual);
    case '<':
      return _compare(column, value, _ComparableOp.smallerThan);
    case '<=':
      return _compare(column, value, _ComparableOp.smallerOrEqual);
    case 'like':
      return _like(column, value, negated: false);
    case 'not like':
      return _like(column, value, negated: true);
    case 'in':
      return _isIn(column, value, negated: false);
    case 'not in':
      return _isIn(column, value, negated: true);
    case 'is null':
      return column.isNull();
    case 'is not null':
      return column.isNotNull();
    case 'between':
      final list = (value as List).cast<Object?>();
      if (list.length != 2) {
        throw InvalidArgumentException(
          'BETWEEN requires a 2-element list, got ${list.length}.',
        );
      }
      return _between(column, list[0] as Object, list[1] as Object);
    default:
      throw UnsupportedOperatorException(
        operator: op,
        supported: kSupportedOperators.toList(),
      );
  }
}

enum _ComparableOp { biggerThan, biggerOrEqual, smallerThan, smallerOrEqual }

/// Dispatch comparison operators based on the column's element type so we
/// can statically resolve Drift's `ComparableExpr` extension.
Expression<bool> _compare(
  GeneratedColumn<Object> column,
  Object? value,
  _ComparableOp op,
) {
  if (value is! Comparable) {
    throw InvalidArgumentException(
      'Operator "${op.name}" requires a Comparable value, got '
      '${value.runtimeType}.',
    );
  }
  if (column is GeneratedColumn<int>) {
    return _intCompare(column, value as int, op);
  }
  if (column is GeneratedColumn<double>) {
    return _doubleCompare(column, value as double, op);
  }
  if (column is GeneratedColumn<DateTime>) {
    return _dateTimeCompare(column, value as DateTime, op);
  }
  if (column is GeneratedColumn<String>) {
    return _stringCompare(column, value as String, op);
  }
  if (column is GeneratedColumn<bool>) {
    throw InvalidArgumentException(
      'Comparison operators are not supported on boolean columns.',
    );
  }
  throw InvalidArgumentException(
    'Comparison operators are not supported for column '
    '${column.driftSqlType.runtimeType}.',
  );
}

Expression<bool> _intCompare(
  GeneratedColumn<int> column,
  int value,
  _ComparableOp op,
) {
  switch (op) {
    case _ComparableOp.biggerThan:
      return column.isBiggerThanValue(value);
    case _ComparableOp.biggerOrEqual:
      return column.isBiggerOrEqualValue(value);
    case _ComparableOp.smallerThan:
      return column.isSmallerThanValue(value);
    case _ComparableOp.smallerOrEqual:
      return column.isSmallerOrEqualValue(value);
  }
}

Expression<bool> _doubleCompare(
  GeneratedColumn<double> column,
  double value,
  _ComparableOp op,
) {
  switch (op) {
    case _ComparableOp.biggerThan:
      return column.isBiggerThanValue(value);
    case _ComparableOp.biggerOrEqual:
      return column.isBiggerOrEqualValue(value);
    case _ComparableOp.smallerThan:
      return column.isSmallerThanValue(value);
    case _ComparableOp.smallerOrEqual:
      return column.isSmallerOrEqualValue(value);
  }
}

Expression<bool> _dateTimeCompare(
  GeneratedColumn<DateTime> column,
  DateTime value,
  _ComparableOp op,
) {
  switch (op) {
    case _ComparableOp.biggerThan:
      return column.isBiggerThanValue(value);
    case _ComparableOp.biggerOrEqual:
      return column.isBiggerOrEqualValue(value);
    case _ComparableOp.smallerThan:
      return column.isSmallerThanValue(value);
    case _ComparableOp.smallerOrEqual:
      return column.isSmallerOrEqualValue(value);
  }
}

Expression<bool> _stringCompare(
  GeneratedColumn<String> column,
  String value,
  _ComparableOp op,
) {
  switch (op) {
    case _ComparableOp.biggerThan:
      return column.isBiggerThanValue(value);
    case _ComparableOp.biggerOrEqual:
      return column.isBiggerOrEqualValue(value);
    case _ComparableOp.smallerThan:
      return column.isSmallerThanValue(value);
    case _ComparableOp.smallerOrEqual:
      return column.isSmallerOrEqualValue(value);
  }
}

Expression<bool> _between(
  GeneratedColumn<Object> column,
  Object low,
  Object high,
) {
  if (low is! Comparable || high is! Comparable) {
    throw InvalidArgumentException(
      'BETWEEN bounds must be Comparable, got '
      '${low.runtimeType} and ${high.runtimeType}.',
    );
  }
  // Compose `>= low AND <= high` so we only need to dispatch comparison
  // operators (which already work via the typed upcasts above).
  final lower = _compare(column, low, _ComparableOp.biggerOrEqual);
  final upper = _compare(column, high, _ComparableOp.smallerOrEqual);
  return lower & upper;
}

Expression<bool> _like(
  GeneratedColumn<Object> column,
  Object? value, {
  required bool negated,
}) {
  if (value is! String) {
    throw InvalidArgumentException(
      'LIKE requires a String value, got ${value.runtimeType}.',
    );
  }
  if (column is! GeneratedColumn<String>) {
    throw InvalidArgumentException(
      'LIKE requires a String column, got '
      '${column.driftSqlType}.',
    );
  }
  final expr = column.like(value);
  return negated ? expr.not() : expr;
}

/// `IN` / `NOT IN`. Drift's `Expression<D>.isIn(Iterable<D>)` does a
/// runtime `as Iterable<D>` cast that we can't bypass with `as dynamic`.
/// Dispatch on the column's element type to coerce the list correctly.
Expression<bool> _isIn(
  GeneratedColumn<Object> column,
  Object? value, {
  required bool negated,
}) {
  if (value is! List) {
    throw InvalidArgumentException(
      'IN requires a List, got ${value.runtimeType}.',
    );
  }
  final result = _dispatchIn(column, value);
  return negated ? result.not() : result;
}

Expression<bool> _dispatchIn(
  GeneratedColumn<Object> column,
  List<Object?> values,
) {
  if (column is GeneratedColumn<int>) {
    return column.isIn(values.whereType<int>().toList());
  }
  if (column is GeneratedColumn<String>) {
    return column.isIn(values.whereType<String>().toList());
  }
  if (column is GeneratedColumn<double>) {
    return column.isIn(values.whereType<double>().toList());
  }
  if (column is GeneratedColumn<DateTime>) {
    return column.isIn(values.whereType<DateTime>().toList());
  }
  if (column is GeneratedColumn<Uint8List>) {
    return column.isIn(values.whereType<Uint8List>().toList());
  }
  if (column is GeneratedColumn<bool>) {
    return column.isIn(values.whereType<bool>().toList());
  }
  throw InvalidArgumentException(
    'IN is not supported for column type ${column.driftSqlType.runtimeType}.',
  );
}