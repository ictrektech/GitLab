# Database Lab with postgresai

For CLI usage, see the [`postgresai` skill](../../postgresai/SKILL.md). For plan links, see
[Console plan links](../../postgresai/references/advanced.md#console-plan-links).

## Find IDs with enough data

Start with the
[well-known IDs](../../../../doc/development/database_review.md#query-plans). Feature
tables often have no rows for them, so check first.

Prefer the candidate with the most rows over one ID that covers every code branch. You can use a
different ID for each query. To check a candidate, run `joe explain` on the real query and compare
`actual ... rows=N` across candidates.

## No production data yet

When a new feature has no rows in production, use one of these options:

- Seed the clone with `joe exec "INSERT ..."` or `joe exec "UPDATE ..."` (and
  `ALTER TABLE ... ADD COLUMN` for new columns), run `ANALYZE <table>`, then explain. Run
  `joe reset` when done.
- Run `EXPLAIN (ANALYZE, BUFFERS)` on a seeded local GDK and share the result through
  `explain.depesz.com` or `explain.dalibo.com`, pasting both the plan and the query.

In the MR, say which option you used.
