# dartastic_drift_otel

OpenTelemetry instrumentation for
[`package:drift`](https://pub.dev/packages/drift).

```dart
final user = await tracedDriftQuery<User>(
  operation: 'select',
  table: 'users',
  invoke: () => (db.select(db.users)..where((u) => u.id.equals(id)))
      .getSingle(),
);

final id = await tracedDriftQuery<int>(
  operation: 'insert',
  table: 'users',
  invoke: () => db.into(db.users).insert(UsersCompanion.insert(name: 'Alice')),
);

await tracedDriftTransaction(() async {
  await db.into(db.users).insert(...);
  await db.into(db.orders).insert(...);
});
```

Each call opens a CLIENT span:
- name: `drift <op> [<table>]`
- `db.system = sqlite`, `db.operation = <op>`,
  `db.collection.name = <table>`, `db.drift = true`

## Why not an interceptor?

drift goes through code-generated DAOs and doesn't expose a
per-query interceptor hook. Wrapping at the call site (or in
your data-layer methods) is the most portable point of
instrumentation — and lets you label spans with the *intent*
(`select users by id`) rather than the generated SQL.

Suppression: `runWithoutDriftInstrumentationAsync`.

## License

Apache 2.0
