---
name: gitlab-backport
description: "Backport a merged GitLab bug fix from master to the maintained stable branches (MAJOR-MINOR-stable-ee) by cherry-pick and open one Stable Branch MR per release. Use when asked to backport, cherry-pick a fix to a stable branch, or prepare patch release MRs for gitlab-org/gitlab."
version: 1.0.1
license: MIT
category: Development Workflow
metadata:
  audience: developers
  workflow: gitlab-release
---

# GitLab Backport

## When to Use

Cherry-pick a merged `master` fix onto each maintained stable branch of `gitlab-org/gitlab` for a patch release. Load the `glab` skill before creating MRs. Official process: [patch release runbook for engineers](https://gitlab.com/gitlab-org/release/docs/-/blob/master/general/patch/engineers.md).

## Prerequisites

- The fix is merged and deployed to GitLab.com.
- It is a bug fix. Features are not backported ([maintenance policy](https://docs.gitlab.com/policy/maintenance/)). For versions outside the policy, open a [backport request issue](https://gitlab.com/gitlab-org/release/tasks/-/issues/new?issuable_template=Backporting-request).
- Not a security fix. Security backports must not be opened on the canonical project; follow the [security release process for engineers](https://gitlab.com/gitlab-org/release/docs/-/blob/master/general/security/engineer.md) instead.
- Targets are the maintained versions that have the bug, at most the three most recently released minors, taken from version.gitlab.com (as Danger does). Never infer them from local or remote branch names; see [maintained-versions.md](references/maintained-versions.md). The public maintenance policy page still says bug fixes go to the current release only; per the patch release runbook, bug-fix backports to all three maintained minors are self-serve while the policy extension rolls out.

## Process

Repeat steps 3-6 for each affected target (`18.11` / `18-11-stable-ee` shown).

1. **Find the commit.** Run `git fetch origin`, then always use the merge commit SHA of the merged MR, so the backport carries the whole fix:
   ```bash
   COMMIT_SHA=$(glab mr view <iid> -R gitlab-org/gitlab --output json | jq -r .merge_commit_sha)
   ```
   Do not grep `git log --oneline` for keywords: a keyword grep matches one of the MR's individual commits instead of the merge commit, so the backport would miss the rest of the fix. If you must search the log, use `COMMIT_SHA=$(git log origin/master --merges --grep "See merge request https://gitlab.com/gitlab-org/gitlab/-/merge_requests/<iid>$" --format=%H)`.
2. **Find the affected versions.** Backport only to maintained versions that have the bug and lack the fix. For each target skip it if `git merge-base --is-ancestor "$COMMIT_SHA" origin/18-11-stable-ee` succeeds (the fix was merged to `master` before that branch was cut; exit 128 means a bad SHA or missing ref, not "absent"). An earlier backport has a new SHA, so also skip it if an open or merged backport MR already targets the branch (`glab mr list -R gitlab-org/gitlab --target-branch 18-11-stable-ee --search "<original MR title>" --all --output json | jq -r '.[] | select(.state == "opened" or .state == "merged") | .web_url'`), or if `git log origin/18-11-stable-ee --fixed-strings --grep "<original MR title>"` finds it (differently titled or adapted backports). Otherwise check that the bug exists on `origin/MAJOR-MINOR-stable-ee`: `git merge-base --is-ancestor <introducing-commit> origin/18-11-stable-ee` (find it with `git log -S` or `git blame` on the lines the fix changed), or `git show`/`git grep` on that branch. If the commit check says no, the content check is the final answer (the code may have been changed or backported since). Skip versions that never had the bug.
3. **Cherry-pick.**
   ```bash
   git checkout -b 18-11-stable-ee-backport-<mr-iid> origin/18-11-stable-ee
   git cherry-pick -m1 "$COMMIT_SHA"   # drop -m1 for a non-merge commit
   ```
   If git says "The previous cherry-pick is now empty", the fix is already there: run `git cherry-pick --abort`, delete the local backport branch, and skip that version. On conflicts, first confirm the fix isn't already on the branch, then resolve, `git cherry-pick --continue`, and record the resolution in the MR description.
4. **Push with `--no-verify`.** Local pre-push hooks (mermaidlint, gettext, vale) match `master` tooling and fail on stable branches; CI runs the real checks.
   ```bash
   git push origin 18-11-stable-ee-backport-<mr-iid> --no-verify
   ```
5. **Write the description** from the repo's `.gitlab/merge_request_templates/Stable Branch.md`, copied verbatim, HTML comments included. Danger's stable-branch check rejects MRs without them. Fill labels, milestone, and assignee as in [mr-description.md](references/mr-description.md).
6. **Create the draft MR.** Title `Backport of '<original MR title>'` with no version prefix: the template says the title is copied into the patch blog post, and recent merged stable MRs use this form (the target branch carries the version). Omit `--push` (already pushed) and `--assignee` (fine-grained PATs get `403 insufficient_granular_scope`; the description's `/assign me` covers it).
   ```bash
   glab mr create -H gitlab-org/gitlab -R gitlab-org/gitlab \
     --title "Backport of '<original MR title>'" \
     --description "$(cat /tmp/backport-18-11-description.md)" \
     --target-branch 18-11-stable-ee --draft --yes
   ```
7. **Verify** milestone, labels, and assignee landed. If a quick action did not apply, fix it with `glab mr update <iid> --milestone "18.11" --label "backport,type::bug,pipeline::tier-3,..." -R gitlab-org/gitlab`.

## Pitfalls

- Cherry-picking a merge commit without `-m1` fails with "is a merge but no -m option was given".
- Danger error "does not use the stable branch template" means the template's HTML comments were stripped.
- This flow intentionally skips the `glab` skill's `--push` rule: the branch is pushed in step 4 with `--no-verify`. Keep `-H gitlab-org/gitlab`.

## Done when

- [ ] One MR per affected maintained version, target branch `MAJOR-MINOR-stable-ee`
- [ ] Conflicts, if any, documented in the description
- [ ] Milestone, labels, assignee verified
- [ ] Pipeline green, especially `e2e:test-on-omnibus-ee`, which runs only with `~"pipeline::tier-3"` (if it fails, confirm the failure relates to the change before asking for review)
- [ ] One maintainer approval (stable branches need one, not two), then merge

After merge, the change deploys to `https://gitlab.{major-minor}-stable-security-get.env.release.gitlab.net`.

## Contributing Improvements

This skill is maintained in [`gitlab-org/gitlab`](https://gitlab.com/gitlab-org/gitlab) under `.claude/skills/gitlab-backport/`. If you discover that any
guidance here is **inaccurate or outdated** (e.g. a command that no longer
works, a wrong flag, an incorrect API behavior), confirm with the user and open
an MR against that repository with the fix. Keep changes focused — one fix per
MR.
