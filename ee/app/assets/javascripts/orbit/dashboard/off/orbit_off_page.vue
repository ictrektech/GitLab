<script>
import { GlAlert, GlButton, GlEmptyState, GlLoadingIcon } from '@gitlab/ui';
import orbitLogoUrl from 'ee_images/illustrations/orbit/orbit-logo.svg?url';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { helpPagePath } from '~/helpers/help_page_helper';
import { toNounSeriesText } from '~/lib/utils/grammar';
import { n__, s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { InternalEvents } from '~/tracking';
import { ACCESS_STATE } from 'ee/orbit/access/constants';
import {
  TURN_ON_ACTION,
  canTurnOn,
  startsTrial,
  trialEnded,
  turnOnAction,
} from 'ee/orbit/access/turn_on_action';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import TrialUnavailableAlert from 'ee/orbit/components/trial/trial_unavailable_alert.vue';
import orbitStartTrialMutation from 'ee/orbit/graphql/mutations/orbit_start_trial.mutation.graphql';
import orbitUpdateMutation from 'ee/orbit/graphql/mutations/orbit_update.mutation.graphql';
import { INSTANCE_TEXT, instanceTrialText } from 'ee/orbit/access/instance_text';
import { daysText, freeCreditsText } from 'ee/orbit/utils/trial_offer_text';
import TurnOnConfirmModal from 'ee/orbit/shared/groups/turn_on_confirm_modal.vue';
import { turnOnTrackingLabel } from 'ee/orbit/shared/groups/utils';
import offOwnedGroupsQuery from './graphql/off_owned_groups.query.graphql';
import OffGroupsTable from './off_groups_table.vue';

// orbit.access can be resolved for at most 10 groups in one request.
const GROUPS_LIMIT = 10;

const HEADER = {
  TRIAL: 'trial',
  OFF: 'off',
  NOT_LICENSED: 'not_licensed',
  NOT_AVAILABLE: 'not_available',
  TRIAL_ENDED: 'trial_ended',
  INSTANCE_TRIAL: 'instance_trial',
  INSTANCE_TRIAL_ENDED: 'instance_trial_ended',
  INSTANCE_NOT_AVAILABLE: 'instance_not_available',
};

const INSTANCE_SALES_HEADERS = [HEADER.INSTANCE_TRIAL_ENDED, HEADER.INSTANCE_NOT_AVAILABLE];

const toRow = (group) => {
  const access = group.orbit?.access;
  const trialActive = access?.state === ACCESS_STATE.TRIAL_ACTIVE;

  return {
    key: group.fullPath,
    namespaceId: getIdFromGraphQLId(group.id),
    name: group.name,
    avatarUrl: group.avatarUrl,
    action: turnOnAction(group),
    offer: access?.trial?.offer,
    trialActive,
    trialEndsOn: trialActive ? access.trial?.expiresOn : null,
  };
};

export default {
  name: 'OrbitOffPage',
  components: {
    ContactSalesButton,
    GlAlert,
    GlButton,
    GlEmptyState,
    GlLoadingIcon,
    OffGroupsTable,
    TrialUnavailableAlert,
    TurnOnConfirmModal,
  },
  mixins: [InternalEvents.mixin()],
  inject: ['orbitPlatform'],
  emits: ['turned-on'],
  apollo: {
    ownedGroups: {
      query: offOwnedGroupsQuery,
      variables: { first: GROUPS_LIMIT },
      update: (data) => data.orbit?.groups?.nodes ?? [],
      result({ data }) {
        if (!data) return;

        this.loadFailed = false;
        this.hasMoreGroups = data.orbit?.groups?.pageInfo.hasNextPage ?? false;
        if (this.turnOnRows.length === 1 && !this.selected.length) {
          this.selected = [this.turnOnRows[0].key];
        }
      },
      error(error) {
        this.loadFailed = true;
        // The server already logs GraphQL errors.
        if (!error.graphQLErrors.length) Sentry.captureException(error);
      },
    },
  },
  data() {
    return {
      ownedGroups: [],
      hasMoreGroups: false,
      loadFailed: false,
      selected: [],
      modalVisible: false,
      turningOn: false,
      turnOnFailureAlert: null,
    };
  },
  computed: {
    saas() {
      return this.orbitPlatform.saas;
    },
    initialLoading() {
      return this.$apollo.queries.ownedGroups.loading && !this.ownedGroups.length;
    },
    reloading() {
      return this.$apollo.queries.ownedGroups.loading && this.ownedGroups.length > 0;
    },
    rows() {
      return this.ownedGroups.map(toRow);
    },
    ownsNoGroups() {
      return this.rows.length === 0;
    },
    turnOnRows() {
      return this.rows.filter((row) => canTurnOn(row.action));
    },
    hasTurnOnRows() {
      return this.turnOnRows.length > 0;
    },
    trialRows() {
      return this.rows.filter((row) => startsTrial(row.action));
    },
    trialEndedRows() {
      return this.rows.filter((row) => trialEnded(row.action));
    },
    selectedRows() {
      return this.turnOnRows.filter((row) => this.selected.includes(row.key));
    },
    confirmGroups() {
      return this.selectedRows.map((row) => ({
        fullPath: row.key,
        name: row.name,
        startsTrial: startsTrial(row.action),
        offer: row.offer,
      }));
    },
    unavailableRow() {
      return this.rows.find((row) => row.action === TURN_ON_ACTION.UNAVAILABLE) ?? null;
    },
    hasUnavailableRows() {
      return Boolean(this.unavailableRow);
    },
    offer() {
      return this.trialRows.find((row) => row.offer)?.offer;
    },
    instanceTrialEndsOn() {
      if (this.saas) return null;

      return this.rows.find((row) => row.trialEndsOn)?.trialEndsOn ?? null;
    },
    header() {
      if (this.trialRows.length) return HEADER.TRIAL;
      if (this.instanceTrialEndsOn && this.hasTurnOnRows) return HEADER.INSTANCE_TRIAL;
      if (this.ownsNoGroups || this.hasUnavailableRows || this.hasTurnOnRows) return HEADER.OFF;
      if (!this.saas) {
        return this.trialEndedRows.length
          ? HEADER.INSTANCE_TRIAL_ENDED
          : HEADER.INSTANCE_NOT_AVAILABLE;
      }
      if (this.rows.every((row) => row.action === TURN_ON_ACTION.NOT_LICENSED)) {
        return HEADER.NOT_LICENSED;
      }
      if (this.trialEndedRows.length) return HEADER.TRIAL_ENDED;

      return HEADER.NOT_AVAILABLE;
    },
    showHeaderSales() {
      return INSTANCE_SALES_HEADERS.includes(this.header);
    },
    title() {
      switch (this.header) {
        case HEADER.TRIAL:
        case HEADER.INSTANCE_TRIAL:
          return s__('Orbit|Try GitLab Orbit');
        case HEADER.NOT_LICENSED:
          return s__('Orbit|GitLab Orbit is available on Premium and Ultimate');
        case HEADER.INSTANCE_TRIAL_ENDED:
          return INSTANCE_TEXT.TRIAL_ENDED_TITLE;
        case HEADER.INSTANCE_NOT_AVAILABLE:
          return INSTANCE_TEXT.NOT_AVAILABLE_TITLE;
        case HEADER.TRIAL_ENDED:
          return this.trialEndedRows.length === 1
            ? s__('Orbit|Your GitLab Orbit trial has ended')
            : s__('Orbit|Your GitLab Orbit trials have ended');
        case HEADER.NOT_AVAILABLE:
          return s__('Orbit|GitLab Orbit is not available for your groups');
        default:
          return s__('Orbit|GitLab Orbit is not turned on for your groups yet');
      }
    },
    detail() {
      switch (this.header) {
        case HEADER.TRIAL:
          return this.trialDetail;
        case HEADER.INSTANCE_TRIAL:
          return instanceTrialText(this.instanceTrialEndsOn);
        case HEADER.INSTANCE_TRIAL_ENDED:
          return INSTANCE_TEXT.TRIAL_ENDED;
        case HEADER.INSTANCE_NOT_AVAILABLE:
          return INSTANCE_TEXT.NOT_AVAILABLE;
        case HEADER.NOT_AVAILABLE:
          return s__('Orbit|Contact sales to get GitLab Orbit for your groups.');
        case HEADER.NOT_LICENSED:
          return s__('Orbit|Contact sales to upgrade and get GitLab Orbit for your groups.');
        case HEADER.TRIAL_ENDED:
          return s__('Orbit|Contact sales to keep using GitLab Orbit for your groups.');
        default:
          return '';
      }
    },
    trialDetail() {
      if (!this.offer) {
        return s__(
          'Orbit|When you turn on GitLab Orbit, each eligible group starts its own trial. When the trial ends, contact sales to keep using GitLab Orbit for that group.',
        );
      }

      return sprintf(
        s__(
          'Orbit|When you turn on GitLab Orbit, each eligible group gets its own %{credits} for GitLab Orbit, valid for %{days}. When the credits run out or the %{days} end, contact sales to keep using GitLab Orbit for that group.',
        ),
        {
          credits: freeCreditsText(this.offer.initialCredits),
          days: daysText(this.offer.durationDays),
        },
      );
    },
    selectedSummary() {
      return sprintf(s__('Orbit|%{selected} of %{total} groups selected'), {
        selected: this.selectedRows.length,
        total: this.turnOnRows.length,
      });
    },
    moreGroupsText() {
      return sprintf(
        n__(
          'Orbit|This list shows your first %{count} top-level group. To turn on GitLab Orbit for another group you own, go to the GitLab Orbit settings of that group.',
          'Orbit|This list shows your first %{count} top-level groups. To turn on GitLab Orbit for another group you own, go to the GitLab Orbit settings of that group.',
          GROUPS_LIMIT,
        ),
        { count: GROUPS_LIMIT },
      );
    },
  },
  methods: {
    async turnOn() {
      this.turnOnFailureAlert?.dismiss();
      this.turningOn = true;
      this.trackEvent('click_orbit_turn_on_from_off_page', {
        label: turnOnTrackingLabel(this.confirmGroups),
        value: this.selectedRows.length,
      });

      const rows = this.selectedRows;
      const errors = await Promise.all(rows.map((row) => this.turnOnGroup(row)));
      const failures = rows
        .map((row, index) => ({ name: row.name, error: errors[index] }))
        .filter(({ error }) => error);

      this.turningOn = false;
      this.modalVisible = false;

      if (failures.length) this.alertTurnOnFailures(failures);
      if (failures.length < rows.length) {
        this.$emit('turned-on');
      } else {
        this.$apollo.queries.ownedGroups.refetch();
      }
    },
    async turnOnGroup(row) {
      const startTrial = startsTrial(row.action);

      try {
        const { data } = await this.$apollo.mutate(
          startTrial
            ? { mutation: orbitStartTrialMutation, variables: { groupPath: row.key } }
            : {
                mutation: orbitUpdateMutation,
                variables: { input: { groupPath: row.key, enabled: true } },
              },
        );
        const payload = startTrial ? data.orbitStartTrial : data.orbitUpdate;

        return payload.errors[0] ?? null;
      } catch (error) {
        const [graphQLError] = error.graphQLErrors ?? [];
        if (graphQLError) return graphQLError.message;

        Sentry.captureException(error);
        return s__('Orbit|Could not turn on GitLab Orbit. Try again.');
      }
    },
    alertTurnOnFailures(failures) {
      const reasons =
        failures.length === 1
          ? failures[0].error
          : failures
              .map(({ name, error }) =>
                sprintf(s__('Orbit|%{group}: %{reason}'), { group: name, reason: error }),
              )
              .join(' ');

      this.turnOnFailureAlert = createAlert({
        title: sprintf(s__('Orbit|Could not turn on GitLab Orbit for %{groups}'), {
          groups: toNounSeriesText(failures.map(({ name }) => name)),
        }),
        message: reasons,
      });
    },
    loadGroups() {
      this.$apollo.queries.ownedGroups.refetch();
    },
  },
  docsPath: helpPagePath('integration/orbit'),
  orbitLogoUrl,
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-6" data-testid="orbit-off-page">
    <gl-loading-icon
      v-if="initialLoading"
      size="lg"
      class="gl-mt-11"
      :label="s__('Orbit|Loading groups')"
    />

    <gl-alert
      v-else-if="loadFailed"
      variant="danger"
      :dismissible="false"
      :primary-button-text="s__('Orbit|Try again')"
      data-testid="orbit-off-load-error"
      @primary-action="loadGroups"
    >
      {{ s__('Orbit|Could not load groups.') }}
    </gl-alert>

    <template v-else>
      <trial-unavailable-alert
        v-if="hasUnavailableRows"
        glm-content="orbit-off-page"
        :namespace-id="unavailableRow.namespaceId"
        :reloading="reloading"
        @retry="loadGroups"
      />

      <gl-empty-state :svg-path="$options.orbitLogoUrl" :svg-height="96">
        <template #title>
          <div class="gl-flex gl-flex-col gl-items-center gl-gap-3">
            <h1 class="gl-my-0 gl-text-size-h-display gl-font-bold gl-leading-36 gl-text-heading">
              {{ title }}
            </h1>
          </div>
        </template>
        <template #description>
          <span class="gl-text-sm" data-testid="orbit-off-detail">
            {{
              s__(
                'Orbit|GitLab Orbit connects work items, merge requests, pipelines, and code, so you, GitLab Duo, and other AI tools can answer questions across projects.',
              )
            }}
            {{ detail }}
          </span>
          <span v-if="ownsNoGroups" class="gl-text-sm" data-testid="orbit-off-ask-owner">
            {{
              s__(
                'Orbit|To use GitLab Orbit, ask an Owner of your top-level group to turn it on from this page. When GitLab Orbit is on, you can use it here.',
              )
            }}
          </span>
        </template>
        <template v-if="ownsNoGroups" #actions>
          <gl-button :href="$options.docsPath">{{
            s__('Orbit|Learn more about GitLab Orbit')
          }}</gl-button>
        </template>
        <template v-else-if="showHeaderSales" #actions>
          <contact-sales-button glm-content="orbit-off-page" />
        </template>
      </gl-empty-state>

      <section
        v-if="!ownsNoGroups"
        class="gl-mx-auto gl-flex gl-w-full gl-max-w-88 gl-flex-col gl-gap-4"
      >
        <div class="gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3">
          <div>
            <h2 class="gl-heading-4 gl-mb-1">{{ s__('Orbit|Groups') }}</h2>
            <p
              v-if="turnOnRows.length > 1"
              class="gl-mb-0 gl-text-subtle"
              data-testid="orbit-off-selected-summary"
            >
              {{ selectedSummary }}
            </p>
          </div>
          <gl-button
            v-if="hasTurnOnRows"
            variant="confirm"
            :disabled="!selectedRows.length"
            :loading="turningOn"
            data-testid="orbit-off-turn-on"
            @click="modalVisible = true"
          >
            {{ s__('Orbit|Turn on GitLab Orbit') }}
          </gl-button>
        </div>

        <off-groups-table :rows="rows" :selected="selected" @update:selected="selected = $event" />

        <div class="gl-flex gl-flex-col gl-gap-2 gl-text-sm gl-text-subtle">
          <p v-if="hasTurnOnRows" class="gl-mb-0">
            {{
              s__(
                'Orbit|Indexing starts when you turn on GitLab Orbit and can take from several minutes to a few hours.',
              )
            }}
          </p>
          <p v-if="hasMoreGroups" class="gl-mb-0" data-testid="orbit-off-more-groups">
            {{ moreGroupsText }}
          </p>
          <p class="gl-mb-0" data-testid="orbit-off-other-groups">
            {{
              s__(
                'Orbit|To use GitLab Orbit in another group, ask an Owner of that group to turn it on.',
              )
            }}
          </p>
        </div>
      </section>

      <turn-on-confirm-modal
        :visible="modalVisible"
        :groups="confirmGroups"
        :loading="turningOn"
        :instance-trial-ends-on="instanceTrialEndsOn"
        @confirm="turnOn"
        @hide="modalVisible = false"
      />
    </template>
  </div>
</template>
