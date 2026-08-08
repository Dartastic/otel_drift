# Changelog

## [0.2.0-wip]

### Changed

- Semantic conventions updated to the current OTel registry: deprecated
  attribute keys are no longer emitted (`db.system` -> `db.system.name`,
  `db.operation` -> `db.operation.name`). The non-registry `db.drift`
  marker attribute was dropped; the instrumentation scope name
  (`otel_drift`) already identifies the source.
- Dependency floors raised to `dartastic_opentelemetry ^1.1.0-beta.12` and
  `dartastic_opentelemetry_api ^1.0.0-rc.1`. The previous floors declared
  compatibility with API versions that predate the semconv enums this
  package uses and could not actually resolve-and-compile.
- `drift` floor raised to `^2.14.0`, the release that introduced the
  `QueryInterceptor` API.
- `repository` URL corrected to the canonical `Dartastic` org casing so
  pub.dev repository verification succeeds.

### Added

- `OTelDriftInterceptor` — a drift `QueryInterceptor` that opens a
  CLIENT span around every statement drift executes (select / insert /
  update / delete / custom / batch, plus transaction commit and
  rollback), with `db.system.name=sqlite`, `db.operation.name`,
  `db.operation.batch.size` on batches, and opt-in `db.query.text`
  (`captureQueryText: true`; off by default because statements can
  embed sensitive literals). Apply with
  `executor.interceptWith(OTelDriftInterceptor())`.
- `tracedDriftQuery<R>({operation, table, sql, invoke})` —
  call-site helper that opens a CLIENT span labelled with the *intent*
  (operation + table, `db.collection.name`) around a DAO call.
- `tracedDriftTransaction<R>(body)` — convenience for
  `tracedDriftQuery(operation: 'transaction', invoke: body)`.
- Zone-scoped suppression
  (`runWithoutDriftInstrumentation` / async variant), honored by both
  the interceptor and the helpers.
- Tests: interceptor asserted through drift's real `interceptWith`
  wiring against a fake `QueryExecutor` (delegation, attributes,
  batch size, commit, error status, suppression) plus the helper
  suite. An `example/` was added.
