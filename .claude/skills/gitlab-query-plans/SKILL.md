---
name: gitlab-query-plans
description: Produce the raw SQL and production query plans (Database Lab, building on the postgresai skill) that GitLab database review requires for new or modified queries. Use when an MR adds or changes ActiveRecord queries or scopes, or a reviewer asks for query plans. Requires a local agent session with a running GDK and an authenticated postgresai CLI; it does not work in Duo agent sessions, which have no database or credentials.
---

# GitLab query plans with postgresai

This skill produces the "Raw SQL" and "Query Plans" artifacts for each new or modified query.
For the rules these artifacts must meet, see
[Preparation when adding or modifying queries](../../../doc/development/database_review.md#preparation-when-adding-or-modifying-queries).
Migrations, indexes, and new tables need more artifacts. See
[How to prepare the merge request for a database review](../../../doc/development/database_review.md#how-to-prepare-the-merge-request-for-a-database-review).

## Prerequisites

- Load the `postgresai` skill ([`.claude/skills/postgresai/SKILL.md`](../postgresai/SKILL.md))
  for all CLI operations: install, auth, target selection with
  `postgresai set-default-project <alias>`, `scripts/joe.sh`, budgets, `hypo`, index
  experiments, and safety rules.
- To pick the alias for the table's database, see
  [`postgresai/references/gitlab.md`](../postgresai/references/gitlab.md).
- The default project is global state. When an MR touches tables in more than one database
  (for example `main` and `sec`), pass `--project <alias>` per call instead of flipping the
  default mid-session.

## Workflow

1. **Capture the SQL that Rails runs.** Do not hand-write it. See
   [references/capture-sql.md](references/capture-sql.md).
1. **Pick production IDs with enough data.** Check candidates with `joe explain`
   (`actual rows=N`). See [references/dblab.md](references/dblab.md#find-ids-with-enough-data).
1. **Run `EXPLAIN ANALYZE`** for each statement:

   ```shell
   .claude/skills/postgresai/scripts/joe.sh explain "<sql with literal IDs>"
   ```

   The wrapper (path relative to the repository root) waits out the CLI's poll budget.

   Check the output:

   - **Rows**: the top node returns at least the `LIMIT`, or more than 0 rows when there is no
     `LIMIT`. Batched queries must return a full batch. For `UPDATE` and `DELETE`,
     `ModifyTable` always shows `rows=0`, so read the scan node under it. If there are too
     few rows, go back to step 2.
   - **Timing**: report the first run, which is usually cold (`I/O Timings: read=...`).
     The 100 ms guideline applies to both cold and warm cache, so do not rerun a query just to
     get under it. If you do rerun, label those numbers as warm.
   - **Buffers**: note `shared hit` and `read` on the top node. Reviewers compare buffers, not
     just time.
   - **Index use**: flag any `Seq Scan` on a large table.

   If the query relies on an index the MR adds, create it on the clone with the loop in
   [`postgresai/references/plan-analysis.md`](../postgresai/references/plan-analysis.md#iterating).
   `joe hypo` gives estimates only, so never submit it as the plan. If production has no data
   for the query yet, see [references/dblab.md](references/dblab.md#no-production-data-yet).
1. **Collect plan links** from the console history (currently the CLI can't build them). See
   [`postgresai/references/advanced.md`](../postgresai/references/advanced.md#console-plan-links).
1. **Draft the MR section** from [templates/query-plans.md](templates/query-plans.md).
   Replace literal production IDs in the SQL with placeholders such as `<project_id>` and
   `<namespace_id>`. The real query stays behind the console plan link, which requires a
   postgres.ai session to view.
   For a modified query, include the SQL and plan from before and after the change.
1. **Get approval, then publish.** Show the drafted section to the user. Only after they
   approve, update the MR description and add `~database`:

   ```shell
   T=$(mktemp -d)
   glab mr view <iid> -F json | jq -r .description > "$T/desc.md"
   # Insert the approved section into $T/desc.md
   glab mr update <iid> --description "$(cat "$T/desc.md")" --label database
   ```

   `glab` gets the project from the current Git remote. Pass `-R <group/project>` only when
   the MR is in a different project.

   Then tell the author to rerun the `danger-review` job, so reviewer roulette suggests a
   database reviewer, and to request a review from that reviewer.
