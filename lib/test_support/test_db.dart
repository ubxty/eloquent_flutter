/// Test-only Drift database used by `test/p0_features_test.dart`.
///
/// Lives in `lib/test_support/` so `drift_dev`'s codegen picks it up.
library;

import 'package:drift/drift.dart';

part 'test_db.g.dart';

@DataClassName('WidgetRow')
class Widgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get meta => text().nullable()();
  IntColumn get stock => integer().withDefault(const Constant(0))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

@DataClassName('CommentRow')
class Comments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get widgetId => integer()();
  TextColumn get body => text()();
}

@DriftDatabase(tables: [Widgets, Comments])
class TestDb extends _$TestDb {
  TestDb(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {},
        onUpgrade: (m, from, to) async {},
      );
}
