<script>
import { GlAlert } from '@gitlab/ui';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import toast from '~/vue_shared/plugins/global_toast';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import getCreditCapsQuery from '../graphql/get_credit_caps.query.graphql';
import upsertFlatUserCapMutation from '../graphql/upsert_flat_user_cap.mutation.graphql';
import FlatUserCapControl from './flat_user_cap_control.vue';
import UserOverridesList from './user_overrides_list.vue';

export default {
  name: 'CreditCapsDashboardApp',
  components: {
    GlAlert,
    DetailLayout,
    FlatUserCapControl,
    UserOverridesList,
  },
  inject: {
    namespacePath: {
      default: null,
    },
  },
  data() {
    return {
      creditCaps: null,
      hasError: false,
      isSavingFlatCap: false,
      hasFlatCapSaveError: false,
    };
  },
  apollo: {
    creditCaps: {
      query: getCreditCapsQuery,
      variables() {
        return { namespacePath: this.namespacePath };
      },
      update({ subscriptionUsage }) {
        return subscriptionUsage?.budgetCaps ?? null;
      },
      result({ data, error }) {
        // In GraphQL the `budgetCaps` field can be null. If it is null, we show an error.
        // There's an issue to further investigate this behaviour.
        // Issue: https://gitlab.com/gitlab-org/gitlab/-/work_items/618074
        if (!data?.subscriptionUsage?.budgetCaps && !error) {
          // eslint-disable-next-line @gitlab/require-i18n-strings
          const nullDataError = new Error('Credit caps data unavailable');
          this.hasError = true;
          logError(nullDataError);
          captureException(nullDataError);
        }
      },
      error(error) {
        this.hasError = true;
        logError(error);
        captureException(error);
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.creditCaps.loading;
    },
    flatUserCap() {
      return this.creditCaps?.flatUserCap;
    },
    flatUserCapEnabled() {
      return this.creditCaps?.flatUserCapEnabled;
    },
    showUserOverridesList() {
      return this.creditCaps?.flatUserCapEnabled !== null;
    },
  },
  methods: {
    async onSaveFlatCap({ flatUserCap, flatUserCapEnabled }) {
      this.isSavingFlatCap = true;
      this.hasFlatCapSaveError = false;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: upsertFlatUserCapMutation,
          variables: {
            input: { namespacePath: this.namespacePath, flatUserCap, flatUserCapEnabled },
          },
          update: (store, { data: { upsertFlatUserCap } }) => {
            if (upsertFlatUserCap.errors.length) return;

            store.writeQuery({
              query: getCreditCapsQuery,
              variables: { namespacePath: this.namespacePath },
              data: {
                subscriptionUsage: {
                  budgetCaps: {
                    flatUserCap: upsertFlatUserCap.flatUserCap,
                    flatUserCapEnabled: upsertFlatUserCap.flatUserCapEnabled,
                  },
                },
              },
            });
          },
        });

        if (data.upsertFlatUserCap.errors.length) {
          const errorObjects = data.upsertFlatUserCap.errors.map((msg) => new Error(msg));

          if (errorObjects.length === 1) throw errorObjects[0];

          // eslint-disable-next-line @gitlab/require-i18n-strings
          throw new AggregateError(errorObjects, 'Flat user cap save failed');
        }

        toast(s__('UsageBilling|Flat cap saved.'));
      } catch (error) {
        this.hasFlatCapSaveError = true;
        logError(error);
        captureException(error);
      } finally {
        this.isSavingFlatCap = false;
      }
    },
  },
};
</script>

<template>
  <detail-layout :heading="s__('UsageBilling|Credit caps')" :loading="isLoading">
    <template v-if="hasError || hasFlatCapSaveError" #alerts>
      <gl-alert v-if="hasError" variant="danger" :dismissible="false" data-testid="error-alert">
        {{ s__('UsageBilling|An error occurred while fetching data.') }}
      </gl-alert>

      <gl-alert
        v-else
        variant="danger"
        :dismissible="false"
        data-testid="flat-cap-save-error-alert"
      >
        {{ s__('UsageBilling|An error occurred while saving flat cap.') }}
      </gl-alert>
    </template>

    <div v-if="!hasError" class="gl-flex gl-flex-col gl-gap-5">
      <flat-user-cap-control
        :flat-user-cap="flatUserCap"
        :flat-user-cap-enabled="flatUserCapEnabled"
        :is-saving="isSavingFlatCap"
        @save="onSaveFlatCap"
      />

      <gl-alert
        v-if="!showUserOverridesList"
        variant="info"
        :dismissible="false"
        :title="s__('UsageBilling|Per-user cap overrides require flat cap value')"
        data-testid="overrides-unavailable-alert"
      >
        {{
          s__(
            "UsageBilling|To add per-user overrides you need to save Flat cap value first. You can leave Enforce cap turned off until you're ready.",
          )
        }}
      </gl-alert>
      <user-overrides-list v-else />
    </div>
  </detail-layout>
</template>
