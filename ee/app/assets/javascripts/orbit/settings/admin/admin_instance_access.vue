<script>
import { defineComponent } from 'vue';
import { GlAlert } from '@gitlab/ui';
import { ACCESS_STATE } from '../../access/constants';
import orbitInstanceStartTrialMutation from '../../graphql/mutations/orbit_instance_start_trial.mutation.graphql';
import { reportRequestError } from '../../shared/groups/utils';
import adminInstanceAccessQuery from './graphql/admin_instance_access.query.graphql';
import AdminInstanceAccessCard from './admin_instance_access_card.vue';

// The health card already explains these states, and a CustomersDot outage is not a missing purchase.
const CARDLESS_ACCESS_STATES = [ACCESS_STATE.NOT_CONFIGURED, ACCESS_STATE.TRIAL_STATUS_UNAVAILABLE];

export default defineComponent({
  name: 'AdminInstanceAccess',
  components: { AdminInstanceAccessCard, GlAlert },
  apollo: {
    instanceAccess: {
      query: adminInstanceAccessQuery,
      update: (data) => data.orbit?.access ?? null,
      error(error) {
        reportRequestError(error);
      },
    },
  },
  data() {
    return {
      instanceAccess: null,
      startingTrial: false,
      trialConfirmVisible: false,
      trialError: null,
    };
  },
  computed: {
    showsAccessCard() {
      return (
        Boolean(this.instanceAccess) && !CARDLESS_ACCESS_STATES.includes(this.instanceAccess.state)
      );
    },
  },
  methods: {
    async startInstanceTrial() {
      this.startingTrial = true;
      this.trialError = null;

      try {
        const { data } = await this.$apollo.mutate({ mutation: orbitInstanceStartTrialMutation });
        const [message] = data.orbitInstanceStartTrial.errors;
        if (message) this.trialError = message;
      } catch (error) {
        this.trialError = reportRequestError(error).message;
      } finally {
        await this.$apollo.queries.instanceAccess.refetch().catch(() => {});
        this.startingTrial = false;
        this.trialConfirmVisible = false;
      }
    },
  },
});
</script>

<template>
  <div v-if="trialError || showsAccessCard" class="gl-flex gl-flex-col gl-gap-6">
    <gl-alert
      v-if="trialError"
      variant="danger"
      :title="s__('Orbit|Could not start your trial')"
      data-testid="orbit-instance-trial-error"
      @dismiss="trialError = null"
    >
      {{ trialError }}
    </gl-alert>

    <admin-instance-access-card
      v-if="showsAccessCard"
      :access="instanceAccess"
      :starting="startingTrial"
      :confirm-visible="trialConfirmVisible"
      @show-confirm="trialConfirmVisible = true"
      @hide-confirm="trialConfirmVisible = false"
      @start-trial="startInstanceTrial"
    />
  </div>
</template>
