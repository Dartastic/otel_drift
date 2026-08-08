# otel_drift

OpenTelemetry instrumentation for
[`package:drift`](https://pub.dev/packages/drift).

## Auto-instrumentation

Wrap the `QueryExecutor` you open your database with (drift >= 2.14):

```dart
class AppDatabase extends _$AppDatabase {
  AppDatabase(File file)
      : super(NativeDatabase.createInBackground(file)
            .interceptWith(OTelDriftInterceptor()));
}
```

Every statement drift runs — select / insert / update / delete /
custom / batch, plus transaction commit and rollback — gets a CLIENT
span:

- name: `drift <operation>`
- `db.system.name = sqlite`, `db.operation.name = <operation>`
- `db.operation.batch.size` on batches
- `db.query.text` only with `OTelDriftInterceptor(captureQueryText:
  true)` — off by default, statements can embed sensitive literals

## Call-site helpers

For spans labelled with the *intent* (which table, which operation)
rather than the generated SQL, wrap DAO calls:

```dart
final user = await tracedDriftQuery<User>(
  operation: 'select',
  table: 'users',
  invoke: () => (db.select(db.users)..where((u) => u.id.equals(id)))
      .getSingle(),
);

await tracedDriftTransaction(() async {
  await db.into(db.users).insert(...);
  await db.into(db.orders).insert(...);
});
```

These add `db.collection.name = <table>` and name the span
`drift <operation> <table>`.

Suppression: `runWithoutDriftInstrumentation` /
`runWithoutDriftInstrumentationAsync`.

## License

Apache 2.0
