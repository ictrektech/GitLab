---
stage: Plan
group: Work Items
info: To determine the technical writer assigned to the Stage/Group associated with this page, see <https://handbook.gitlab.com/handbook/product/ux/technical-writing/#assignments>
description: Configure rate limits on issue, epic, and note creation, and on thread resolution.
title: Content creation rate limits
---

{{< details >}}

- Tier: Free, Premium, Ultimate
- Offering: GitLab Self-Managed

{{< /details >}}

Rate limits control the pace at which users can create issues, epics, and notes,
and resolve or unresolve threads.

## Issue and epic creation

The limit for [epic](../user/group/epics/_index.md) creation is the same limit applied to issue creation.

Prerequisites:

- Administrator access.

To limit the number of requests made to the issue and epic creation endpoints:

1. In the upper-right corner, select **Admin**.
1. In the left sidebar, select **Settings** > **Network**.
1. Expand **Issues Rate Limits**.
1. Under **Max requests per minute**, enter the new value.
1. Select **Save changes**.

The rate limit:

- Is applied independently per project and per user.
- Is not applied per IP address.
- Is disabled by default.
- Can be set to `0` to disable the rate limit.

Requests over the rate limit are logged into the `auth.log` file.

For example, if you set the limit to `300`, requests that exceed a rate of 300 per minute are blocked.
Access to the endpoint is available after one minute.

## Note creation

You can configure the rate limit for requests to the note creation endpoint.

Prerequisites:

- Administrator access.

To change the note creation rate limit:

1. In the upper-right corner, select **Admin**.
1. In the left sidebar, select **Settings** > **Network**.
1. Expand **Notes rate limit**.
1. In the **Maximum requests per minute** box, enter the new value.
1. Optional. In the **Users to exclude from the rate limit** box, list users allowed to exceed the limit.
1. Select **Save changes**.

The rate limit:

- Is applied independently per user.
- Is not applied per IP address.
- Defaults to `300`.

Requests over the rate limit are logged into the `auth.log` file.

For example, if you set the limit to `300`, requests that exceed a rate of 300 per minute are blocked.
Access to the endpoint is available after one minute.

## Thread resolution

{{< history >}}

- [Introduced](https://gitlab.com/gitlab-org/gitlab/-/work_items/606720) in GitLab 19.6.

{{< /history >}}

You can configure the rate limit for requests that resolve or unresolve a thread or a comment.
The limit applies to the UI, the REST API, and the GraphQL API.

Prerequisites:

- Administrator access.

To change the thread resolution rate limit:

1. In the upper-right corner, select **Admin**.
1. In the left sidebar, select **Settings** > **Network**.
1. Expand **Thread resolution rate limits**.
1. In the **Maximum requests per minute** box, enter the new value.
1. Select **Save changes**.

The rate limit:

- Is applied independently per user.
- Is not applied per IP address.
- Defaults to `120`.
- Can be set to `0` to disable the rate limit.
- Counts each resolve or unresolve request, including requests for a thread that is already
  resolved or unresolved.
  A GraphQL request with multiple mutations counts each mutation.
  When a GraphQL request exceeds the limit, the whole request returns an error,
  but the mutations that ran before the limit was reached are not reverted.

Requests over the rate limit return `429 Too Many Requests`.

## Related topics

- [Rate limits](_index.md)
- [Non-configurable rate limits](non_configurable.md)
