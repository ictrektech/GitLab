## GitLab for VOS

Select the CPU profile matching the device: `amd` for AMD64 or `arm` for ARM64.
Neither requires NVIDIA runtime. A GitLab Runner is a separate optional deployment.

Select one NAS public directory or host path for Data, mapped directly to `/var/opt/gitlab`
for repositories, uploads, and application data. VOS manages configuration and encryption
keys in `${VOS_APP_STORAGE_PATH}/config` and logs in `${VOS_APP_STORAGE_PATH}/logs`.
The required PGV application provides PostgreSQL through dedicated database `gitlabhq_production`
and non-superuser role `gitlab`. Bundled PostgreSQL is disabled. Redis is currently bundled.
The initializer installs required extensions and saves the dedicated password in
`${VOS_APP_STORAGE_PATH}/config/vos-db-password`. It refuses unexpected database ownership or missing saved credentials.
Keep their permissions and ownership intact. Stop GitLab before moving the directory.
Back up the configuration and keys, application files, and the GitLab database in PGV together.

Set the externally reachable HTTPS VOS URL ending in `/app/com.ictrek.gitlab`.
Trust the VOS certificate in the browser and Git clients.
First startup performs GitLab initialization and can take several minutes.

Open the VOS menu to sign in. GitLab binds each verified VOS subject to a separate native
account. VOS names and emails do not grant administrator or project access.
The first version uses reserved placeholder emails. Configure a verified contact email separately.
GitLab's local administrator account remains available for administration and recovery.

Use GitLab personal access tokens or SSH keys for Git operations.
Web single sign-on does not authenticate a command-line Git client.
VOS logout or account changes do not yet revoke existing GitLab sessions, tokens, or keys.
Block the corresponding GitLab account when immediate revocation is required.

This development package requires validation on the target VOS release before production use.

If 0.0.2 was installed, stop it before upgrading. Select the previous `<GITLAB_STORAGE_PATH>/gitlab/data` as Data, and move the previous `gitlab/config` and `gitlab/logs` into the VOS application storage `config` and `logs` directories. Existing files are not moved automatically; retain database credentials and encryption keys.

The external HTTPS URL is a required installation field with no empty default.
Use the actual device address, for example `https://vos.example.com:1180/app/com.ictrek.gitlab`.
