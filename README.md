## GitLab for VOS

This repository contains GitLab source from the official
[GitLab repository](https://gitlab.com/gitlab-org/gitlab), with tooling for VOS integration development.
The initial commit contains the original source tree without the original commit history.
License files and copyright notices remain in the source tree.

### Current status

The repository includes source import, upstream synchronization, a VOS OmniAuth provider,
stable account mapping, and CPU-only AMD64/ARM64 image and package definitions.
Authentication uses the VOS iframe Fastpath with PKCE and online token introspection and userinfo checks.
Device acceptance and publication are separate from these source changes.
See the validation results reported with each delivered version before deploying it.

The original upstream introduction and installation references are retained in
[README-legacy.md](README-legacy.md).
This README describes maintenance of the VOS fork.

`UPSTREAM` records the source URL, branch, original commit ID, source tree ID, and local
snapshot commit used as the merge baseline.
The default development branch is `main`.

### Sign in with VOS

The VOS menu opens `/app/com.ictrek.gitlab/-/vos/sign_in` on the same HTTPS origin as VOS.
The browser performs the PKCE exchange through the VOS bridge, then posts the access token
to GitLab's native CSRF-protected OmniAuth callback.
The backend verifies token activity, expiration, audience, client ID, scope, subject, and
the latest enabled user state through the configured VOS server.
Tokens stay out of URLs, local storage, GitLab identity records, and application logs.

The `vos` provider binds a SHA-256 encoding of the stable VOS `sub` to a native GitLab identity.
It uses stable `vos_<subject-hash>` usernames and reserved placeholder emails under `users.invalid`.
The initial displayed name comes from VOS. Configure a verified contact email separately for notifications.
Email and LDAP auto-linking remain disabled for this provider even when other providers use them.
VOS login does not grant GitLab administrator status or bypass GitLab two-factor authentication.
GitLab account blocks, signup controls, and project/group permissions remain effective.

No identity database migration is required. Changing the VOS identity provider behind an existing
GitLab installation requires an explicit identity migration, rather than reusing this provider name.
VOS account disablement rejects new sign-ins, but synchronization of existing GitLab sessions,
personal access tokens, SSH keys, and account deletion remains separate work.

### Images, profiles, and storage

The image extends a digest-pinned official GitLab EE runtime with the VOS provider files.
It verifies that the runtime `VERSION` matches this checkout's `VERSION`.
No precompiled upstream application files are replaced.
The VOS runtime uses two Puma workers and Sidekiq concurrency 10 to avoid scaling
GitLab processes to every CPU on a shared appliance.

PostgreSQL is provided by the required PGV application. GitLab's bundled PostgreSQL is disabled.
Redis remains bundled for now, independently of the PostgreSQL integration.

| VOS profile | Architecture | Feishu sheet | Image tag |
| --- | --- | --- | --- |
| `amd` | `amd64` | `AMD_with_cuda` | `amd_<GitLab-VERSION>_<source-commit-12>` |
| `arm` | `arm64` | `ARM_with_cuda` | `arm_<GitLab-VERSION>_<source-commit-12>` |

The sheet names identify the existing release-table locations. Neither profile uses NVIDIA runtime.
Runner is independent of the GitLab server. GPU jobs require GPU configuration on the Runner host,
not on this application container. Runner is not installed or granted the Docker socket by this package.

`GITLAB_DATA_PATH` is the only `type: path` configuration, with hint
`com.ictrek.gitlab.storage`. Select a NAS public directory or host path as with Model Hub.
It maps directly to `/var/opt/gitlab` for repositories, uploads, and local application data.
Configuration and encryption keys use `${VOS_APP_STORAGE_PATH}/config`; logs use
`${VOS_APP_STORAGE_PATH}/logs`. PostgreSQL data remains in PGV's managed storage.
Back up configuration and keys together with Data and the PostgreSQL database.
Stop GitLab before moving files and preserve ownership and permissions.

If version 0.0.2 was already installed, stop it before upgrading. Set Data to the previous
`<GITLAB_STORAGE_PATH>/gitlab/data`, and move the previous `gitlab/config` and `gitlab/logs`
into the VOS application storage's `config` and `logs` directories. This package does not
move existing files automatically; retain the saved database credential and encryption keys.
The icon uses the original upstream `app/assets/images/logo.svg` on a transparent 1024-pixel square.

Build on an architecture-matched host after syncing the local checkout with `rsync`:

```shell
python3 ictrek.app/scripts/build_image.py --sheet AMD_with_cuda --source-commit <local-commit>
python3 ictrek.app/scripts/build_image.py --sheet ARM_with_cuda --source-commit <local-commit>
```

Each command builds one platform, pushes its single-platform image to Huawei SWR, and records
the tag in the corresponding Feishu sheet. Use `--no-push` for local image validation.
The script performs no Git operations. Set `--base-image` to a mirror of the pinned digest when needed.
Build contexts, logs, and metadata remain under `~/dev/build/gitlab` on the build host.

The profile-specific one-shot PGV initializer creates database `gitlabhq_production`, role `gitlab`,
and the required `amcheck`, `btree_gist`, `pg_trgm`, and `plpgsql` extensions.
It validates PostgreSQL 17/18 and database ownership and never grants GitLab superuser privileges.
Only this initializer receives the VOS PGV administrator credential.
The application receives only its dedicated password through the protected configuration mount.
That password is generated once and retained in `${VOS_APP_STORAGE_PATH}/config/vos-db-password` with mode `0600`.
Keep that file with the GitLab configuration backup. Existing roles without their saved credential
or databases owned by another role cause initialization to fail instead of being overwritten.
Existing bundled PostgreSQL data requires an explicit migration before switching to this image.

GitLab's external PostgreSQL requirements include `max_connections >= 400` and
`shared_buffers >= 2GB`. The initializer checks these before loading the schema.
PGV 0.0.58 defaults meet these requirements. Older installations or custom settings may be lower.
Check the installed PGV without changing it:

```shell
python3 ictrek.app/scripts/check_pgv.py
```

An operator can explicitly apply the required capacity and restart shared PGV with
`--apply-and-restart`. This briefly disconnects every application using that PGV instance.
Schedule or obtain approval for that interruption before running the command.
The script saves only the previous non-secret parameter values under `~/dev/build/gitlab`.
Use `--restore-and-restart` to restore those values during an approved maintenance window.
The GitLab package never restarts or silently reconfigures shared PGV itself.

After both image publications succeed, run `ictrek.app/scripts/package.sh` on a build host.
It resolves profile images from Feishu, validates both Compose profiles, and produces the pull
package under `~/dev/build/gitlab/packages`. This command does not publish an app-store release.
The staged package resolves its PGV dependency from the current published release.

For a release, commit and push application code and update the VAI submodule reference first.
After every affected profile image is published and recorded in Feishu, run locally:

```shell
./ictrek.app/scripts/update_version.sh patch
```

The script requires a clean checkout, bumps `ictrek.app/VERSION`, and pushes only the
`vos-gitlab-v<version>` trigger tag. GitHub Actions builds and checks the package, creates
public release `v<version>`, and publishes it to the VOS App Store. Reuse unchanged images
for packaging-only releases. Configure `FEISHU_APP_ID`, `FEISHU_APP_SECRET`, `APPSTORE_IP`,
and `APPSTORE_TOKEN` as repository Actions secrets. Verify the workflow and publication
results before considering a release complete. The workflow's manual retry accepts an
existing published version and verifies its artifact digest before retrying App Store upload.

Set the external HTTPS URL ending in `/app/com.ictrek.gitlab` at installation, and trust its
certificate in the browser and Git clients. The local GitLab administrator login remains available.

### VOS integration plan

The initial design uses one shared GitLab instance with GitLab's native users, groups,
projects, and permissions.
VOS supplies platform identity, the navigation entry, and application lifecycle management.
The following boundaries guide implementation and acceptance:

| Area | Integration and validation |
| --- | --- |
| Authentication | The VOS OmniAuth strategy uses the PKCE Fastpath and online introspection/userinfo rather than relying on the platform's currently inconsistent OIDC issuer metadata. Validate client registration, callbacks, and certificate trust on the target device. |
| Account mapping | Bind provider `vos` and the encoded stable subject to a native GitLab identity. Verify first-login provisioning, account collisions, user switching, and logout. Contact email and displayed name do not determine identity. |
| Account lifecycle and permissions | Define administrator mapping, project and group access, and account disable/delete handling. Handle existing GitLab sessions, personal access tokens, and SSH keys separately from the VOS login session. |
| Web entry | Integrate the VOS menu, iframe, Traefik routing, and application path. Validate static assets, redirects, cookies, CSRF, WebSockets, and frame policies. |
| Git access | Publish correct external clone URLs and an SSH port that does not conflict with the host. Keep HTTPS clone/push and SSH authentication usable outside the browser login flow. |
| Storage and recovery | Persist repositories, uploads, LFS objects, configuration, and encryption keys in the selected directory. PostgreSQL uses a dedicated database and non-superuser role in PGV. Back up that database consistently with GitLab configuration and files. Redis is currently bundled. |
| Packaging and runtime | The manifest, Compose services, configuration, routes, storage declarations, and health checks are defined. Verify image availability and resource requirements separately for AMD64 and ARM64. |
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

The minimum VOS platform requirement is `>=3.0.0`, matching the working Model Hub
and PGV packages. Feature-document revision numbers do not define platform releases.

The external HTTPS URL is a required installation field with no empty default.
Use the actual device address, for example `https://vos.example.com:1180/app/com.ictrek.gitlab`.

VOS readiness waits for GitLab HTTP `/-/readiness` under the application base path.
The container starting successfully does not mean first-time initialization is complete.

Concurrent callbacks for the same verified VOS identity are serialized before native
account lookup and creation, preventing duplicate first-login provisioning.

Each login flow has its own five-minute challenge, bound to the native session CSRF
token and atomically consumed in Redis. Parallel flows cannot overwrite a shared session
state slot. Native CSRF validation and one-use replay rejection remain enabled.

Re-entering with the same mapped identity preserves the existing native session.
Only switching to a different identity signs out the previous GitLab account.

The VOS entry keeps a small integration frame alive across native GitLab navigation.
It reads the initial VOS locale and listens for `locale-change`, updates the signed-in
user through GitLab’s native CSRF-protected preferences endpoint, and reloads content
only when the language changes. Chinese and English follow VOS; login and accounts remain native.
