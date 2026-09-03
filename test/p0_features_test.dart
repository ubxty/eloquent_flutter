/// End-to-end P0 feature tests for eloquent_flutter.
///
/// Covers every P0 feature the integration added:
///   * $casts (int/datetime/json)
///   * isDirty / wasChanged
///   * SoftDeletes (delete / withTrashed / forceDelete / restore)
///   * whereHas / has / withCount
///   * saveQuietly
///   * pluck / value / sole
///   * aggregates (min/max/avg/sum)
///   * firstOrCreate / updateOrCreate
///   * WithTimestamps (created_at/updated_at auto-populate)
// ignore_for_file: prefer_const_constructors
library;

import 'package:drift/drift.dart' show TableInfo;
import 'package:drift/native.dart';
import 'package:eloquent_flutter/eloquent_flutter.dart';
import 'package:eloquent_flutter/src/test_support/test_db.dart';
import 'package:test/test.dart';

// =============================================================================
// Models.
// =============================================================================

/// Widget model — exercises $casts (int/datetime/json), SoftDeletes,
/// WithTimestamps.
class Widget extends Model<Widget, WidgetRow>
    with SoftDeletes<Widget, WidgetRow>, WithTimestamps {
  Widget(super.data);

  @override
  TableInfo<Widgets, WidgetRow> get $table => TestRegistry.widgets;

  @override
  Widget $wrap(WidgetRow data) => Widget(data);

  @override
  Map<String, dynamic> toMap() => {
        'id': $data.id,
        'name': $data.name,
        'meta': $data.meta,
        'stock': $data.stock,
        'deleted_at': $data.deletedAt,
        'created_at': $data.createdAt,
        'updated_at': $data.updatedAt,
      };

  @override
  Map<String, String> get $casts => {
        'stock': CastType.integer,
        'deleted_at': CastType.dateTime,
        'created_at': CastType.dateTime,
        'updated_at': CastType.dateTime,
        'meta': CastType.json,
      };

  @override
  Map<String, Relationship<dynamic>> get $relations => {
        'comments': HasMany<Comment, CommentRow>(
          local: this,
          relatedTable: TestRegistry.comments,
          foreignKey: 'widget_id',
          creator: Comment.new,
        ),
      };

  // WithTimestamps mixin wants these three abstract members.
  @override
  Model get model => this;
  @override
  Map<String, dynamic> get modelMap => toMap();
  @override
  Future<void> persistTimestamps() async => refresh();

  // ---- Forwarding statics ----
  static final _q = ModelQuery<Widget, WidgetRow>(
    table: TestRegistry.widgets,
    creator: Widget.new,
    casts: {
      'stock': CastType.integer,
      'meta': CastType.json,
      'deleted_at': CastType.dateTime,
      'created_at': CastType.dateTime,
      'updated_at': CastType.dateTime,
    },
  );

  static Future<List<Widget>> all() => _q.all();
  static Future<Widget?> find(Object id) => _q.find(id);
  static Future<Widget> findOrFail(Object id) => _q.findOrFail(id);
  static Future<Widget> create(Map<String, dynamic> values) => _q.create(values);
  static Future<List<Widget>> withTrashed() => _q.withTrashed().get();
  static QueryBuilder<Widget, WidgetRow> where(
    String c, [
    Object? v,
    String op = '=',
  ]) =>
      _q.where(c, v, op);
  static QueryBuilder<Widget, WidgetRow> query() => _q.query();
  static Future<Widget> firstOrCreate(
    Map<String, dynamic> a, [
    Map<String, dynamic> c = const {},
  ]) =>
      _q.firstOrCreate(a, c);
  static Future<Widget> firstOrNew(
    Map<String, dynamic> a, [
    Map<String, dynamic> c = const {},
  ]) =>
      _q.firstOrNew(a, c);
  static Future<Widget> updateOrCreate(
    Map<String, dynamic> a,
    Map<String, dynamic> v,
  ) =>
      _q.updateOrCreate(a, v);
  static Future<int> upsert(
    List<Map<String, dynamic>> rows, [
    List<String> uniqueBy = const [],
  ]) =>
      _q.upsert(rows, uniqueBy);
  static Stream<List<Widget>> watch() => _q.watch();
}

/// HasMany target.
class Comment extends Model<Comment, CommentRow> {
  Comment(super.data);

  @override
  TableInfo<Comments, CommentRow> get $table => TestRegistry.comments;

  @override
  Comment $wrap(CommentRow data) => Comment(data);

  @override
  Map<String, dynamic> toMap() => {
        'id': $data.id,
        'widget_id': $data.widgetId,
        'body': $data.body,
      };
}

/// Registry the models use to resolve their tables.
class TestRegistry {
  static TestDb? _db;
  static void init(TestDb db) => _db = db;
  static void shutdown() => _db = null;
  static TestDb get _instance =>
      _db ?? (throw StateError('TestRegistry.init(db) must be called first.'));

  /// Public accessor for tests that need to issue raw drift statements
  /// directly (e.g. fixtures inside setUp).
  static TestDb get db => _instance;
  static TableInfo<Widgets, WidgetRow> get widgets => _instance.widgets;
  static TableInfo<Comments, CommentRow> get comments => _instance.comments;
}

/// Subclass that lets the test inject an observer for saveQuietly.
class ObservableWidget extends Widget {
  ObservableWidget(super.data);
  ObserverSet? _obs;
  void attachObserver(ObserverSet o) => _obs = o;
  @override
  ObserverSet get $observers => _obs ?? super.$observers;

  @override
  ObservableWidget $wrap(WidgetRow data) => ObservableWidget(data);

  @override
  ObservableWidget wrap(WidgetRow data) => $wrap(data);
}

// =============================================================================
// Helpers.
// =============================================================================

Future<TestDb> _bootstrap() async {
  final db = TestDb(NativeDatabase.memory());
  Eloquent.init(db);
  TestRegistry.init(db);
  await Schema.create('widgets', (t) {
    t.id();
    t.string('name');
    t.text('meta').nullable_();
    t.integer('stock').default_(0);
    t.dateTime('deleted_at').nullable_();
    t.timestamps();
  });
  await Schema.create('comments', (t) {
    t.id();
    t.integer('widget_id');
    t.text('body');
  });
  return db;
}

Future<void> _teardown() async {
  await Eloquent.dispose();
  TestRegistry._db = null;
}

QueryBuilder<Widget, WidgetRow> _widgetQuery() => QueryBuilder<Widget, WidgetRow>(
      table: TestRegistry.widgets,
      creator: Widget.new,
      relations: {
        'comments': RelationSpec(
          relatedTable: TestRegistry.comments,
          foreignKey: 'widget_id',
        ),
      },
    );

// =============================================================================
// Tests.
// =============================================================================

void main() {
  setUp(() async {
    await _bootstrap();
  });

  tearDown(() async {
    await _teardown();
  });

  group(r'$casts', () {
    test('int / json casts work', () async {
      final w = await Widget.create({
        'name': 'A',
        'stock': '42', // int cast accepts a String
        'meta': '{"theme":"dark"}',
      });

      expect(w.getAttribute('stock'), 42);
      expect(w.getAttribute('name'), 'A');
      final meta = w.getAttribute('meta') as Map<String, dynamic>;
      expect(meta['theme'], 'dark');
    });
  });

  group('isDirty + wasChanged', () {
    test('setAttribute marks dirty; save() clears it; wasChanged works',
        () async {
      final w = await Widget.create({'name': 'a', 'stock': 0});
      expect(w.isDirty(), false);
      expect(w.wasChanged(), false);

      w.setAttribute('name', 'b');
      expect(w.isDirty(), true);
      expect(w.isDirty('name'), true);
      expect(w.wasChanged('name'), true);

      await w.save();

      expect(w.isDirty(), false);
      // wasChanged sticks until next snapshot.
      expect(w.wasChanged(), true);
      await w.refresh();
      expect(w.wasChanged(), false);
    });
  });

  group('SoftDeletes', () {
    test('delete() sets deleted_at; withTrashed() returns it; forceDelete() removes',
        () async {
      final w = await Widget.create({'name': 'trash-me', 'stock': 1});

      await w.delete();
      await w.refresh();
      expect(w.trashed, true);
      expect(w.toMap()['deleted_at'], isNotNull);

      final all = await Widget.all();
      expect(all.length, 0);

      final withTrashed = await Widget.withTrashed();
      expect(withTrashed.length, 1);

      await w.forceDelete();
      final after = await Widget.withTrashed();
      expect(after.length, 0);
    });

    test('restore() un-deletes', () async {
      final w = await Widget.create({'name': 'restore', 'stock': 1});
      await w.delete();
      await w.refresh();
      expect(w.trashed, true);

      await w.restore();
      expect(w.trashed, false);

      final live = await Widget.all();
      expect(live.length, 1);
    });
  });

  group('whereHas / withCount', () {
    setUp(() async {
      // Two widgets, one of them has a comment.
      await Widget.create({'name': 'with-comment', 'stock': 1});
      await Widget.create({'name': 'no-comment', 'stock': 1});
      final ws = await Widget.all();
      final w =
          ws.firstWhere((x) => x.toMap()['name'] == 'with-comment');
      await TestRegistry._instance.into(TestRegistry.comments).insert(
            CommentsCompanion.insert(
              widgetId: w.toMap()['id'] as int,
              body: 'hi',
            ),
          );
    });

    test('whereHas returns only widgets that have comments', () async {
      final rows = await _widgetQuery().whereHas('comments').get();
      expect(rows.length, 1);
      expect(rows.first.toMap()['name'], 'with-comment');
    });

    test('withCount attaches comments_count per row', () async {
      final rows = await _widgetQuery().withCount('comments').get();
      expect(rows.length, 2);
      final byName = {for (final r in rows) r.toMap()['name'] as String: r};
      expect(byName['with-comment']!.getLoaded('comments_count'), 1);
      expect(byName['no-comment']!.getLoaded('comments_count'), 0);
    });
  });

  group('saveQuietly', () {
    test('saveQuietly() does not fire observers', () async {
      var fired = 0;
      final original = await Widget.create({'name': 'q', 'stock': 1});
      // Re-wrap the existing row using the same subclass constructor.
      // Mark `$exists` true so `save()` takes the UPDATE path; otherwise
      // it would try to INSERT id=1 again (violates unique constraint).
      final obs = ObservableWidget(original.$data);
      obs.$exists = true;
      obs.attachObserver(
        ObserverSet(
          updated: (_) => fired++,
        ),
      );
      obs.setAttribute('name', 'z');
      await obs.saveQuietly();
      expect(fired, 0); // updated did NOT fire

      await obs.save();
      expect(fired, 1); // updated DID fire
    });
  });

  group('pluck / value / sole', () {
    setUp(() async {
      await Widget.create({'name': 'one', 'stock': 10});
      await Widget.create({'name': 'two', 'stock': 20});
      await Widget.create({'name': 'three', 'stock': 30});
    });

    test('pluck returns a list of values', () async {
      final names = await _widgetQuery().pluck('name') as List<dynamic>;
      expect(names, containsAll(['one', 'two', 'three']));
    });

    test('pluck with key returns a map<key, model>', () async {
      final m = await _widgetQuery().pluck('name', 'id') as Map<dynamic, Widget>;
      expect(m.length, 3);
    });

    test('value returns the first matching row\'s column value', () async {
      final q = _widgetQuery()..orderBy('id');
      final v = await q.value('name');
      expect(v, 'one');
    });

    test('sole throws on 0 or 2+', () async {
      await expectLater(_widgetQuery().sole(),
          throwsA(isA<MultipleRecordsFoundException>()));

      final only = await (_widgetQuery()..where('name', 'one')).sole();
      expect(only.toMap()['name'], 'one');

      await expectLater(
        (_widgetQuery()..where('name', 'nope')).sole(),
        throwsA(isA<ModelNotFoundException>()),
      );
    });
  });

  group('aggregates (min/max/avg/sum)', () {
    setUp(() async {
      await Widget.create({'name': 'a', 'stock': 10});
      await Widget.create({'name': 'b', 'stock': 20});
      await Widget.create({'name': 'c', 'stock': 30});
    });

    test('min returns the smallest value', () async {
      expect(await _widgetQuery().min('stock'), 10);
    });

    test('max returns the largest value', () async {
      expect(await _widgetQuery().max('stock'), 30);
    });

    test('avg returns the arithmetic mean', () async {
      expect(await _widgetQuery().avg('stock'), closeTo(20.0, 0.001));
    });

    test('sum returns the total', () async {
      expect(await _widgetQuery().sum('stock'), 60);
    });

    test('soft-deleted rows are excluded from aggregates', () async {
      // Soft-delete the middle row — it should drop out of every
      // aggregate. The remaining rows are stock=10 and stock=30.
      final all = await Widget.all();
      final middle = all.firstWhere((w) => w.toMap()['stock'] == 20);
      await middle.delete();

      expect(await _widgetQuery().min('stock'), 10);
      expect(await _widgetQuery().max('stock'), 30);
      expect(await _widgetQuery().sum('stock'), 40);
      expect(await _widgetQuery().avg('stock'), closeTo(20.0, 0.001));

      // withTrashed restores the deleted row to the aggregate set.
      final q = _widgetQuery()..withTrashed();
      expect(await q.min('stock'), 10);
      expect(await q.max('stock'), 30);
      expect(await q.sum('stock'), 60);
      expect(await q.avg('stock'), closeTo(20.0, 0.001));
    });
  });

  group('firstOrCreate / updateOrCreate', () {
    test('firstOrCreate is idempotent', () async {
      final w1 = await Widget.firstOrCreate({'name': 'unique'});
      final w2 = await Widget.firstOrCreate({'name': 'unique'});
      expect(w1.toMap()['id'], w2.toMap()['id']);
      final all = await Widget.all();
      expect(all.length, 1);
    });

    test('updateOrCreate updates existing, creates new', () async {
      final w1 = await Widget.updateOrCreate({'name': 'first'}, {'stock': 100});
      expect(w1.toMap()['stock'], 100);

      final w2 = await Widget.updateOrCreate({'name': 'first'}, {'stock': 200});
      expect(w2.toMap()['id'], w1.toMap()['id']);
      expect(w2.toMap()['stock'], 200);

      final w3 = await Widget.updateOrCreate({'name': 'second'}, {'stock': 50});
      expect(w3.toMap()['id'], isNot(w1.toMap()['id']));
      expect(w3.toMap()['stock'], 50);

      final all = await Widget.all();
      expect(all.length, 2);
    });
  });

  group('WithTimestamps', () {
    test('save() populates created_at and updated_at', () async {
      // Fresh WidgetRow — id=0 means "autoincrement placeholder".
      final fresh = Widget(
        WidgetRow(
          id: 0,
          name: 'ts',
          meta: null,
          stock: 1,
          deletedAt: null,
          createdAt: null,
          updatedAt: null,
        ),
      );
      expect(fresh.$primaryKeyValue, 0);
      final before = DateTime.now();
      await fresh.save();
      final after = DateTime.now();

      // Refresh from DB to read back what drift actually wrote.
      await fresh.refresh();

      final created = fresh.toMap()['created_at'] as DateTime;
      final updated = fresh.toMap()['updated_at'] as DateTime;
      expect(
        !created.isBefore(before.subtract(const Duration(seconds: 1))),
        true,
      );
      expect(!created.isAfter(after.add(const Duration(seconds: 1))), true);
      expect(!updated.isBefore(before.subtract(const Duration(seconds: 1))),
          true);
    });
  });
}
