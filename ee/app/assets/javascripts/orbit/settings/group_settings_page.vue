<script>
import { GlAlert, GlIcon, GlSkeletonLoader, GlToggle } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { ERROR_POLICY_ALL } from '~/lib/graphql';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { formatNumber, n__, s__, sprintf } from '~/locale';
import { InternalEvents } from '~/tracking';
import groupSettingsQuery from '../graphql/queries/group_settings.query.graphql';
import orbitStartTrialMutation from '../graphql/mutations/orbit_start_trial.mutation.graphql';
import orbitUpdateMutation from '../graphql/mutations/orbit_update.mutation.graphql';
import { isOrbitReady, isIndexingQueued } from '../utils/orbit_group_state';
import { daysText, freeCreditsText } from '../utils/trial_offer_text';
import { ACCESS_REASON, ACCESS_STATE } from '../access/constants';
import { instanceTrialText } from '../access/instance_text';
import { canTurnOn, startsTrial, turnOnAction } from '../access/turn_on_action';
import { CONFIRM_TURN_OFF } from '../shared/groups/constants';
import GroupsConfirmModal from '../shared/groups/groups_confirm_modal.vue';
import TurnOnConfirmModal from '../shared/groups/turn_on_confirm_modal.vue';
import GroupSettingsAlert from './group_settings_alert.vue';
import { INSTANCE_PAGE_STATES, PAGE_STATE } from './constants';

const INDEXING_POLL_INTERVAL = 15000;
// A queued group can wait hours, so it polls less often, but the page still shows when it is ready.
const QUEUED_POLL_INTERVAL = 60000;

const toggleErrorTitle = (enabled) =>
  enabled
    ? s__('Orbit|Could not turn on GitLab Orbit')
    : s__('Orbit|Could not turn off GitLab Orbit');

export default {
  name: 'OrbitGroupSettingsPage',
  components: {
    GlAlert,
    GlIcon,
    GlSkeletonLoader,
    GlToggle,
    GroupSettingsAlert,
    GroupsConfirmModal,
    TurnOnConfirmModal,
  },
  mixins: [InternalEvents.mixin()],
  inject: ['orbitPlatform'],
  props: {
    groupFullPath: { type: String, required: true },
    duoAvailable: { type: Boolean, required: true },
    orbitPath: { type: String, required: true },
    usageQuotasPath: { type: String, required: true },
    duoSettingsPath: { type: String, required: true },
  },
  apollo: {
    group: {
      query: groupSettingsQuery,
      variables() {
        return { fullPath: this.groupFullPath };
      },
      // The indexing status comes from the Orbit service. When it fails, still show the
      // group, so the Owner can turn Orbit off.
      errorPolicy: ERROR_POLICY_ALL,
      result({ data, error, errors }) {
        if (!data?.group) {
          if (error || errors?.length) {
            createAlert({
              message: s__('Orbit|Could not load the group. Try again.'),
              error: error ?? errors[0],
              captureError: true,
            });
          }
          return;
        }

        this.statusUnavailable = Boolean(errors?.length);
        this.updatePolling();
      },
      // `result` handles errors, because it also gets the partial data. Without this hook,
      // vue-apollo logs every error to the console.
      error() {},
    },
  },
  data() {
    return {
      group: null,
      turnOnModalVisible: false,
      confirmingTurnOff: false,
      startingTrial: false,
      togglingOrbit: false,
      actionError: null,
      statusUnavailable: false,
    };
  },
  computed: {
    saas() {
      return this.orbitPlatform.saas;
    },
    // An older backend returns null for the new fields (@gl_introduced), so the state is not known.
    isOrbitStateKnown() {
      return typeof this.group.orbit?.enabled === 'boolean';
    },
    isOn() {
      return Boolean(this.group.orbit?.enabled);
    },
    access() {
      return this.group.orbit?.access ?? null;
    },
    accessState() {
      return this.access?.state;
    },
    action() {
      return turnOnAction(this.group);
    },
    canTurnOnGroup() {
      return !this.isOn && canTurnOn(this.action);
    },
    blockedAlert() {
      const alert = this.groupBlockedAlert;

      return this.saas ? alert : (INSTANCE_PAGE_STATES[alert] ?? alert);
    },
    groupBlockedAlert() {
      const reason = this.access?.reason;

      if (this.accessState === ACCESS_STATE.NOT_CONFIGURED) return PAGE_STATE.UNLICENSED;
      if (this.canTurnOnGroup) return null;

      switch (this.accessState) {
        case ACCESS_STATE.UNLICENSED:
          return reason === ACCESS_REASON.FREE_PLAN ? PAGE_STATE.FREE_PLAN : PAGE_STATE.UNLICENSED;
        case ACCESS_STATE.TRIAL_STATUS_UNAVAILABLE:
          return PAGE_STATE.CDOT_UNAVAILABLE;
        case ACCESS_STATE.TRIAL_NOT_ELIGIBLE:
          return this.saas ? PAGE_STATE.NOT_ELIGIBLE : null;
        case ACCESS_STATE.TRIAL_ENDED:
          return reason === ACCESS_REASON.CREDITS_EXHAUSTED
            ? PAGE_STATE.CREDITS_USED_UP
            : PAGE_STATE.TRIAL_ENDED;
        case ACCESS_STATE.TRIAL_ELIGIBLE:
          return this.isOn ? null : PAGE_STATE.UNLICENSED;
        default:
          return null;
      }
    },
    isBlocked() {
      return Boolean(this.blockedAlert);
    },
    showActionError() {
      return Boolean(this.actionError) && this.blockedAlert !== PAGE_STATE.CDOT_UNAVAILABLE;
    },
    isEligible() {
      return startsTrial(this.action) && !this.isOn;
    },
    confirmGroups() {
      return [
        {
          fullPath: this.groupFullPath,
          name: this.group.name,
          startsTrial: this.isEligible,
          offer: this.access?.trial?.offer ?? null,
        },
      ];
    },
    instanceTrialEndsOn() {
      return !this.saas && this.isTrialActive ? this.access.trial?.expiresOn : null;
    },
    turnOffConfirmKind() {
      return this.confirmingTurnOff ? CONFIRM_TURN_OFF : null;
    },
    // A blocked group can still be on (the end-of-trial worker runs hourly), so the Owner can still turn it off.
    showToggle() {
      return this.isOrbitStateKnown && (!this.isBlocked || this.isOn);
    },
    trialBannerText() {
      if (this.isTrialActive) return this.activeTrialText;

      const offer = this.access?.trial?.offer;

      if (!offer) {
        return sprintf(
          s__(
            'Orbit|Turn on GitLab Orbit to start a trial for %{groupName}. When the trial ends, contact sales to keep using GitLab Orbit.',
          ),
          { groupName: this.group.name },
        );
      }

      return sprintf(
        s__(
          'Orbit|Turn on GitLab Orbit to start a trial for %{groupName} with %{credits}, valid for %{days}. When the credits run out or the trial ends, contact sales to keep using GitLab Orbit.',
        ),
        {
          groupName: this.group.name,
          credits: freeCreditsText(offer.initialCredits),
          days: daysText(offer.durationDays),
        },
      );
    },
    activeTrialText() {
      if (!this.saas) return instanceTrialText(this.access.trial?.expiresOn);

      const total = this.access?.trial?.credits?.total;

      if (!total) {
        return sprintf(
          s__(
            'Orbit|%{groupName} has a GitLab Orbit trial. When it ends, contact sales to keep using GitLab Orbit.',
          ),
          { groupName: this.group.name },
        );
      }

      return sprintf(
        n__(
          'Orbit|%{groupName} has a GitLab Orbit trial with %{credits} credit. When the credit runs out or the trial ends, contact sales to keep using GitLab Orbit.',
          'Orbit|%{groupName} has a GitLab Orbit trial with %{credits} credits. When the credits run out or the trial ends, contact sales to keep using GitLab Orbit.',
          total,
        ),
        { groupName: this.group.name, credits: formatNumber(total) },
      );
    },
    isTrialActive() {
      return this.accessState === ACCESS_STATE.TRIAL_ACTIVE;
    },
    showTrialBanner() {
      return this.isEligible || this.isTrialActive;
    },
    isReady() {
      return isOrbitReady(this.group);
    },
    showDuoAlert() {
      return this.isOn && !this.duoAvailable;
    },
    statusAlertButtonText() {
      return this.isReady ? s__('Orbit|Go to GitLab Orbit') : '';
    },
    statusAlertTitle() {
      if (this.statusUnavailable) return s__('Orbit|GitLab Orbit status is not available');

      const message = this.isReady
        ? s__('Orbit|GitLab Orbit is ready for %{groupName}')
        : s__('Orbit|GitLab Orbit is indexing %{groupName}');
      return sprintf(message, { groupName: this.group.name });
    },
  },
  beforeDestroy() {
    this.$apollo.queries.group.stopPolling();
  },
  methods: {
    updatePolling() {
      if (!this.isOn || this.isReady) {
        this.$apollo.queries.group.stopPolling();
        return;
      }

      this.$apollo.queries.group.startPolling(
        isIndexingQueued(this.group) ? QUEUED_POLL_INTERVAL : INDEXING_POLL_INTERVAL,
      );
    },
    onToggleChange(enabled) {
      if (enabled) {
        this.turnOnModalVisible = true;
      } else {
        this.confirmingTurnOff = true;
      }
    },
    onConfirmTurnOn() {
      if (this.isEligible) {
        this.startTrial();
      } else {
        this.setOrbitEnabled(true);
      }
    },
    onConfirmTurnOff() {
      this.confirmingTurnOff = false;
      this.setOrbitEnabled(false);
    },
    async startTrial() {
      this.startingTrial = true;
      this.actionError = null;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: orbitStartTrialMutation,
          variables: { groupPath: this.groupFullPath },
        });
        const [message] = data.orbitStartTrial.errors;
        if (message) this.actionError = { title: s__('Orbit|Could not start your trial'), message };
      } catch (error) {
        this.actionError = {
          title: s__('Orbit|Could not start your trial'),
          message: error.message,
        };
        Sentry.captureException(error);
      } finally {
        this.turnOnModalVisible = false;
        this.startingTrial = false;
        await this.$apollo.queries.group.refetch();
      }
    },
    async setOrbitEnabled(enabled) {
      this.togglingOrbit = true;
      this.actionError = null;
      if (!enabled) this.trackEvent('click_orbit_turn_off_indexing');

      try {
        const { data } = await this.$apollo.mutate({
          mutation: orbitUpdateMutation,
          variables: { input: { groupPath: this.groupFullPath, enabled } },
        });
        const [message] = data.orbitUpdate.errors;
        if (message) this.actionError = { title: toggleErrorTitle(enabled), message };
      } catch (error) {
        this.actionError = { title: toggleErrorTitle(enabled), message: error.message };
        Sentry.captureException(error);
      } finally {
        this.turnOnModalVisible = false;
        this.togglingOrbit = false;
        await this.$apollo.queries.group.refetch();
      }
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-max-w-limited gl-flex-col gl-gap-6 gl-py-5"
    data-testid="orbit-group-settings"
  >
    <gl-skeleton-loader v-if="!group" :lines="4" />

    <template v-else>
      <gl-alert
        v-if="showActionError"
        variant="danger"
        :title="actionError.title"
        data-testid="orbit-action-error"
        @dismiss="actionError = null"
      >
        {{ actionError.message }}
      </gl-alert>

      <gl-alert
        v-if="!isOrbitStateKnown"
        variant="info"
        :dismissible="false"
        data-testid="orbit-state-unknown-alert"
      >
        {{ s__('Orbit|GitLab Orbit is not available right now. Try again later.') }}
      </gl-alert>

      <group-settings-alert
        v-else-if="isBlocked"
        :state="blockedAlert"
        :group-name="group.name"
        :usage-quotas-path="usageQuotasPath"
      />

      <gl-alert
        v-else-if="isOn"
        :variant="isReady ? 'success' : 'info'"
        :title="statusAlertTitle"
        :primary-button-text="statusAlertButtonText"
        :primary-button-link="orbitPath"
        :dismissible="false"
        data-testid="orbit-status-alert"
      >
        <template v-if="!isReady && !statusUnavailable">
          {{
            s__('Orbit|You can leave this page. A message appears here when GitLab Orbit is ready.')
          }}
        </template>
      </gl-alert>

      <div class="gl-flex gl-flex-col gl-gap-2">
        <h1 class="gl-heading-1 gl-mb-0">
          {{ s__('Orbit|GitLab Orbit') }}
        </h1>
        <p class="gl-mb-0 gl-text-subtle">
          {{
            s__(
              'Orbit|GitLab Orbit connects work items, merge requests, pipelines, and code, so GitLab Duo and other AI tools can answer questions across projects.',
            )
          }}
        </p>
      </div>

      <div
        v-if="showTrialBanner"
        class="gl-border gl-flex gl-items-center gl-gap-5 gl-rounded-lg gl-border-feedback-info gl-bg-feedback-info gl-p-5"
        data-testid="orbit-trial-banner"
      >
        <div
          class="gl-hidden gl-h-9 gl-w-9 gl-shrink-0 gl-items-center gl-justify-center gl-rounded-full gl-bg-default gl-text-feedback-info @sm:gl-flex"
        >
          <gl-icon name="orbit" :size="24" />
        </div>
        <div>
          <h2 class="gl-heading-4 gl-mb-1">{{ s__('Orbit|GitLab Orbit trial') }}</h2>
          <p class="gl-mb-0 gl-text-subtle">{{ trialBannerText }}</p>
        </div>
      </div>

      <template v-if="showToggle">
        <gl-toggle
          :value="isOn"
          :label="s__('Orbit|Turn on GitLab Orbit')"
          :help="
            s__(
              'Orbit|Required to use GitLab Orbit. Indexes this group, its subgroups, and projects. Can take up to a few hours.',
            )
          "
          :is-loading="togglingOrbit || startingTrial"
          data-testid="orbit-toggle"
          @change="onToggleChange"
        />

        <gl-alert
          v-if="showDuoAlert"
          variant="info"
          :title="s__('Orbit|GitLab Duo is not available for this group')"
          :primary-button-text="s__('Orbit|Go to GitLab Duo settings')"
          :primary-button-link="duoSettingsPath"
          :dismissible="false"
          data-testid="orbit-duo-alert"
        >
          {{ s__('Orbit|Turn on GitLab Duo to let GitLab Duo Chat and agents use GitLab Orbit.') }}
        </gl-alert>
      </template>

      <turn-on-confirm-modal
        :visible="turnOnModalVisible"
        :groups="confirmGroups"
        :loading="startingTrial || togglingOrbit"
        :instance-trial-ends-on="instanceTrialEndsOn"
        @confirm="onConfirmTurnOn"
        @hide="turnOnModalVisible = false"
      />

      <groups-confirm-modal
        :kind="turnOffConfirmKind"
        :groups="confirmGroups"
        :auto-index-enabled="false"
        @confirm="onConfirmTurnOff"
        @cancel="confirmingTurnOff = false"
      />
    </template>
  </div>
</template>
