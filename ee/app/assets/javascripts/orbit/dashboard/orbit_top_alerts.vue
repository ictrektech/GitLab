<script>
import { defineComponent } from 'vue';
import { GlAlert } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { isInitialIndexing } from 'ee/orbit/utils/orbit_group_state';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';

export default defineComponent({
  name: 'OrbitTopAlerts',
  components: { ContactSalesButton, GlAlert },
  inject: ['defaultGroupMissing', 'preferencesPath'],
  props: {
    enabledGroups: {
      type: Array,
      required: true,
    },
    endedTrialNamespaceId: {
      type: Number,
      required: false,
      default: null,
    },
  },
  computed: {
    indexingGroups() {
      return this.enabledGroups.filter(isInitialIndexing);
    },
    hasIndexingGroups() {
      return this.indexingGroups.length > 0;
    },
    hasAlerts() {
      return (
        Boolean(this.endedTrialNamespaceId) || this.defaultGroupMissing || this.hasIndexingGroups
      );
    },
    indexingTitle() {
      if (this.enabledGroups.length === 1) {
        return sprintf(s__('Orbit|Indexing %{name}'), { name: this.indexingGroups[0].name });
      }

      return sprintf(s__('Orbit|Indexing %{indexing} of %{total} groups'), {
        indexing: this.indexingGroups.length,
        total: this.enabledGroups.length,
      });
    },
  },
});
</script>

<template>
  <div v-if="hasAlerts" class="gl-mb-5 gl-flex gl-flex-col gl-gap-4">
    <gl-alert
      v-if="endedTrialNamespaceId"
      variant="warning"
      :title="s__('Orbit|Trials have ended for some groups')"
      :dismissible="false"
      data-testid="orbit-trial-ended-alert"
    >
      {{
        s__(
          'Orbit|GitLab Orbit queries are paused for groups whose trial ended. Contact sales to keep using GitLab Orbit.',
        )
      }}
      <template #actions>
        <contact-sales-button
          glm-content="orbit-trial-ended"
          :namespace-id="endedTrialNamespaceId"
        />
      </template>
    </gl-alert>

    <gl-alert
      v-if="defaultGroupMissing"
      variant="warning"
      :title="s__('Orbit|Select a default group')"
      :dismissible="false"
      :primary-button-text="s__('Orbit|Go to preferences')"
      :primary-button-link="preferencesPath"
      data-testid="orbit-no-default-alert"
    >
      {{
        s__(
          'Orbit|To run GitLab Orbit queries, select a default group in your preferences. You belong to more than one group eligible for GitLab Orbit billing. Indexing continues.',
        )
      }}
    </gl-alert>

    <gl-alert
      v-if="hasIndexingGroups"
      variant="info"
      :title="indexingTitle"
      :dismissible="false"
      data-testid="orbit-indexing-alert"
    >
      {{
        s__(
          'Orbit|You can use GitLab Orbit when indexing is done, which may take several minutes to hours. You can leave this page and check back later.',
        )
      }}
    </gl-alert>
  </div>
</template>
