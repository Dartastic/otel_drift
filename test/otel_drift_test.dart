// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
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

Map<String, Object> _attrs(Span span) =>
    {for (final a in span.attributes.toList()) a.key: a.value};

void main() {
  group('tracedDriftQuery', () {
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

    test('emits CLIENT span with db.* + drift attrs', () async {
      await tracedDriftQuery<int>(
        operation: 'select',
        table: 'users',
        invoke: () async => 1,
      );

      final span = exporter.spans.single;
      expect(span.kind, equals(SpanKind.client));
      expect(span.name, equals('drift select users'));
      final attrs = _attrs(span);
      expect(attrs['db.system'], equals('sqlite'));
      expect(attrs['db.operation'], equals('select'));
      expect(attrs['db.collection.name'], equals('users'));
      expect(attrs['db.drift'], equals(true));
    });

    test('tracedDriftTransaction emits a transaction span', () async {
      await tracedDriftTransaction<void>(() async {});
      final span = exporter.spans.single;
      expect(_attrs(span)['db.operation'], equals('transaction'));
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
}
