## GitLab upstream updates for VOS

This repository contains GitLab source from the official
[GitLab repository](https://gitlab.com/gitlab-org/gitlab), plus VOS integration changes.
The initial commit contains the original source tree without the original commit history.
License files and copyright notices remain in the source tree.

`UPSTREAM` records the source URL, branch, original commit ID, source tree ID, and local
snapshot commit used as the merge baseline.
The default development branch is `main`.

### Update source

Commit or stash local changes, then run from the repository root:

```shell
python3 scripts/vos_sync_upstream.py --check
python3 scripts/vos_sync_upstream.py
```

The first command checks for an update without changing the source or baseline.
The second command fetches the latest upstream source with `--depth=1` and `--no-tags`,
creates a source snapshot whose parent is the previous snapshot, and merges that snapshot
into the current branch.
On success, the script commits the merge and the updated `UPSTREAM` file together.
The script does not push, install dependencies, build, or deploy GitLab.

Each update retains one upstream source snapshot and a local merge commit.
Individual upstream commits between snapshots are not imported.
The original upstream commit IDs remain in `UPSTREAM` and snapshot commit messages.
Use those IDs to inspect detailed upstream history on GitLab.com.
Do not use `git pull upstream`, `--unshallow`, or unrestricted upstream history fetches.
Use ordinary `git pull --ff-only origin main` to receive changes already published in this fork.

Fetches use temporary directories under `~/dev/build/gitlab-upstream` and remove those
directories when the command exits.
Set `VOS_UPSTREAM_BUILD_ROOT` to change that location.
Python 3 and Git are required on macOS or Linux.
The script supports fresh clones and execution from an initialized VAI submodule.

### Resolve conflicts

If an update conflicts with local changes, the script leaves a Git merge in progress.
Resolve each conflict and stage only the intended resolutions:

```shell
git status
git add <resolved-files>
python3 scripts/vos_sync_upstream.py --continue
```

Use the script to finish the merge. Do not run `git commit` separately or edit `UPSTREAM`.
To cancel the update and preserve the previous baseline:

```shell
python3 scripts/vos_sync_upstream.py --abort
```

### Review and deliver

Review the merge, run checks appropriate to the changed code on an approved build host,
and push the GitLab branch before committing and pushing the VAI submodule reference.
No build or test command should write generated files into the source checkout.

The updater's repository tests use temporary local Git repositories under
`~/dev/build/gitlab-upstream-tests` and require no network or GitLab services:

```shell
python3 scripts/tests/test_vos_sync_upstream.py
```
