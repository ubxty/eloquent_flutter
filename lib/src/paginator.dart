/// Laravel-style pagination result.
library;

import 'model.dart';
import 'query_builder.dart';

/// Wraps the result of [QueryBuilder.paginate] with page metadata.
///
/// ```dart
/// final page = await User.where('active', true).paginate(page: 2, perPage: 20);
/// page.data;         // List<User>
/// page.currentPage;  // 2
/// page.lastPage;     // 5 (if 100 total rows, perPage=20)
/// page.total;        // 100
/// page.hasMore;      // true
/// ```
class Paginator<T extends Model<T, Object>> {
  Paginator({
    required this.data,
    required this.currentPage,
    required this.perPage,
    required this.total,
    required this.query,
  });

  /// The rows on this page.
  final List<T> data;

  /// The 1-indexed current page number.
  final int currentPage;

  /// The number of rows per page.
  final int perPage;

  /// The total number of rows across all pages.
  final int total;

  /// The originating [QueryBuilder], captured so that [nextPage] /
  /// [previousPage] can re-run the query at a different offset.
  final QueryBuilder<T, Object> query;

  /// Last page number, or 1 if [total] is 0.
  int get lastPage {
    if (total == 0) return 1;
    return ((total + perPage - 1) ~/ perPage).clamp(1, 1 << 30);
  }

  /// True if there is at least one more page after [currentPage].
  bool get hasMore => currentPage < lastPage;

  /// True if there is at least one page before [currentPage].
  bool get hasPrevious => currentPage > 1;

  /// Fetch the next page (or the same page if already at the end).
  Future<Paginator<T>> nextPage() async {
    if (!hasMore) return this;
    return query.paginate(page: currentPage + 1, perPage: perPage);
  }

  /// Fetch the previous page (or the same page if already at the start).
  Future<Paginator<T>> previousPage() async {
    if (!hasPrevious) return this;
    return query.paginate(page: currentPage - 1, perPage: perPage);
  }
}