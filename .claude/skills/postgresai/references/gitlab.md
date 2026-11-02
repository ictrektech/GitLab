# Using this at GitLab

- Pick the target alias for the table's database:
  1. Read `gitlab_schema` in `db/docs/<table>.yml`.
  1. Find the `db/database_connections/<db>.yaml` that lists that schema under `gitlab_schemas`.
     `gitlab_shared*` tables are on every database, so use the one the query runs against.
  1. Use `gitlab-production-<db>` (`main`, `ci`, or `sec`). Use `gitlab-production-registry`
     for container-registry queries. Skip `*-deprecated` entries in `postgresai projects`.
- A wrong alias does not error, so pick by table ownership, not by whether `describe` or `plan`
  succeeds. The table exists on every clone but is empty outside its own database, so the plan
  is meaningless (`cost=0.00..0.00`). For example, main holds empty copies of partitioned
  `p_ci_*` tables, so plans there look cheap and are wrong.
- Docs: [Database Lab](https://docs.gitlab.com/development/database/database_lab/#use-the-postgresai-cli).
- Local GDK databases: use `gdk psql` against your local GDK database instead; this skill is
  for production-sized data.
- Before requesting a database review: [db-review-flow.md](db-review-flow.md).
