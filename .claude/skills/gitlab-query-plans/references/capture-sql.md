# Capture the SQL that Rails runs

Capture SQL from the code path itself, so that scopes, joins, preloads, pagination, and limits
match production. Explain the final statement sent to the database, not an intermediate
relation.

- Capture one statement for each variation of a dynamic query, for example with and without an
  optional filter or join. If there are many permutations, capture the one with all parameters
  plus one for each query shape.
- For paginated queries, use the maximum allowed `LIMIT` and a non-zero `OFFSET`.
- Remove the trailing `/*application:...*/` marker comment before you explain the query.
- Replace local IDs with the production IDs you picked.

CI: the `rspec:merge-auto-explain-logs` job in the MR pipeline records the queries the specs run
with their plans and shows which are new compared with the default branch.

For other capture methods (performance bar, `log/development.log`, spec logging), see
[Tips for finding the SQL executed by the application](../../../../doc/development/database_review.md#tips-for-finding-the-sql-executed-by-the-application).

## Option A: `to_sql` on the final relation

Use this option only if nothing else is chained onto the relation before it runs: no caller
scopes, finders, pagination, or `limit`. Otherwise, use option B.

```shell
bin/rails runner 'puts ::Ai::FlowTrigger.for_projects(278964).to_sql'
```

- `Project.new(id: X).assoc` yields `(1=0)` for through-associations on an unsaved record.
  Use `Project.find(X)` or a real local record, then put the production ID into the SQL.
- For `has_one` association loads, `Model.first.association(:name).scope.to_sql` gives the
  `... LIMIT 1` form.

## Option B: record queries while running the code

This option catches preload queries, association loads, and anything the caller chains on:

```shell
bin/rails runner '
project = Project.joins(:group).first
sqls = []
ActiveSupport::Notifications.subscribed(->(*, payload) {
  sqls << payload[:sql] if payload[:sql] =~ /table_a|table_b/
}, "sql.active_record") do
  # Call the code under review here
  project.approval_policies.without_warn_mode.preload_approval_policy_rules.to_a
    .each { |p| p.undeleted_approval_policy_rules.to_a }
end
puts sqls.uniq
'
```
