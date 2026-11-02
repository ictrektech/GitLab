# Stable Branch MR description

Copy `.gitlab/merge_request_templates/Stable Branch.md` verbatim to `/tmp/backport-18-X-description.md`, then:

- Keep every HTML comment at the top. Danger enforces them.
- Fill `## What does this MR do and why?` with the backported MR (`!number`), the bug, and whether the cherry-pick was clean or had conflicts and how they were resolved.
- Keep all checklist items and reference links.
- Expand the template's `/label ~backport` line. Quick actions in the description replace the `--assignee`, `--milestone`, and `--label` flags of `glab mr create`.

## Labels

Hardcode `~backport`, `~"type::bug"`, and `~"pipeline::tier-3"` (`e2e:test-on-omnibus-ee` runs on stable branches only with it; never add `pipeline::expedited`, Danger rejects it). Inherit group, section, devops, severity, bug subtype, and customer labels from the original MR:

```bash
glab mr view <original-mr-iid> -R gitlab-org/gitlab --output json \
  | jq -r '.labels[] | select(test("^(group::|section::|devops::|severity::|bug::|customer)"))'
```

Skip `backport`, `type::bug`, and `pipeline::tier-3` from the inherited list. Quote labels containing spaces or `::`:

```
/label ~backport ~"type::bug" ~"pipeline::tier-3" ~"<inherited-label>" ...
/milestone %18.X
/assign me
```

## Severity

See the [severity definitions](https://handbook.gitlab.com/handbook/product-development/how-we-work/issue-triage/#severity) in the handbook.
