<script>
import {
  GlAlert,
  GlBadge,
  GlButton,
  GlExperimentBadge,
  GlLink,
  GlLoadingIcon,
  GlPopover,
  GlSprintf,
} from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { createAlert } from '~/alert';
import { __, s__, sprintf } from '~/locale';
import { visitUrl } from '~/lib/utils/url_utility';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import { groupSecurityPolicyStoreIndexPath } from 'ee/lib/utils/path_helpers/group';
import { ACTIONS } from '../../catalog/actions';
import { RULES } from '../../catalog/rules';
import { TRIGGERS } from '../../catalog/triggers';
import { resolveCatalogEntry } from '../../catalog/helpers';
import {
  NAMESPACE_TYPE_GROUP,
  POLICY_STATUS_ACTIVE,
  POLICY_STATUS_DISABLED,
} from '../../constants';
import {
  containerQueryVariables,
  policyMutationVariables,
  policyStoreFrom,
  policyStoreId,
} from '../../policies';
import { EVALUATIONS_PAGE_SIZE, toEvaluations } from '../../evaluations';
import getPolicyEvaluations from '../../graphql/get_policy_evaluations.query.graphql';
import getGroupPolicyEvaluations from '../../graphql/get_group_policy_evaluations.query.graphql';
import { apiErrorMessage, isPolicyWritable, readMutationPayload } from '../../utils';
import singlePolicyQuery from '../../single_policy_query';
import governPolicyUpdateMutation from '../../graphql/govern_policy_update.mutation.graphql';
import governPolicyDeleteMutation from '../../graphql/govern_policy_delete.mutation.graphql';
import { deserializePolicyData } from '../editor/serializer';
import { modeLabel, modeVariant, statusLabel, statusVariant, scopeLabel } from '../list/utils';
import EvaluationsSection from './evaluations_section.vue';
import SummarySection from './summary_section.vue';

export default {
  name: 'PolicyStoreDetailRoot',
  components: {
    GlAlert,
    GlBadge,
    GlButton,
    GlExperimentBadge,
    GlLink,
    GlLoadingIcon,
    GlPopover,
    GlSprintf,
    EvaluationsSection,
    SummarySection,
    TimeAgoTooltip,
  },
  i18n: {
    deleteConfirmButton: __('Delete'),
  },
  inject: {
    organizationId: {},
    namespacePath: { default: '' },
    namespaceType: {},
    policyId: {},
    canUpdatePolicy: { default: false },
    canDeletePolicy: { default: false },
    listPath: { default: '' },
    editPath: { default: '' },
  },
  data() {
    return {
      policy: null,
      policyError: false,
      evaluations: null,
      deleting: false,
      toggling: false,
      sourceElementId: uniqueId('policy-source-'),
    };
  },
  apollo: {
    policy: singlePolicyQuery,
    // Separate from the policy read: the evaluations are the engine's record of what
    // the policy did, so a denied or failed read of them must not take the policy page
    // down with it. A null connection and a failed request both leave `evaluations`
    // null, which the section reads as "could not be loaded" rather than "never ran".
    evaluations: {
      query() {
        return this.isGroupContext ? getGroupPolicyEvaluations : getPolicyEvaluations;
      },
      variables() {
        return {
          ...containerQueryVariables(this.namespaceType, this.namespaceIdentifier),
          policyId: policyStoreId(this.policyId),
          first: EVALUATIONS_PAGE_SIZE,
        };
      },
      skip() {
        return policyStoreId(this.policyId) === null;
      },
      // An evaluations log gains rows on every engine run, so a cached read is
      // staler here than anywhere else on the page: the first read comes from
      // the network, and later reads follow the cache.
      fetchPolicy: 'network-only',
      nextFetchPolicy: 'cache-first',
      update(data) {
        return toEvaluations(policyStoreFrom(data, this.namespaceType)?.policyEvaluations);
      },
      error(error) {
        Sentry.captureException(error);
        this.evaluations = null;
      },
    },
  },
  computed: {
    policyLoading() {
      return this.$apollo.queries.policy.loading;
    },
    evaluationsLoading() {
      return this.$apollo.queries.evaluations.loading;
    },
    isGroupContext() {
      return this.namespaceType === NAMESPACE_TYPE_GROUP;
    },
    namespaceIdentifier() {
      return this.isGroupContext ? this.namespacePath : this.organizationId;
    },
    isActive() {
      return this.policy.status === POLICY_STATUS_ACTIVE;
    },
    // The store rejects a write from any container but the policy's own, with
    // the same "not found" it gives an unknown id. Disabling here turns that
    // into an answer the page can explain instead of a failed request.
    isWritable() {
      return isPolicyWritable(this.policy, {
        namespaceType: this.namespaceType,
        namespacePath: this.namespacePath,
      });
    },
    // Two independent gates: the ability says whether this user may write at
    // all, isWritable whether this container is the one that owns the policy.
    canEdit() {
      return this.canUpdatePolicy && this.isWritable;
    },
    canDelete() {
      return this.canDeletePolicy && this.isWritable;
    },
    hasActions() {
      return this.canUpdatePolicy || this.canDeletePolicy;
    },
    sourceGroupPath() {
      return this.policy.group ? groupSecurityPolicyStoreIndexPath(this.policy.group.fullPath) : '';
    },
    versionLabel() {
      return sprintf(s__('PolicyStore|Version %{version}'), {
        version: this.policy.version,
      });
    },
    // Nothing names the source when the policy is the container's own and the
    // container is the organization, which is where the reader already is.
    hasSource() {
      return Boolean(this.policy.inherited || this.policy.group);
    },
    sourceMessage() {
      return this.policy.inherited
        ? s__('PolicyStore|Inherited from %{namespace}')
        : s__('PolicyStore|Owned by %{namespace}');
    },
    // The source line is the on-page text Pajamas asks disabled actions to point
    // at; the popover repeats it for pointer users, so both read one condition.
    explainsSource() {
      return !this.isWritable && this.hasSource;
    },
    actionsDescribedBy() {
      return this.explainsSource ? this.sourceElementId : null;
    },
    hasMeta() {
      return Boolean(
        this.policy.version || this.policy.created_at || this.policy.updated_at || this.hasSource,
      );
    },
    regoSections() {
      return [
        {
          testid: 'scope-rego',
          label: s__('PolicyStore|Compiled scope Rego'),
          help: s__(
            'PolicyStore|Read-only Rego the store compiled from the scope. The policy engine evaluates this program to decide where the policy applies.',
          ),
          rego: this.policy.scope_rego,
        },
        {
          testid: 'policy-rego',
          label: s__('PolicyStore|Compiled policy Rego'),
          help: s__(
            'PolicyStore|Read-only Rego the store compiled from the rules. The policy engine evaluates this single program when the trigger fires.',
          ),
          rego: this.policy.policy_rego,
        },
      ].filter(({ rego }) => rego);
    },
    toggleStatusLabel() {
      return this.isActive ? s__('PolicyStore|Disable') : s__('PolicyStore|Enable');
    },
    // The catalog files supply the presentation for the persisted ids, the same
    // lookup the editor and the list use.
    sections() {
      const { trigger, triggerConfig, rules, ruleConfigs, actions, actionConfigs } =
        deserializePolicyData(this.policy);

      return [
        {
          testid: 'trigger',
          label: s__('PolicyStore|Trigger'),
          ids: trigger ? [trigger] : [],
          catalog: TRIGGERS,
          configs: { [trigger]: triggerConfig },
        },
        {
          testid: 'rules',
          label: s__('PolicyStore|Rules'),
          ids: rules,
          catalog: RULES,
          configs: ruleConfigs,
        },
        {
          testid: 'actions',
          label: s__('PolicyStore|Actions'),
          ids: actions,
          catalog: ACTIONS,
          configs: actionConfigs,
        },
      ].map(({ testid, label, ids, catalog, configs }) => ({
        testid,
        label,
        entries: ids.map((id) => resolveCatalogEntry(catalog, id, configs[id])),
      }));
    },
  },
  methods: {
    modeLabel,
    modeVariant,
    statusLabel,
    statusVariant,
    scopeLabel,
    mutationVariables(document, params) {
      return policyMutationVariables({
        document,
        namespaceType: this.namespaceType,
        namespaceIdentifier: this.namespaceIdentifier,
        policyId: this.policyId,
        params,
      });
    },
    // The mutation returns the whole policy, which Apollo normalizes onto the
    // entity this page's query watches, so the badges refresh from the cache
    // without a second read.
    async onToggleStatus() {
      if (!this.canEdit) return;

      this.toggling = true;

      const lifecycleState = this.isActive ? POLICY_STATUS_DISABLED : POLICY_STATUS_ACTIVE;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: governPolicyUpdateMutation,
          variables: this.mutationVariables(governPolicyUpdateMutation, {
            lifecycle_state: lifecycleState,
          }),
        });

        readMutationPayload(data, 'governPolicyUpdate');
      } catch (error) {
        Sentry.captureException(error);
        createAlert({
          message:
            apiErrorMessage(error) ||
            s__('PolicyStore|The policy could not be updated. Try again.'),
        });
      } finally {
        this.toggling = false;
      }
    },
    async onDelete() {
      // Guards re-entrancy: the confirm dialog is awaited before any request,
      // so without this a double-click would open two confirmation flows.
      if (this.deleting || !this.canDelete) return;

      this.deleting = true;

      const confirmed = await confirmAction(
        sprintf(
          s__('PolicyStore|Are you sure you want to delete %{name}? This action cannot be undone.'),
          { name: this.policy.name },
        ),
        {
          title: s__('PolicyStore|Delete policy?'),
          primaryBtnText: this.$options.i18n.deleteConfirmButton,
          primaryBtnVariant: 'danger',
        },
      );

      if (!confirmed) {
        this.deleting = false;
        return;
      }

      try {
        // No cache update: with a list path the full navigation discards the
        // cache; without one the page keeps its last read, as it did before.
        const { data } = await this.$apollo.mutate({
          mutation: governPolicyDeleteMutation,
          variables: this.mutationVariables(governPolicyDeleteMutation),
        });

        readMutationPayload(data, 'governPolicyDelete');

        if (this.listPath) {
          visitUrl(this.listPath);
        } else {
          this.deleting = false;
        }
      } catch (error) {
        Sentry.captureException(error);
        createAlert({
          message:
            apiErrorMessage(error) ||
            s__('PolicyStore|The policy could not be deleted. Try again.'),
        });
        this.deleting = false;
      }
    },
  },
};
</script>

<template>
  <gl-loading-icon v-if="policyLoading" size="lg" class="gl-mt-6" data-testid="policy-loading" />
  <!-- A null policy after loading means not found: unknown id, denied read, or a skipped id. -->
  <gl-alert
    v-else-if="policyError || !policy"
    variant="danger"
    :dismissible="false"
    class="gl-mt-4"
    data-testid="policy-error"
  >
    {{
      s__(
        'PolicyStore|The policy could not be loaded from the Policy Store API. Refresh the page to try again.',
      )
    }}
  </gl-alert>
  <div v-else class="gl-flex gl-flex-col gl-gap-5 gl-pt-6">
    <div class="gl-flex gl-flex-wrap gl-items-start gl-justify-between gl-gap-4">
      <div class="gl-min-w-0">
        <div class="gl-mb-2 gl-flex gl-items-center">
          <h1 class="gl-heading-1 gl-mb-0" data-testid="policy-name">{{ policy.name }}</h1>
          <gl-experiment-badge type="experiment" />
        </div>
        <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
          <gl-badge variant="neutral" data-testid="policy-type">{{ policy.type }}</gl-badge>
          <gl-badge :variant="modeVariant(policy.mode)" data-testid="policy-mode">
            {{ modeLabel(policy.mode) }}
          </gl-badge>
          <gl-badge :variant="statusVariant(policy.status)" data-testid="policy-status">
            {{ statusLabel(policy.status) }}
          </gl-badge>
        </div>
        <p
          v-if="policy.description"
          class="gl-mb-0 gl-mt-3 gl-text-subtle"
          data-testid="policy-description"
        >
          {{ policy.description }}
        </p>
        <ul
          v-if="hasMeta"
          class="gl-mb-0 gl-mt-3 gl-flex gl-list-none gl-flex-wrap gl-gap-x-4 gl-gap-y-1 gl-p-0 gl-text-sm gl-text-subtle"
          data-testid="policy-meta"
        >
          <li v-if="policy.version" data-testid="policy-version">{{ versionLabel }}</li>
          <li v-if="policy.created_at" data-testid="policy-created-at">
            <gl-sprintf :message="s__('PolicyStore|Created %{timeAgo}')">
              <template #timeAgo><time-ago-tooltip :time="policy.created_at" /></template>
            </gl-sprintf>
          </li>
          <li v-if="policy.updated_at" data-testid="policy-updated-at">
            <gl-sprintf :message="s__('PolicyStore|Updated %{timeAgo}')">
              <template #timeAgo><time-ago-tooltip :time="policy.updated_at" /></template>
            </gl-sprintf>
          </li>
          <li v-if="hasSource" :id="sourceElementId" data-testid="policy-source">
            <gl-sprintf v-if="policy.group" :message="sourceMessage">
              <template #namespace>
                <gl-link :href="sourceGroupPath">{{ policy.group.name }}</gl-link>
              </template>
            </gl-sprintf>
            <span v-else>{{ s__('PolicyStore|Inherited from the organization') }}</span>
          </li>
        </ul>
      </div>
      <div v-if="hasActions" class="gl-flex-shrink-0">
        <span ref="policyActions" class="gl-flex gl-gap-3">
          <!-- No href when the policy is not writable: a disabled GlButton still
               renders an anchor, which middle-click and the context menu follow. -->
          <gl-button
            v-if="canUpdatePolicy"
            :href="canEdit ? editPath : null"
            :disabled="!canEdit"
            :aria-describedby="actionsDescribedBy"
            data-testid="edit-policy-button"
          >
            {{ s__('PolicyStore|Edit policy') }}
          </gl-button>
          <gl-button
            v-if="canUpdatePolicy"
            :loading="toggling"
            :disabled="!canEdit"
            :aria-describedby="actionsDescribedBy"
            data-testid="toggle-status-button"
            @click="onToggleStatus"
          >
            {{ toggleStatusLabel }}
          </gl-button>
          <gl-button
            v-if="canDeletePolicy"
            category="secondary"
            variant="danger"
            :loading="deleting"
            :disabled="!canDelete"
            :aria-describedby="actionsDescribedBy"
            data-testid="delete-policy-button"
            @click="onDelete"
          >
            {{ $options.i18n.deleteConfirmButton }}
          </gl-button>
        </span>
        <gl-popover
          v-if="explainsSource"
          triggers="hover focus"
          :target="() => $refs.policyActions"
          placement="bottom"
          data-testid="policy-actions-popover"
        >
          <gl-sprintf
            v-if="policy.group"
            :message="
              s__('PolicyStore|This policy belongs to %{namespace} and can only be changed there.')
            "
          >
            <template #namespace>
              <gl-link :href="sourceGroupPath">{{ policy.group.name }}</gl-link>
            </template>
          </gl-sprintf>
          <span v-else>{{
            s__(
              'PolicyStore|This policy belongs to the organization and can only be changed there.',
            )
          }}</span>
        </gl-popover>
      </div>
    </div>

    <summary-section
      v-for="section in sections"
      :key="section.testid"
      :label="section.label"
      :entries="section.entries"
      :testid="section.testid"
    />

    <summary-section :label="s__('PolicyStore|Scope')" testid="scope">
      <p class="gl-mb-0">{{ scopeLabel(policy.scopedProjectsCount) }}</p>
    </summary-section>

    <evaluations-section :evaluations="evaluations" :loading="evaluationsLoading" />

    <summary-section
      v-for="rego in regoSections"
      :key="rego.testid"
      :label="rego.label"
      :testid="rego.testid"
    >
      <p class="gl-mb-3 gl-text-sm gl-text-subtle">{{ rego.help }}</p>
      <pre
        tabindex="0"
        role="region"
        :aria-label="rego.label"
        class="gl-mb-0 gl-max-h-48 gl-overflow-y-auto gl-whitespace-pre-wrap gl-rounded-base gl-bg-subtle gl-p-3 gl-text-sm"
      ><code>{{ rego.rego }}</code></pre>
    </summary-section>
  </div>
</template>
