---
name: fixture-coverage
description: "Write a development fixture for a table that has no seed data, or close the value-class gaps in one that does. Use when asked to add seed data for a table, to act on gitlab:seed:value_class_report output, or when run-dev-fixtures fails because a newly added table holds no rows."
---

# Development fixtures for empty and thinly-seeded tables

`db:migrate:multi-version-upgrade` restores a PG dump and runs every newer
migration against it. A table with no rows, or with rows that never vary,
lets a migration pass without touching anything. The failure then lands on a
customer during a real upgrade.

## 1. Ask what the table needs

```shell
bundle exec rake "gitlab:seed:value_class_report[table_a,table_b]"
```

Each column comes back as either a specification or a gap:

```
  ci_triggers
    description (string): needs null, empty, ascii, glyphs
    project_id (integer): needs present
```

A class a constraint puts out of reach is never asked for, so `project_id`
above wants a value but not a null: a `CHECK (project_id IS NOT NULL)`
rejects one.

`needs` means the table holds no rows and this is what to write. `missing`
means rows exist but never take that shape.

Run it with no arguments to sweep every table; that form reports only tables
that hold rows and still miss a class.

## 2. Write the fixture

Add `db/fixtures/development/NN_<area>.rb`, or `ee/db/fixtures/development/`
for EE-only tables. Read `db/fixtures/development/41_code_review_workflow.rb`
first and mirror it.

An EE fixture is seeded by `run-dev-fixtures-ee` and, on an EE image, by the
upgrade-stop dump. Prefer the FOSS path when the table also exists in CE, so
`run-dev-fixtures` seeds it too. A new fixture only reaches the dump once the
upgrade stop ships a release containing it, since the generator seeds from
inside the released image.

Rules that reviewers enforce on these files:

- **`insert_all`, not model creates.** The point is row shapes a long-lived
  instance really contains, including nulls in columns that are nullable
  today and might not be after a future migration. Model validations reject
  exactly those shapes.
- **Order every lookup.** `limit(2)` without `order(:id)` picks different
  rows on a re-run, so the fixture stops being idempotent and grows the
  table on every seed.
- **Populate sharding keys with the value their sync trigger derives**, not
  whatever is nearest to hand. A `namespace_id` is often the parent's
  `project_namespace_id`, not its `namespace_id`.
- **Do not rescue**, even though the file above does. A few fixtures swallow
  errors and the rest let them surface, so a table that stops seeding fails
  `run-dev-fixtures-ee` instead of quietly losing coverage. Copy its
  structure, not its `rescue` blocks.
- **Guard tables with no unique index** so a second run inserts nothing.

## 3. Verify it before opening anything

```shell
bundle exec rake db:seed_fu FILTER=<your_file>
bundle exec rake db:seed_fu FILTER=<your_file>
bundle exec rake "gitlab:seed:value_class_report[<your_tables>]"
```

Two runs must leave row counts unchanged, and the report should come back
quieter than it started.

## 4. Open the merge request

Ask whether to open it as a draft or as ready for review, then create it
following `.ai/merge-requests.md`, which includes `/assign me` so the author
owns it.

Request no reviewers. The author chooses who reviews, and the owning group
is the one to ask: it is the `feature_categories` entry in the table's
`db/docs/<table>.yml`.

In the description, say which value classes the rows now cover.

## Known limits of the report

- A broken foreign key reference is not checked; only null against present.
- `negative` is still offered on an integer column with no check constraint
  bounding it, which an enum cannot satisfy.
- Column types without rules, such as `binary` and `uuid`, are skipped.
