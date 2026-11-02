## GitLab for VOS

This repository contains GitLab source from the official
[GitLab repository](https://gitlab.com/gitlab-org/gitlab), with tooling for VOS integration development.
The initial commit contains the original source tree without the original commit history.
License files and copyright notices remain in the source tree.

### Current status

Source import, upstream synchronization tooling, and the VAI `apps/GitLab` submodule are in place.
VOS authentication, account mapping, application packaging, and device validation are not implemented yet.
This repository does not currently provide an installable VOS app release.

The original upstream introduction and installation references are retained in
[README-legacy.md](README-legacy.md).
This README describes maintenance of the VOS fork.

`UPSTREAM` records the source URL, branch, original commit ID, source tree ID, and local
snapshot commit used as the merge baseline.
The default development branch is `main`.

### VOS integration plan

The initial design uses one shared GitLab instance with GitLab's native users, groups,
projects, and permissions.
VOS supplies platform identity, the navigation entry, and application lifecycle management.
The following work remains subject to implementation and validation:

| Area | Planned integration |
| --- | --- |
| Authentication | Start with GitLab's native OpenID Connect support. Validate VOS discovery, issuer consistency, token verification, client registration, callbacks, and certificate trust. Add a small authentication extension only if the VOS iframe Fastpath cannot establish the required GitLab session through native interfaces. |
| Account mapping | Bind the identity provider and stable VOS `sub` to a GitLab account. Treat username and email as mutable profile fields. Verify first-login provisioning, missing or unverified email, account collisions, user switching, and logout. |
| Account lifecycle and permissions | Define administrator mapping, project and group access, and account disable/delete handling. Handle existing GitLab sessions, personal access tokens, and SSH keys separately from the VOS login session. |
| Web entry | Integrate the VOS menu, iframe, Traefik routing, and application path. Validate static assets, redirects, cookies, CSRF, WebSockets, and frame policies. |
| Git access | Publish correct external clone URLs and an SSH port that does not conflict with the host. Keep HTTPS clone/push and SSH authentication usable outside the browser login flow. |
| Storage and recovery | Persist repositories, database state, uploads, LFS objects, configuration, and encryption keys. Start with GitLab's bundled database and Redis. Validate consistent backup and restore before changing shared-service dependencies. |
| Packaging and runtime | Add the VOS manifest, Compose services, configuration, routes, storage declarations, and health checks. Verify image availability and resource requirements separately for AMD64 and ARM64. |
| Upgrade and optional services | Follow GitLab's supported upgrade stops and database migration requirements. Define recovery behavior. Add Runner, Registry, Pages, and SMTP only when included in the release scope. |

Before declaring the app integrated, verify two distinct VOS users, stable account binding,
private-project access controls, HTTPS and SSH clone/push, restart persistence, and account
disable behavior on a target VOS device.
Validate backup/restore and the supported upgrade path separately from a successful initial install.

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
Upstream changes to `README.md` can conflict with this fork's replacement homepage.
Merge the upstream documentation changes into `README-legacy.md`, preserve the VOS homepage
in `README.md`, and stage both files before continuing.
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
