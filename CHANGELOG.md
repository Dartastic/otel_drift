# Changelog

## [0.1.0-beta.1] - 2026-05-13

### Added

- `tracedDriftQuery<R>({operation, table, sql, invoke})` —
  generic helper that opens a CLIENT span with `db.system=sqlite`
  and `db.drift=true` around a drift query. Wrap individual
  DAO calls or your data-layer methods to surface query timings.
- `tracedDriftTransaction<R>(body)` — convenience for
  `tracedDriftQuery(operation: 'transaction', invoke: body)`.
- Why not an interceptor? drift goes through code-generated
  DAOs and doesn't expose a per-query hook; wrapping at the
  call site is the most portable instrumentation point.
- Zone-scoped suppression
  (`runWithoutDriftInstrumentation` / async variant).
- 4 tests via the generic helper.
