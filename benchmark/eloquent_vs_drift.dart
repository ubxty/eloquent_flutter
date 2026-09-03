/// Head-to-head benchmarks: `eloquent_flutter` vs raw `drift`.
///
/// Measures wall-clock time for the same set of operations executed via
/// the wrapper and via drift's bare API. Used to assert that the wrapper
/// stays within an acceptable overhead budget. The two measurements per
/// pair are:
///
///   1. The **full** operation (what the user actually does): for the
///      wrapper that includes any post-insert reads required to populate
///      auto-increment / default values; for raw drift we add the same
///      read so the comparison is apples-to-apples.
///
///   2. The **minimum** raw drift call (no read-back) for reference —
///      this is the lower bound the wrapper could ever reach.
///
/// Run with `dart run benchmark/eloquent_vs_drift.dart` from the
/// package root. The output is plain text — easy to grep and diff
/// between runs.
// ignore_for_file: prefer_const_constructors, avoid_relative_lib_imports
// `tool/` is not a published location; the schema there is for the
// benchmark + test suite only.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/drift.dart' as d show Value;
import 'package:drift/native.dart';
import 'package:eloquent_flutter/eloquent_flutter.dart';

import '../test/p0_features_test.dart' show Widget, TestRegistry;
import '../tool/test_support/test_db.dart';

// =====================================================================
// Setup — same database + schema as the test suite uses.
// =====================================================================

Future<TestDb> _openDb() async {
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

Future<void> _seed(TestDb db, int n) async {
  await db.batch((b) {
    b.insertAll(
      db.widgets,
      [
        for (var i = 0; i < n; i++)
          WidgetsCompanion.insert(name: 'w$i', stock: d.Value(i)),
      ],
    );
  });
}

// =====================================================================
// Benchmark helpers.
// =====================================================================

typedef OpResult = void;

class _Bench {
  _Bench(this.label, this.iter);

  final String label;
  final int iter;

  Future<Duration> run(Future<OpResult> Function() op) async {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iter; i++) {
      await op();
    }
    sw.stop();
    return sw.elapsed;
  }
}

void _printResult(String name, Duration el, int iter) {
  final us = el.inMicroseconds / iter;
  print('  ${name.padRight(40)}  ${us.toStringAsFixed(2).padLeft(8)} µs/op'
      '  ($iter iters, ${el.inMilliseconds} ms total)');
}

Future<void> _printOverhead(
    String label, Duration w, Duration r, int iter) async {
  final overhead = (w.inMicroseconds / r.inMicroseconds - 1) * 100;
  print('');
  print('  $label');
  _printResult('wrapper', w, iter);
  _printResult('drift (raw)', r, iter);
  print('  ${'overhead'.padRight(40)}  ${overhead.toStringAsFixed(1).padLeft(8)} %');
}

Future<void> _section(String title) async {
  print('');
  print('=' * 72);
  print('  $title');
  print('=' * 72);
}

// =====================================================================
// 1) INSERT — wrapper round-trip vs raw insert + read-back.
// =====================================================================

Future<void> _benchInsert() async {
  await _section('INSERT — 1k iterations');

  final db = await _openDb();

  // Wrapper: Model.create({...}) — round-trips (insert + re-fetch for
  // auto-incremented id + defaults).
  final wrapped = _Bench('eloquent: Widget.create({name, stock})', 1000);
  final wTime = await wrapped.run(() async {
    await Widget.create({'name': 'w', 'stock': 1});
  });

  // Raw drift minimum: just the insert (returns the rowid).
  final rawMin = _Bench('drift min: db.into(...).insert(...)', 1000);
  final rMinTime = await rawMin.run(() async {
    await db.into(db.widgets).insert(
          WidgetsCompanion.insert(name: 'w', stock: d.Value(1)),
        );
  });

  // Raw drift fair: insert + read-back (what the wrapper actually does).
  final rawFair = _Bench('drift fair: insert + select-by-id', 1000);
  final rFairTime = await rawFair.run(() async {
    final id = await db.into(db.widgets).insert(
          WidgetsCompanion.insert(name: 'w', stock: d.Value(1)),
        );
    await (db.select(db.widgets)..where((t) => t.id.equals(id)))
        .getSingle();
  });

  _printOverhead('wrapper vs raw insert (lower bound)', wTime, rMinTime, 1000);
  _printOverhead('wrapper vs raw insert + read-back (fair)',
      wTime, rFairTime, 1000);

  await Eloquent.dispose();
  await db.close();
}

// =====================================================================
// 2) FIND by PK — wrapper vs raw select where.
// =====================================================================

Future<void> _benchFind() async {
  await _section('FIND by primary key — 1k iterations on a 1k-row table');

  final db = await _openDb();
  await _seed(db, 1000);

  // Stable id for the run.
  final sample = await (db.select(db.widgets)..limit(1)).getSingle();
  final id = sample.id;

  // Wrapper: Widget.find(id).
  final wrapped = _Bench('eloquent: Widget.find(id)', 1000);
  final wTime = await wrapped.run(() async {
    await Widget.find(id);
  });

  // Raw drift: select where + getSingleOrNull.
  final raw = _Bench('drift: db.select(...).getSingleOrNull()', 1000);
  final rTime = await raw.run(() async {
    await (db.select(db.widgets)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  });

  _printOverhead('wrapper vs raw', wTime, rTime, 1000);

  await Eloquent.dispose();
  await db.close();
}

// =====================================================================
// 3) WHERE chain — wrapper vs raw where + orderBy + limit.
// =====================================================================

Future<void> _benchWhereChain() async {
  await _section('WHERE + orderBy + limit — 1k iterations on a 1k-row table');

  final db = await _openDb();
  await _seed(db, 1000);

  // Wrapper: rebuild a fresh builder per iteration (the wrapper mutates
  // `this`; the raw drift statement is also a fresh builder per
  // iteration so the comparison stays even).
  final wrapped = _Bench('eloquent: Widget.where().orderBy().limit().get()',
      1000);
  final wTime = await wrapped.run(() async {
    final q = QueryBuilder<Widget, WidgetRow>(
      table: TestRegistry.widgets,
      creator: Widget.new,
    );
    await q.where('stock', 5).orderBy('id').limit(10).get();
  });

  // Raw drift: db.select(...).where().orderBy().limit().get().
  final raw = _Bench(
      'drift:    db.select(...).where().orderBy().limit().get()',
      1000);
  final rTime = await raw.run(() async {
    await (db.select(db.widgets)
          ..where((t) => t.stock.equals(5))
          ..orderBy([(t) => OrderingTerm(expression: t.id)])
          ..limit(10))
        .get();
  });

  _printOverhead('wrapper vs raw', wTime, rTime, 1000);

  await Eloquent.dispose();
  await db.close();
}

// =====================================================================
// 4) ALL rows — wrapper vs raw select.
// =====================================================================

Future<void> _benchAll() async {
  await _section('ALL rows — 100 iterations on a 1k-row table');

  final db = await _openDb();
  await _seed(db, 1000);

  final wrapped = _Bench('eloquent: Widget.all()', 100);
  final wTime = await wrapped.run(() async {
    await Widget.all();
  });

  final raw = _Bench('drift:    db.select(...).get()', 100);
  final rTime = await raw.run(() async {
    await db.select(db.widgets).get();
  });

  _printOverhead('wrapper vs raw', wTime, rTime, 100);

  await Eloquent.dispose();
  await db.close();
}

// =====================================================================
// 5) COUNT(*) — wrapper vs raw customSelect with the same WHERE clause.
// =====================================================================

Future<void> _benchCount() async {
  await _section('COUNT — 1k iterations on a 1k-row table');

  final db = await _seedForCount();

  // Wrapper: QueryBuilder.count() — emits a static
  // `SELECT COUNT(*) ... WHERE "deleted_at" IS NULL` when no user
  // predicates are present, identical to the raw query below.
  final wrapped = _Bench('eloquent: QueryBuilder.count()', 1000);
  final wTime = await wrapped.run(() async {
    await QueryBuilder<Widget, WidgetRow>(
      table: TestRegistry.widgets,
      creator: Widget.new,
    ).count();
  });

  // Raw drift: same SQL — soft-delete predicate included so the
  // comparison is apples-to-apples.
  final raw = _Bench(
      'drift:    customSelect COUNT(*) WHERE deleted_at IS NULL',
      1000);
  final rTime = await raw.run(() async {
    await db.customSelect(
      'SELECT COUNT(*) AS c FROM widgets WHERE "deleted_at" IS NULL',
      readsFrom: {db.widgets},
    ).getSingle();
  });

  _printOverhead('wrapper vs raw', wTime, rTime, 1000);

  await Eloquent.dispose();
  await db.close();
}

Future<TestDb> _seedForCount() async {
  final db = await _openDb();
  await _seed(db, 1000);
  return db;
}

// =====================================================================
// 6) SAVE — wrapper vs raw insert.
// =====================================================================

Future<void> _benchSave() async {
  await _section('SAVE (insert path) — 1k iterations');

  final db = await _openDb();

  // Wrapper: new Widget + save() — insert + re-fetch for autoincrement.
  final wrapped = _Bench('eloquent: new Widget(...).save()', 1000);
  final wTime = await wrapped.run(() async {
    final w = Widget(
      const WidgetRow(
        id: 0,
        name: 'fresh',
        meta: null,
        stock: 1,
        deletedAt: null,
        createdAt: null,
        updatedAt: null,
      ),
    );
    await w.save();
  });

  await Eloquent.dispose();
  await db.close();

  final db2 = await _openDb();

  // Raw drift minimum: just insert.
  final rawMin = _Bench('drift min: db.into(...).insert(...)', 1000);
  final rMinTime = await rawMin.run(() async {
    await db2.into(db2.widgets).insert(
          WidgetsCompanion.insert(name: 'fresh', stock: d.Value(1)),
        );
  });

  _printOverhead('wrapper vs raw insert (lower bound)', wTime, rMinTime, 1000);

  await Eloquent.dispose();
  await db2.close();
}

// =====================================================================
// main
// =====================================================================

Future<void> main() async {
  print('');
  print('eloquent_flutter — wrapper vs raw drift benchmark');
  print('Database : NativeDatabase.memory()');
  print('Platform : ${Platform.operatingSystem}');
  print('Dart     : ${Platform.version}');

  await _benchInsert();
  await _benchFind();
  await _benchWhereChain();
  await _benchAll();
  await _benchCount();
  await _benchSave();

  print('');
  print('=' * 72);
  print('  Summary');
  print('=' * 72);
  print('  Fair-overhead numbers should land well below 50%. The wrapper');
  print('  mostly pays for: (a) one extra SELECT round-trip to populate');
  print('  auto-incremented / defaulted columns after INSERT, and');
  print('  (b) per-instance state (casts, dirty tracking, snapshot).');
  print('');
}
