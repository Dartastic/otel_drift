// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:drift/drift.dart';

import 'drift_suppression.dart';

const _tracerName = 'otel_drift';
const _dbSystem = 'sqlite';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

/// Shared span wrapper: opens a CLIENT span named
/// `drift <operation> [<table>]`, runs [invoke], and flips the span to
/// Error on exception.
Future<R> _traced<R>({
  required String operation,
  String? table,
  String? queryText,
  int? batchSize,
  required Future<R> Function() invoke,
}) async {
  if (driftInstrumentationSuppressed()) return invoke();
  final name = table != null ? 'drift $operation $table' : 'drift $operation';
  final span = _tracer().startSpan(
    name,
    kind: SpanKind.client,
    attributes: OTel.attributesFromMap(<String, Object>{
      Db.dbSystemName.key: _dbSystem,
      Db.dbOperationName.key: operation,
      if (table != null) Db.dbCollectionName.key: table,
      if (queryText != null) Db.dbQueryText.key: queryText,
      if (batchSize != null) Db.dbOperationBatchSize.key: batchSize,
    }),
  );
  try {
    return await invoke();
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorAttributes.errorType.key,
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

/// Generic helper for instrumenting a drift call site. Opens a CLIENT
/// span named `drift <operation> [<table>]`, runs [invoke], and
/// flips the span to Error on exception.
///
/// Prefer [OTelDriftInterceptor] for automatic statement-level
/// instrumentation. This helper complements it at the call site,
/// where you can label spans with the *intent* (which table, which
/// operation) rather than the generated SQL:
///
/// ```dart
/// final user = await tracedDriftQuery<User>(
///   operation: 'select',
///   table: 'users',
///   invoke: () => (db.select(db.users)..where((u) => u.id.equals(id)))
///       .getSingle(),
/// );
/// ```
Future<R> tracedDriftQuery<R>({
  required String operation,
  String? table,
  String? sql,
  required Future<R> Function() invoke,
}) {
  return _traced(
    operation: operation,
    table: table,
    queryText: sql,
    invoke: invoke,
  );
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

/// A drift [QueryInterceptor] that opens a CLIENT span around every
/// statement drift executes (select / insert / update / delete /
/// custom / batch, plus transaction commit and rollback).
///
/// Wrap the [QueryExecutor] you open the database with:
///
/// ```dart
/// AppDatabase(
///   NativeDatabase.createInBackground(file)
///       .interceptWith(OTelDriftInterceptor()),
/// );
/// ```
///
/// Spans are named `drift <operation>` and carry `db.system.name`,
/// `db.operation.name`, `db.operation.batch.size` (for batches) and,
/// only when [captureQueryText] is enabled, `db.query.text`.
///
/// Suppression via `runWithoutDriftInstrumentation` /
/// `runWithoutDriftInstrumentationAsync` is honored.
class OTelDriftInterceptor extends QueryInterceptor {
  /// Creates an interceptor. [captureQueryText] is off by default.
  OTelDriftInterceptor({this.captureQueryText = false});

  /// Whether to record the SQL statement as `db.query.text`.
  ///
  /// Off by default: statements can embed literal values, which may
  /// contain sensitive data.
  final bool captureQueryText;

  String? _text(String statement) => captureQueryText ? statement : null;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _traced(
      operation: 'select',
      queryText: _text(statement),
      invoke: () => executor.runSelect(statement, args),
    );
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _traced(
      operation: 'insert',
      queryText: _text(statement),
      invoke: () => executor.runInsert(statement, args),
    );
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _traced(
      operation: 'update',
      queryText: _text(statement),
      invoke: () => executor.runUpdate(statement, args),
    );
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _traced(
      operation: 'delete',
      queryText: _text(statement),
      invoke: () => executor.runDelete(statement, args),
    );
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    return _traced(
      operation: 'custom',
      queryText: _text(statement),
      invoke: () => executor.runCustom(statement, args),
    );
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    return _traced(
      operation: 'batch',
      batchSize: statements.arguments.length,
      invoke: () => executor.runBatched(statements),
    );
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    return _traced(operation: 'commit', invoke: inner.send);
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) {
    return _traced(operation: 'rollback', invoke: inner.rollback);
  }
}
