---
name: fe-test-janitor
description: >
  On-demand skill that reads one RSpec feature spec file, or every spec file in a
  directory, and classifies each example as `migrate`, `reframe`, `partial`, or
  `keep` using static signal analysis.
  Use when asked to triage Capybara feature specs for MSW migration candidates,
  identify slow or frontend-only specs, or reproduce the "Migrate top 20 slowest
  frontend only capybara tests to MSW" rubric sweep against a directory such as
  `spec/features/` or `ee/spec/features/`.
argument-hint: "<directory_or_file>  e.g. spec/features/work_items/"
---

# fe-test-janitor

Run the `fe_test_janitor` CLI on one `*_spec.rb` file, or on a directory of them,
then check each label against the frontend testing guide.

## Rules

The rules that decide whether a test stays in Capybara are in
`doc/development/testing_guide/frontend_testing.md`. The file is long, so do not
read all of it. Search for `### Choose the right feature test type` and read
from that heading to the next `###` heading. That part has these sections:

- **Choose the right feature test type**: the "Use a Capybara feature test"
  criteria always come first.
- **When a test checks the database**: what to do with a `reframe` label.
- **Find tests to move**: what each label means.

Do not repeat or change those rules here. Update the doc instead.

## How to run

The CLI uses only the Ruby standard library, so it does not need Bundler.

```shell
tooling/bin/fe_test_janitor spec/features/work_items/
tooling/bin/fe_test_janitor spec/features/work_items/detail/work_item_detail_spec.rb
```

## Output format

```plaintext
FILE: spec/features/work_items/detail/work_item_detail_spec.rb
  [migrate] shows development widget with merge request (line 42)
    Reason: quarantine tag detected; have_css/have_selector on Vue-rendered element
  [reframe] closes the work item (line 30)
    Reason: reloads a record to assert DB state
  [keep   ] reorders child items (line 18)
    Reason: drag-and-drop interaction
  [partial] uploads a design (line 55)
    Reason: file upload interaction; have_css/have_selector on rendered element
  [shared ] work items title (line 61)
    Reason: shared example call, not analyzed
```

The tool does not classify an `it_behaves_like` or `include_examples` call,
because its examples are in another file. It lists the call as `shared`. It also
skips the examples inside `shared_examples` and `shared_context` definitions.

A summary follows the results:

```plaintext
=== Summary ===
Files scanned : 4
Examples found: 23
  migrate     : 8
  reframe     : 2
  partial     : 5
  keep        : 8
Shared example calls (not analyzed): 3
```

## Labels are suggestions

The tool reads the spec source as text and does not load Rails. Check each label
by hand against the rules in the doc before you move a test. A `reframe` label
does not mean that the test can move: if the database change is the point of the
test, it stays in Capybara.

The tool reads only the lines of each example. When you check a label, also read:

- The `before` and `around` hooks of the enclosing groups, for example a
  `stub_request` in a parent `before` hook.
- The metadata of the enclosing groups, for example `:sidekiq_inline`.
- The helper methods that the example calls.

If the tool cannot parse a file, it stops and shows the file name and the syntax
errors.

## Code

The CLI is `tooling/bin/fe_test_janitor`, and the code is in
`tooling/lib/tooling/fe_test_janitor/`. Run the specs with:

```shell
bundle exec rspec spec/tooling/lib/tooling/fe_test_janitor/
```
