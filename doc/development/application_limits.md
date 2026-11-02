---
stage: Async
group: Async
info: Any user with at least the Maintainer role can merge updates to this content. For details, see <https://docs.gitlab.com/development/development_processes/#development-guidelines-review>.
title: Application limits development
---

This document provides a development guide for contributors to add application
limits to GitLab.

## Documentation

First of all, you have to gather information and decide which are the different
limits that are set for the different GitLab tiers. Coordinate with others to document
and communicate those limits.

Add the documentation to the page that matches the limit type:

- [Plan limits and other instance-wide limits](../administration/instance_limits.md).
- Rate limits that are:
  - [Configurable in the **Admin** area](../rate_limits/_index.md#admin-area).
  - [Configurable only with the API or the Rails console](../rate_limits/_index.md#api-and-rails-console).
  - [Not configurable](../rate_limits/non_configurable.md).

There is a guide about [introducing application limits](https://handbook.gitlab.com/handbook/product/product-processes/#introducing-application-limits).

## Implement plan limits

The `plan_limits` table is cell-scoped configuration: each cell has its own
copy of the table, and limits are not migrated between cells. New cells start
with the column default for each limit, and administrators tune limits per cell
via the [admin Plan Limits API](../api/plan_limits.md). Because of this, every
new plan limit must be settable through that API - otherwise a new limit
can only ever take its column default on each cell.

Do not introduce a plan limit that must stay consistent across cells -
`plan_limits` is cell-local, so there is no way to keep it in sync.

### Insert database plan limits

In the `plan_limits` table, create a new column and insert the limit values.
It's recommended to create two separate migration script files.

1. Add a new column to the `plan_limits` table with non-null default value that
   represents desired limit, such as:

   ```ruby
   add_column(:plan_limits, :project_hooks, :integer, default: 100, null: false)
   ```

   Plan limits entries set to `0` mean that limits are not enabled. You should
   use this setting only in special and documented circumstances.
1. (Optionally) Create the database migration that fine-tunes each level with a
   desired limit using the `create_or_update_plan_limit` migration helper.
   The plans in this migration should match the [plans on GitLab.com](#subscription-plans).
   If a plan is missed, customers on that plan would receive the default limit, which might be
   `0` (unlimited).

   For example:

   ```ruby
   class InsertProjectHooksPlanLimits < Gitlab::Database::Migration[2.1]
     def up
       create_or_update_plan_limit('project_hooks', 'default', 0)
       create_or_update_plan_limit('project_hooks', 'free', 10)
       create_or_update_plan_limit('project_hooks', 'premium', 30)
       create_or_update_plan_limit('project_hooks', 'premium_trial', 30)
       create_or_update_plan_limit('project_hooks', 'ultimate', 100)
       create_or_update_plan_limit('project_hooks', 'ultimate_trial', 100)
       create_or_update_plan_limit('project_hooks', 'ultimate_trial_paid_customer', 100)
       create_or_update_plan_limit('project_hooks', 'opensource', 100)
     end

     def down
       create_or_update_plan_limit('project_hooks', 'default', 0)
       create_or_update_plan_limit('project_hooks', 'free', 0)
       create_or_update_plan_limit('project_hooks', 'premium', 0)
       create_or_update_plan_limit('project_hooks', 'premium_trial', 0)
       create_or_update_plan_limit('project_hooks', 'ultimate', 0)
       create_or_update_plan_limit('project_hooks', 'ultimate_trial', 0)
       create_or_update_plan_limit('project_hooks', 'ultimate_trial_paid_customer', 0)
       create_or_update_plan_limit('project_hooks', 'opensource', 0)
     end
   end
   ```

   Some plans exist only on GitLab.com. This is a no-op for plans
   that do not exist.

   To set limits in your migration only for GitLab.com and allow other instances
   to use the default limits, add `return unless Gitlab.com?` to the start of
   the `#up` and `#down` methods to make the migration a no-op for other instances.
1. Expose the new column through the [admin Plan Limits API](../api/plan_limits.md):

   - Add it as an `optional` parameter on `PUT /application/plan_limits`
     ([`lib/api/admin/plan_limits.rb`](https://gitlab.com/gitlab-org/gitlab/-/blob/master/lib/api/admin/plan_limits.rb))
     so administrators can tune the limit per cell.
   - Add it to the response entity
     ([`lib/api/entities/plan_limit.rb`](https://gitlab.com/gitlab-org/gitlab/-/blob/master/lib/api/entities/plan_limit.rb))
     so the limit can be read back.
   - Document the attribute on the [Plan Limits API page](../api/plan_limits.md).

### Plan limits validation

#### Get current limit

Access to the current limit can be done through the project or the namespace,
such as:

```ruby
project.actual_limits.project_hooks
```

#### Check current limit

There is one method `PlanLimits#exceeded?` to check if the current limit is
being exceeded. You can use either an `ActiveRecord` object or an `Integer`.

Ensures that the count of the records does not exceed the defined limit, such as:

```ruby
project.actual_limits.exceeded?(:project_hooks, ProjectHook.where(project: project))
```

Ensures that the number does not exceed the defined limit, such as:

```ruby
project.actual_limits.exceeded?(:project_hooks, 10)
```

#### `Limitable` concern

The [`Limitable` concern](https://gitlab.com/gitlab-org/gitlab/-/blob/master/app/models/concerns/limitable.rb)
can be used to validate that a model does not exceed the limits. It ensures
that the count of the records for the current model does not exceed the defined
limit.

You must specify the limit scope of the object being validated
and the limit name if it's different from the pluralized model name.

```ruby
class ProjectHook
  include Limitable

  self.limit_name = 'project_hooks' # Optional as ProjectHook corresponds with project_hooks
  self.limit_scope = :project
end
```

To test the model, you can include the shared examples.

```ruby
it_behaves_like 'includes Limitable concern' do
  subject { build(:project_hook, project: create(:project)) }
end
```

### Testing instance-wide limits

Instance-wide features always use `default` Plan, as instance-wide features
do not have license assigned.

```ruby
class InstanceVariable
  include Limitable

  self.limit_name = 'instance_variables' # Optional as InstanceVariable corresponds with instance_variables
  self.limit_scope = Limitable::GLOBAL_SCOPE
end
```

### Subscription Plans

GitLab Self-Managed:

- `default`: Everyone.

GitLab.com:

- `default`: Any system-wide feature.
- `free`: Namespaces and projects with a Free subscription.
- `premium`: Namespaces and projects with a Premium subscription.
- `premium_trial`: Namespaces and projects with a Premium Trial subscription.
- `ultimate`: Namespaces and projects with an Ultimate subscription.
- `ultimate_trial`: Namespaces and projects with an Ultimate Trial subscription.
- `ultimate_trial_paid_customer`: Namespaces and projects on a Premium subscription that are trialling Ultimate for 30 days.
- `opensource`: Namespaces and projects that are member of GitLab Open Source program.

There is an `early_adopter` plan on GitLab.com that has no subscriptions.

The `test` environment doesn't have any plans.

## Choose a rate limiter

GitLab has two rate limiters for application code.
Both use the [LabKit rate limiting SDK](https://gitlab.com/gitlab-org/ruby/gems/labkit-ruby/-/blob/master/lib/labkit/rate_limit/README.md) and store their counters in the rate limiting Redis instance.

Add a [request rate limit with LabKit](#implement-request-rate-limits-with-labkit) when:

- The limit protects a group of routes from request volume, whatever action each request performs.
  For example, the packages API, the files API, or Git over HTTP.
- The limit counts by IP address or by the authenticated requester.
- The request should be blocked before it reaches a controller or Grape endpoint.

Add a [`Gitlab::ApplicationRateLimiter` key](#implement-rate-limits-using-gitlabapplicationratelimiter) when:

- The limit applies to one action, such as creating an issue or sending an email.
- The limit counts by a resource, such as a project, group, or namespace, or by a combination of values.
- The limit counts distinct resources, or the work runs outside a web request, such as in a Sidekiq worker.

If either rate limiter could work, use `Gitlab::ApplicationRateLimiter`.
Its limit applies only to the action that calls it.

## Implement request rate limits with LabKit

The `Gitlab::Middleware::LabkitRackRateLimit` middleware rate limits Rails controllers,
Grape endpoints, and any other Rack requests.
The middleware runs after Warden authenticates the request and before the request reaches the application.
A request over the limit receives a `429 Too Many Requests` response.

LabKit enforces these rate limits.
`Rack::Attack` is still in the middleware stack, but it does not throttle requests.
LabKit reads each limit and period from the throttle definitions in `Gitlab::RackAttack`,
so new throttles still start there.

To add a request rate limit:

1. Add new fields to the [rate_limits JSONB column](https://gitlab.com/gitlab-org/gitlab/-/blob/63b37287ae028842fcdcf56d311e6bb0c7e09e79/app/models/application_setting.rb#L603)
   in the `ApplicationSetting` model.
1. Update the JSON schema validator for the [rate_limits column](https://gitlab.com/gitlab-org/gitlab/-/blob/63b37287ae028842fcdcf56d311e6bb0c7e09e79/app/validators/json_schemas/application_setting_rate_limits.json).
1. Add a throttle definition, which holds the limit and period:
   - For a single throttle, add it to `Gitlab::RackAttack.throttle_definitions`,
     with a matching predicate in `Gitlab::RackAttack::Request`.
   - For an authenticated and unauthenticated pair, add one entry to `Gitlab::Throttle::REGULAR_THROTTLES`.
     `Gitlab::RackAttack.regular_throttle_definitions` generates `throttle_unauthenticated_<name>`
     and `throttle_authenticated_<name>` from it.
1. Register the throttle in `ThrottleRegistry`. For more information, see [register a throttle](#register-a-throttle).
1. Add the new settings to the **Admin** area form in `app/views/admin/application_settings/_ip_limits.html.haml`.
1. Optional. To observe the throttle before it blocks requests, name it in the
   [`GITLAB_THROTTLE_DRY_RUN` environment variable](../administration/settings/user_and_ip_rate_limits.md#try-out-throttling-settings-before-enforcing-them).
   A throttle in dry run mode builds as a [`:log` rule](https://gitlab.com/gitlab-org/ruby/gems/labkit-ruby/-/blob/master/lib/labkit/rate_limit/README.md#actions) instead of a `:limit` rule,
   and its claim is named `<rule_name>_dry_run_bypass` instead of `<rule_name>_claim`.
1. Document the new settings in [User and IP rate limits](../administration/settings/user_and_ip_rate_limits.md) and [Application settings API](../api/settings.md).
1. Configure the rate limit for GitLab.com and document it in [rate limits on GitLab.com](../user/gitlab_com/rate_limits.md).

### Register a throttle

Each throttle maps to one LabKit rule in `Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry`,
defined in `lib/gitlab/rack_attack/labkit_rate_limit/throttle_registry.rb` and, for EE throttles, in
`ee/lib/ee/gitlab/rack_attack/labkit_rate_limit/throttle_registry.rb`.
A spec fails if a throttle in `Gitlab::RackAttack.all_throttle_definitions` has no registry entry.

Each entry declares:

- `limiter`: The limiter that owns the rule. Use `ThrottleRegistry::GENERAL`, unless the throttle
  must count requests that a rule in the general limiter also counts.
  In one limiter, a request is counted by the first rule that claims it, so a throttle that
  counts the same requests as another rule needs its own limiter.
  The protected paths and EE incident management throttles have their own limiters for this reason.
- `characteristics`: What the rule counts by, for example `[:ip]` for an unauthenticated
  throttle or `[:requester_type, :requester_id]` for an authenticated throttle.
- `match`: The facts a request must have for the rule to apply.
- `cohort`: The rollout cohort whose feature flags control enforcement of the rule.
  Use an existing cohort. A new cohort needs its own feature flag definitions, and
  `Rack::Attack` throttles requests again until both flags for the new cohort are enabled.
- `claims`: Whether the rule stops evaluation after it counts a request. Every entry must
  declare it.

LabKit evaluates the skip rules first, such as the bypass header and the user allowlist,
then the GitLab.com plan rules, then the registry rules.
Registry rules are evaluated in registry order: specialized APIs, then Git, then web,
then the general API. A throttle with `claims: true` counts the request and stops evaluation,
so a more general rule later in the list does not count the same request.

A claim includes the throttle's `setting_*` fact, so ordering excludes a request only while the
claiming throttle is enabled. For an exclusion that must always apply, add a [negated fact](https://gitlab.com/gitlab-org/ruby/gems/labkit-ruby/-/blob/master/lib/labkit/rate_limit/README.md#matchers) to
`match`, as the web and API rules do with `path: { nre: <regex> }`, `git_http_non_lfs: false`,
and `frontend: false`.

In `match`:

- Gate the rule on the presence of each characteristic that can be `nil`. An authenticated rule
  gates on `requester_id: /./`, and a rule that counts by `[:aid]` gates on `aid: /./`.
  Without the gate, requests with no value share one counter.
- Gate an unauthenticated rule on `requester_id: nil, runner_id: nil`.
- Include the throttle's `setting_*` fact, so that disabling the throttle in the **Admin**
  area stops the rule from matching.
- Put the `path:` regular expression last. Conditions are checked in order and evaluation
  stops at the first one that fails, so cheaper conditions first avoid running the regular
  expression.

Rules match on the facts returned by
`Gitlab::RackAttack::LabkitRateLimit::ClassifiedRequest#labkit_facts`, which merges the
identity facts with the classification facts. Add the throttle's `setting_*` fact to
`ClassifiedRequest#classification_facts`, or to the EE module for an EE throttle.
Add a classification fact only for a condition that a path regular expression cannot express.

### Tier-aware request rate limits

On GitLab.com, `Gitlab::RateLimit::PlanRules` adds request rate limits that depend on the
subscription plan of the requester. These rules are defined in
`ee/lib/ee/gitlab/rate_limit/plan_rules.rb` and apply only to GitLab.com.

- Each limit has two rules: a `:log` rule that counts requests, and a `:limit` rule that
  blocks them. Feature flags with `_info` and `_enforce` suffixes decide which rule matches.
- An authenticated user gets the highest plan among the top-level groups the user is a member of,
  directly or through a shared group. A user with no paid group gets the Free limits.

## Implement rate limits using `Gitlab::ApplicationRateLimiter`

`Gitlab::ApplicationRateLimiter` limits a single action. Call it from the code that performs the
action, such as a controller, API endpoint, service, or worker.
Each rate limit key is a LabKit rule.

Be sure to [document the new limit](#documentation).

### Add a rate limit key

1. Add a `Labkit::RateLimit::Rule` for the key to `Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits`.
   CE keys are in `lib/gitlab/application_rate_limiter/labkit_adapter/supported_rate_limits.rb`,
   and EE-only keys and EE overrides are in
   `ee/lib/ee/gitlab/application_rate_limiter/labkit_adapter/supported_rate_limits.rb`.
   A key with no rule raises `Gitlab::ApplicationRateLimiter::InvalidKeyError`.

   ```ruby
   issues_create: ::Labkit::RateLimit::Rule.new(
     name: 'limit_issues_by_project_user_external_author',
     characteristics: %i[project user external_author],
     limit: -> { Gitlab::CurrentSettings.current_application_settings.issues_create_limit },
     period: 1.minute,
     action: :limit
   ),
   ```

1. Set the rule attributes.
   For what each attribute does, see [Rule](https://gitlab.com/gitlab-org/ruby/gems/labkit-ruby/-/blob/master/lib/labkit/rate_limit/README.md#rule) in the LabKit documentation.
   In GitLab:
   - `name` must start with `limit_`. A spec fails for a name without the prefix.
   - `action` must be `:limit`.
   - `limit` is usually a lambda that reads the limit from application settings.
   - `characteristics` use the names in [characteristic names](#characteristic-names).
   - `count_distinct` is optional. Set to `:project_id` to count distinct resources passed as
     `resource:` instead of counting calls. For an example, see the EE
     `unique_project_downloads_for_application` key in
     `ee/lib/ee/gitlab/application_rate_limiter/labkit_adapter/supported_rate_limits.rb`.
1. Call the key from the code that performs the action. For more information, see
   [check a rate limit](#check-a-rate-limit).

A spec requires every key to define a limit and a period. Keys that receive their limit from
the caller, or count a cost instead of calls, are listed as exceptions in
`spec/lib/gitlab/application_rate_limiter/labkit_adapter/supported_rate_limits_spec.rb`.

### Check a rate limit

Use one of these methods:

- `Gitlab::ApplicationRateLimiter.throttled?`: Counts the action and returns `true` when the
  action is over the limit.
- `Gitlab::ApplicationRateLimiter.throttled_request?`: Same as `throttled?`, and also honors the
  rate limit bypass header and logs throttled requests to `auth.log` with the message
  `Application_Rate_Limiter_Request`. Use it for web requests.
- `Gitlab::ApplicationRateLimiter.peek`: Returns whether the action is over the limit, without counting it.
- `Gitlab::ApplicationRateLimiter.resource_usage_throttled?`: Adds a cost, such as database
  duration, instead of one call. The Sidekiq resource usage middleware uses it.

In controllers, use the `CheckRateLimit` concern, which calls `throttled_request?`.
In services, use the `RateLimitedService` concern.

Pass `scope:` as a hash keyed by the characteristic names the key registers in
`SupportedRateLimits`:

```ruby
Gitlab::ApplicationRateLimiter.throttled?(:issues_create, scope: { project: project, user: current_user })
```

ActiveRecord values contribute their primary key and primitives their string
form. Omitted (or `nil`) characteristics are keyed on labkit's `_unknown_`
sentinel, and a scope key that is not a characteristic of the rule raises in
development and test.

### Characteristic names

Each rate limit key registers an ordered list of characteristics.
Names are bare nouns: `:user`, `:project`, `:ip`, `:group`, `:namespace`. They
are never suffixed with `_id`, even though an ActiveRecord value contributes its
primary key.

Limits that are global rather than per-actor register a single characteristic
literally named `scope`, so the call reads `scope: { scope: :global }`:

```ruby
Gitlab::ApplicationRateLimiter.throttled?(:fetch_google_ip_list, scope: { scope: :global })
```

The repetition is the characteristic name colliding with the keyword argument
name. It is not a mistake.

The `RateLimitedService` concern takes the same characteristic names, mapped to
the service methods that supply each value:

```ruby
rate_limit key: :issues_create,
  opts: { scope: { project: :project, user: :current_user } }
```

A characteristic name is part of the Redis key. Renaming one starts a new
counter and discards whatever the old one had accumulated, so treat renames as a
behavior change rather than a refactor.

## Rate limiting architecture

For the design of LabKit rate limiting and proposed changes, see
[Unified rate limiting architecture](https://handbook.gitlab.com/handbook/engineering/architecture/design-documents/unified_rate_limiting/).
