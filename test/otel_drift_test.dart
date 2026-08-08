// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:drift/drift.dart';
import 'package:otel_drift/otel_drift.dart';
import 'package:test/test.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;

  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

/// In-memory [QueryExecutor] fake: records calls, returns canned
/// results, and can be armed to throw on the next statement.
class _FakeExecutor extends QueryExecutor {
  final List<String> calls = [];
  bool failNext = false;

  void _record(String call) {
    calls.add(call);
    if (failNext) {
      failNext = false;
      throw StateError('database is locked');
    }
  }

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) async {
    _record('select');
    return const [
      {'n': 1},
    ];
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    _record('insert');
    return 1;
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async {
    _record('update');
    return 1;
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) async {
    _record('delete');
    return 1;
  }

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {
    _record('custom');
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    _record('batch');
  }

  @override
  TransactionExecutor beginTransaction() => _FakeTransactionExecutor();

  @override
  QueryExecutor beginExclusive() => this;
}

class _FakeTransactionExecutor extends _FakeExecutor
    implements TransactionExecutor {
  @override
  bool get supportsNestedTransactions => false;

  @override
  Future<void> send() async {
    calls.add('send');
  }

  @override
  Future<void> rollback() async {
    calls.add('rollback');
  }
}

Map<String, Object> _attrs(Span span) =>
    {for (final a in span.attributes.toList()) a.key: a.value};

void main() {
  late _MemorySpanExporter exporter;

  setUp(() async {
    await OTel.reset();
    exporter = _MemorySpanExporter();
    await OTel.initialize(
      serviceName: 'drift-otel-test',
      detectPlatformResources: false,
      spanProcessor: SimpleSpanProcessor(exporter),
    );
  });

  tearDown(() async {
    await OTel.shutdown();
    await OTel.reset();
  });

  group('tracedDriftQuery', () {
    test('emits CLIENT span with db.* attrs', () async {
      await tracedDriftQuery<int>(
        operation: 'select',
        table: 'users',
        invoke: () async => 1,
      );

      final span = exporter.spans.single;
      expect(span.kind, equals(SpanKind.client));
      expect(span.name, equals('drift select users'));
      final attrs = _attrs(span);
      expect(attrs['db.system.name'], equals('sqlite'));
      expect(attrs['db.operation.name'], equals('select'));
      expect(attrs['db.collection.name'], equals('users'));
    });

    test('tracedDriftTransaction emits a transaction span', () async {
      await tracedDriftTransaction<void>(() async {});
      final span = exporter.spans.single;
      expect(_attrs(span)['db.operation.name'], equals('transaction'));
    });

    test('exception flips span to Error', () async {
      await expectLater(
        tracedDriftQuery<void>(
          operation: 'insert',
          table: 't',
          invoke: () async => throw StateError('locked'),
        ),
        throwsStateError,
      );
      final span = exporter.spans.single;
      expect(span.status, equals(SpanStatusCode.Error));
    });

    test('runWithoutDriftInstrumentationAsync bypasses spans', () async {
      await runWithoutDriftInstrumentationAsync(() async {
        await tracedDriftQuery<int>(
          operation: 'select',
          table: 'users',
          invoke: () async => 1,
        );
      });
      expect(exporter.spans, isEmpty);
    });
  });

  group('OTelDriftInterceptor', () {
    late _FakeExecutor inner;

    setUp(() {
      inner = _FakeExecutor();
    });

    test('runSelect delegates and emits a CLIENT span', () async {
      final executor = inner.interceptWith(OTelDriftInterceptor());
      final rows = await executor.runSelect('SELECT n FROM t', []);

      expect(rows.single['n'], equals(1));
      expect(inner.calls, equals(['select']));

      final span = exporter.spans.single;
      expect(span.kind, equals(SpanKind.client));
      expect(span.name, equals('drift select'));
      final attrs = _attrs(span);
      expect(attrs['db.system.name'], equals('sqlite'));
      expect(attrs['db.operation.name'], equals('select'));
      expect(
        attrs.containsKey('db.query.text'),
        isFalse,
        reason: 'query text capture is opt-in',
      );
    });

    test('captureQueryText records db.query.text', () async {
      final executor =
          inner.interceptWith(OTelDriftInterceptor(captureQueryText: true));
      await executor.runInsert('INSERT INTO t (n) VALUES (?)', [1]);

      final attrs = _attrs(exporter.spans.single);
      expect(attrs['db.operation.name'], equals('insert'));
      expect(attrs['db.query.text'], equals('INSERT INTO t (n) VALUES (?)'));
    });

    test('runBatched records db.operation.batch.size', () async {
      final executor = inner.interceptWith(OTelDriftInterceptor());
      await executor.runBatched(
        BatchedStatements(
          ['INSERT INTO t (n) VALUES (?)'],
          [
            ArgumentsForBatchedStatement(0, [1]),
            ArgumentsForBatchedStatement(0, [2]),
          ],
        ),
      );

      expect(inner.calls, equals(['batch']));
      final attrs = _attrs(exporter.spans.single);
      expect(attrs['db.operation.name'], equals('batch'));
      expect(attrs['db.operation.batch.size'], equals(2));
    });

    test('transaction commit emits a commit span', () async {
      final executor = inner.interceptWith(OTelDriftInterceptor());
      final tx = executor.beginTransaction();
      await tx.runUpdate('UPDATE t SET n = 1', []);
      await tx.send();

      final names = exporter.spans.map((s) => s.name).toList();
      expect(names, equals(['drift update', 'drift commit']));
    });

    test('executor failure flips span to Error and rethrows', () async {
      final executor = inner.interceptWith(OTelDriftInterceptor());
      inner.failNext = true;

      await expectLater(
        executor.runDelete('DELETE FROM t', []),
        throwsStateError,
      );

      final span = exporter.spans.single;
      expect(span.status, equals(SpanStatusCode.Error));
      expect(_attrs(span)['error.type'], equals('StateError'));
    });

    test('suppression bypasses interceptor spans but still delegates',
        () async {
      final executor = inner.interceptWith(OTelDriftInterceptor());
      await runWithoutDriftInstrumentationAsync(() async {
        await executor.runSelect('SELECT n FROM t', []);
      });

      expect(inner.calls, equals(['select']));
      expect(exporter.spans, isEmpty);
    });
  });
}
