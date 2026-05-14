// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'drift_suppression.dart';

const _tracerName = 'otel_drift';
const _dbSystem = 'sqlite';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Generic helper for instrumenting a drift query. Opens a CLIENT
/// span named `drift <operation> [<table>]`, runs [invoke], and
/// flips the span to Error on exception.
///
/// drift doesn't expose a generic Interceptor hook (queries go
/// through code-generated DAOs), so the most ergonomic way to
/// instrument is to wrap individual call sites:
///
/// ```dart
/// final user = await tracedDriftQuery<User>(
///   operation: 'select',
///   table: 'users',
///   invoke: () => (db.select(db.users)..where((u) => u.id.equals(id)))
///       .getSingle(),
/// );
/// ```
///
/// For broader instrumentation, write a wrapper class around your
/// DAO methods that delegates to this helper.
Future<R> tracedDriftQuery<R>({
  required String operation,
  String? table,
  String? sql,
  required Future<R> Function() invoke,
}) async {
  if (driftInstrumentationSuppressed()) return invoke();
  final name = table != null ? 'drift $operation $table' : 'drift $operation';
  final span = _tracer().startSpan(
    name,
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(<String, Object>{
      Database.dbSystem.key: _dbSystem,
      Database.dbSystemName.key: _dbSystem,
      Database.dbOperation.key: operation,
      Database.dbOperationName.key: operation,
      if (table != null) Database.dbCollectionName.key: table,
      if (sql != null) Database.dbQueryText.key: sql,
      'db.drift': true,
    }),
  );
  try {
    return await invoke();
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Convenience helper for transactions.
Future<R> tracedDriftTransaction<R>(
  Future<R> Function() body,
) {
  return tracedDriftQuery<R>(
    operation: 'transaction',
    invoke: body,
  );
}
