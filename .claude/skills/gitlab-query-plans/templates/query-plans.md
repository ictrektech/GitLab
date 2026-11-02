# MR description: Database section

Add a `## Database` section to the MR description, before `## References` if that section
exists. For each query, include:

- What the query does and when it runs.
- The SQL, with placeholders such as `<project_id>` instead of the production IDs you used.
  The console plan link holds the real query.
- The plan link, followed by a one-line summary: scan type and index, rows, time (cold or
  warm), and shared buffers hit and read.

Mention schema changes only if the MR makes them. Values in these examples are illustrative.

## New query

````markdown
## Database

New read queries introduced by `method_name` (run once per evaluation):

### 1. Flow triggers for the project

```sql
SELECT "ai_flow_triggers".* FROM "ai_flow_triggers" WHERE "ai_flow_triggers"."project_id" = <project_id>
```

Plan: https://console.postgres.ai/gitlab/projects/gitlab-production-main/sessions/63540/commands/168710
(Index Scan on `index_ai_flow_triggers_on_project_id`, 3 rows, 2.2 ms cold, buffers: 4 hit / 3 read)
````

## Modified query

Include the SQL and plan from both before and after the change:

````markdown
### 2. Approval policies for the project (modified)

Before:

```sql
<previous SQL with placeholders>
```

Plan: https://console.postgres.ai/gitlab/projects/gitlab-production-main/sessions/63540/commands/168720
(Seq Scan on `security_policies`, 20 rows, 340 ms cold, buffers: 1200 hit / 8900 read)

After:

```sql
<new SQL with the same placeholders>
```

Plan: https://console.postgres.ai/gitlab/projects/gitlab-production-main/sessions/63540/commands/168721
(Index Scan on `index_security_policies_on_type`, 20 rows, 3.1 ms cold, buffers: 12 hit / 6 read)
````
