<script>
import { GlBadge, GlAlert, GlButton, GlLink, GlSprintf, GlCollapsibleListbox } from '@gitlab/ui';
import { mapValues, uniqBy } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import { SEVERITY_LEVELS } from '~/vue_shared/constants';
import { nDaysBefore, toISODateFormat } from '~/lib/utils/datetime_utility';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import {
  NAMESPACE_GROUP,
  NAMESPACE_PROJECT,
  TIME_WINDOW_OPTIONS,
  DEFAULT_TIME_WINDOW_DAYS,
  ICON_BLOCKED,
  ICON_WARNED,
  SEVERITY_ICONS,
} from '../constants';
import groupRuleActivityQuery from '../graphql/queries/group_dependency_firewall_rule_activity.query.graphql';
import projectRuleActivityQuery from '../graphql/queries/project_dependency_firewall_rule_activity.query.graphql';
import MetricCard from './metric_card.vue';
import ActivePoliciesTable from './active_policies_table.vue';

// Only the two most severe levels fit on one line in the card; the total covers every level.
const SHOWN_SEVERITIES = ['CRITICAL', 'HIGH'];

const EMPTY_SUMMARY = {
  blocked: 0,
  warned: 0,
  totalTriggers: 0,
  vulnerabilitiesPrevented: 0,
  vulnerabilitiesPreventedBySeverity: [],
  maliciousPackagesPrevented: 0,
  maliciousPackagesWarnedOnly: 0,
  licenseRisksPrevented: 0,
  licenseRisksWarnedOnly: 0,
};

export default {
  name: 'DashboardV2App',
  components: {
    GlBadge,
    GlAlert,
    GlButton,
    GlLink,
    GlSprintf,
    GlCollapsibleListbox,
    DetailLayout,
    MetricCard,
    ActivePoliciesTable,
  },
  props: {
    fullPath: {
      type: String,
      required: true,
    },
    namespaceType: {
      type: String,
      required: true,
      validator: (value) => [NAMESPACE_GROUP, NAMESPACE_PROJECT].includes(value),
    },
    newPolicyPath: {
      type: String,
      required: true,
    },
    disableNewPolicy: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  apollo: {
    dependencyFirewall: {
      query() {
        return this.namespaceType === NAMESPACE_PROJECT
          ? projectRuleActivityQuery
          : groupRuleActivityQuery;
      },
      // The summary is window-scoped but cached by the Apollo query key, so always refetch
      // when the time window changes rather than serving a stale cached window.
      fetchPolicy: 'cache-and-network',
      variables() {
        return { fullPath: this.fullPath, from: this.fromDate };
      },
      result({ data }) {
        if (data?.dependencyFirewall) {
          this.hasError = false;
        }
      },
      error() {
        this.hasError = true;
      },
    },
  },
  data() {
    return {
      dependencyFirewall: null,
      hasError: false,
      timeWindowDays: DEFAULT_TIME_WINDOW_DAYS,
    };
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.dependencyFirewall.loading;
    },
    fromDate() {
      // Compute in UTC so the day boundary matches the backends
      return toISODateFormat(nDaysBefore(new Date(), this.timeWindowDays - 1, { utc: true }), true);
    },
    timeWindowToggleText() {
      return TIME_WINDOW_OPTIONS.find((option) => option.value === this.timeWindowDays)?.text;
    },
    policies() {
      const rules = this.dependencyFirewall?.dependencyFirewallRuleActivity || [];
      const enabledRules = rules.filter((rule) => rule.enabled);
      // The API returns one row per rule; list each policy once. JSON keeps the key unambiguous,
      // since policy names can contain slashes.
      // TODO: dedupe on the policy ID: https://gitlab.com/gitlab-org/gitlab/-/work_items/631829
      const uniquePolicies = uniqBy(enabledRules, (rule) =>
        JSON.stringify([
          rule.source?.namespace?.fullPath ?? rule.source?.project?.fullPath,
          rule.policyName,
        ]),
      );

      return uniquePolicies.map((rule) => ({
        id: rule.id,
        name: rule.policyName,
        source: rule.source,
        sourceRelationship: rule.sourceRelationship,
        scope: rule.scope,
        mode: rule.mode,
        updatedAt: rule.lastModified?.at,
      }));
    },
    summary() {
      const summary = this.dependencyFirewall?.dependencyFirewallActivitySummary || {};
      // The prevented fields are null when not available, so default each field, not the object.
      return mapValues(EMPTY_SUMMARY, (fallback, key) => summary[key] ?? fallback);
    },
    metrics() {
      return [
        {
          key: 'packageEvaluations',
          title: s__('DependencyFirewall|Package evaluations'),
          value: this.summary.totalTriggers,
          breakdown: [
            {
              key: 'blocked',
              value: this.summary.blocked,
              label: s__('DependencyFirewall|Blocked'),
              icon: ICON_BLOCKED,
              variant: 'danger',
            },
            {
              key: 'warned',
              value: this.summary.warned,
              label: s__('DependencyFirewall|Warned'),
              icon: ICON_WARNED,
              variant: 'warning',
            },
          ],
        },
        {
          key: 'vulnerabilitiesPrevented',
          title: s__('DependencyFirewall|Vulnerabilities prevented'),
          value: this.summary.vulnerabilitiesPrevented,
          breakdown: SHOWN_SEVERITIES.map((severity) => {
            const key = severity.toLowerCase();
            return {
              key,
              value:
                this.summary.vulnerabilitiesPreventedBySeverity.find(
                  (item) => item.severity === severity,
                )?.count ?? 0,
              label: SEVERITY_LEVELS[key],
              icon: SEVERITY_ICONS[severity],
              variant: 'danger',
            };
          }),
        },
        {
          key: 'maliciousPackagesPrevented',
          title: s__('DependencyFirewall|Malicious packages prevented'),
          value: this.summary.maliciousPackagesPrevented,
          breakdown: [
            {
              key: 'maliciousWarnedOnly',
              value: this.summary.maliciousPackagesWarnedOnly,
              label: s__('DependencyFirewall|Warned only'),
              icon: ICON_WARNED,
              variant: 'warning',
            },
          ],
        },
        {
          key: 'licenseRisksPrevented',
          title: s__('DependencyFirewall|License risks prevented'),
          value: this.summary.licenseRisksPrevented,
          breakdown: [
            {
              key: 'licenseWarnedOnly',
              value: this.summary.licenseRisksWarnedOnly,
              label: s__('DependencyFirewall|Warned only'),
              icon: ICON_WARNED,
              variant: 'warning',
            },
          ],
        },
      ];
    },
    subtitle() {
      const message =
        this.namespaceType === NAMESPACE_PROJECT
          ? s__(
              'DependencyFirewall|Every package entering %{namespaceName} is evaluated against the policies in effect for its project.',
            )
          : s__(
              'DependencyFirewall|Every package entering %{namespaceName} is evaluated against the policies in effect for its group.',
            );
      return sprintf(message, { namespaceName: this.fullPath });
    },
  },
  timeWindowOptions: TIME_WINDOW_OPTIONS,
  creditsDocsLink: helpPagePath('subscriptions/gitlab_credits'),
};
</script>

<template>
  <detail-layout :description="subtitle">
    <template #heading>
      <span class="gl-inline-flex gl-items-center gl-gap-3">
        {{ s__('DependencyFirewall|Dependency firewall') }}
        <gl-badge variant="info">{{ __('Beta') }}</gl-badge>
      </span>
    </template>

    <template #actions>
      <span id="dependency-firewall-time-window-label" class="gl-sr-only">
        {{ s__('DependencyFirewall|Time period') }}
      </span>
      <gl-collapsible-listbox
        v-model="timeWindowDays"
        :items="$options.timeWindowOptions"
        :toggle-text="timeWindowToggleText"
        icon="clock"
        toggle-aria-labelled-by="dependency-firewall-time-window-label"
        data-testid="time-window-listbox"
      />
      <gl-button
        v-if="!disableNewPolicy"
        data-testid="new-policy-button"
        variant="confirm"
        icon="plus"
        :href="newPolicyPath"
      >
        {{ s__('DependencyFirewall|New policy') }}
      </gl-button>
    </template>

    <template #alerts>
      <!-- Copy is duplicated in the shared HAML component (security/dependency_firewall/beta_credits_alert_component.html.haml); keep both in sync (shared msgids). -->
      <gl-alert
        variant="warning"
        :title="s__('DependencyFirewall|Charges may be incurred at the end of beta')"
        :dismissible="false"
        data-testid="ga-billing-alert"
        class="gl-mb-5"
      >
        <gl-sprintf
          :message="
            s__(
              'DependencyFirewall|Dependency Firewall is free during the beta period. Once generally available, it will be a paid feature billed through %{linkStart}GitLab Credits%{linkEnd}. You\'ll need to opt in before anything is charged, and we\'ll give you advance notice ahead of general availability.',
            )
          "
        >
          <template #link="{ content }">
            <gl-link :href="$options.creditsDocsLink" target="_blank">
              {{ content }}
            </gl-link>
          </template>
        </gl-sprintf>
      </gl-alert>

      <gl-alert
        v-if="hasError"
        variant="danger"
        :dismissible="false"
        data-testid="error-alert"
        class="gl-mb-5"
      >
        {{ s__('DependencyFirewall|Failed to load dependency firewall activity.') }}
      </gl-alert>
    </template>

    <div
      v-if="!hasError"
      class="gl-mb-5 gl-grid gl-grid-cols-1 gl-gap-5 @md/panel:gl-grid-cols-2 @xl/panel:gl-grid-cols-4"
    >
      <metric-card
        v-for="metric in metrics"
        :key="metric.key"
        :data-testid="`metric-card-${metric.key}`"
        :title="metric.title"
        :value="metric.value"
        :breakdown="metric.breakdown"
        :loading="isLoading"
      />
    </div>

    <active-policies-table v-if="!hasError" :items="policies" :loading="isLoading" />
  </detail-layout>
</template>
