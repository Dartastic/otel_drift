// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:otel_drift/otel_drift.dart';

Future<void> main() async {
  await OTel.initialize(serviceName: 'otel-drift-example');

  // Auto-instrumentation: wrap the QueryExecutor you open your
  // database with. Every statement drift runs (select / insert /
  // update / delete / custom / batch, plus transaction commit and
  // rollback) gets a CLIENT span. In a real app:
  //
  //   class AppDatabase extends _$AppDatabase {
  //     AppDatabase(File file)
  //         : super(NativeDatabase.createInBackground(file)
  //               .interceptWith(OTelDriftInterceptor()));
  //   }
  //
  // Pass captureQueryText: true to also record `db.query.text`
  // (off by default: statements can embed sensitive literals).
  final executor =
      NativeDatabase.memory().interceptWith(OTelDriftInterceptor());
  await executor.close();

  // Call-site helper: label spans with the *intent* (operation +
  // table) around a DAO call. Complements the interceptor's
  // statement-level spans.
  final names = await tracedDriftQuery<List<String>>(
    operation: 'select',
    table: 'users',
    // In a real app: () => db.select(db.users).get()
    invoke: () async => ['alice', 'bob'],
  );
  assert(names.length == 2);

  // Group multiple statements under one logical span.
  await tracedDriftTransaction<void>(() async {
    // await db.into(db.users).insert(...);
    // await db.into(db.orders).insert(...);
  });

  // Suppress instrumentation for a scope (e.g. noisy polling).
  await runWithoutDriftInstrumentationAsync(() async {
    // Queries in here emit no spans.
  });

  await OTel.shutdown();
}
