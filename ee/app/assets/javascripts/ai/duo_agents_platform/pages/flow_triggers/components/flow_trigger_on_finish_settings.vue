<script>
import { GlAlert, GlCollapsibleListbox, GlFormCheckbox, GlFormGroup } from '@gitlab/ui';
import { isEqual, uniqueId } from 'lodash-es';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { s__ } from '~/locale';
import namespaceWorkItemTypesQuery from '~/work_items/graphql/namespace_work_item_types.query.graphql';
import { workItemTypesStatusNameOptions } from 'ee/ai/duo_agents_platform/utils/work_item_statuses';

export default {
  name: 'FlowTriggerOnFinishSettings',
  components: {
    GlAlert,
    GlCollapsibleListbox,
    GlFormCheckbox,
    GlFormGroup,
  },
  inject: ['projectPath'],
  props: {
    statusOnFinish: {
      type: String,
      required: false,
      default: null,
    },
    readyMergeRequestsOnFinish: {
      type: Boolean,
      required: true,
    },
    disabled: {
      type: Boolean,
      required: true,
    },
    triggerStatusNames: {
      type: Array,
      required: true,
    },
    triggerWorkItemTypeIds: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['update:status-on-finish', 'update:ready-merge-requests-on-finish'],
  apollo: {
    workItemTypes: {
      query: namespaceWorkItemTypesQuery,
      variables() {
        return { fullPath: this.projectPath };
      },
      update(data) {
        this.statusesFailedToLoad = false;
        return data.namespace?.workItemTypes?.nodes ?? [];
      },
      skip() {
        return this.disabled;
      },
      // Shown in the listbox only. While the work item condition is open for editing, it runs
      // the same query and raises the page alert, so a second alert would repeat it.
      error(error) {
        this.statusesFailedToLoad = true;
        Sentry.captureException(error);
      },
    },
  },
  data() {
    return {
      workItemTypes: [],
      statusesFailedToLoad: false,
      headingId: uniqueId('on-finish-heading-'),
      descriptionId: uniqueId('on-finish-description-'),
      statusToggleId: uniqueId('on-finish-status-toggle-'),
    };
  },
  computed: {
    statusOptions() {
      return workItemTypesStatusNameOptions(this.workItemTypes, this.triggerWorkItemTypeIds);
    },
    // Undefined falls back to the listbox's own "No results found" text.
    noResultsText() {
      return this.statusesFailedToLoad
        ? s__('DuoAgentsPlatform|Could not load statuses. Refresh the page to try again.')
        : undefined;
    },
    restartsTrigger() {
      return Boolean(this.statusOnFinish) && this.triggerStatusNames.includes(this.statusOnFinish);
    },
  },
  watch: {
    // Runs when the user changes the types, not on load, so a stored status is never dropped unseen.
    triggerWorkItemTypeIds(typeIds, previousTypeIds) {
      if (
        !isEqual(typeIds, previousTypeIds) &&
        this.statusOnFinish &&
        // Before the types load, or after the query fails, no status would be in the list.
        this.workItemTypes.length &&
        !this.statusOptions.some(({ value }) => value === this.statusOnFinish)
      ) {
        this.$emit('update:status-on-finish', null);
      }
    },
  },
};
</script>

<template>
  <div role="group" :aria-labelledby="headingId" :aria-describedby="descriptionId">
    <h2 :id="headingId" class="gl-heading-3 gl-mb-1 gl-mt-3">
      {{ s__('DuoAgentsPlatform|When the session finishes') }}
    </h2>
    <p :id="descriptionId" class="gl-text-subtle" data-testid="on-finish-description">
      <template v-if="disabled">
        {{
          s__(
            'DuoAgentsPlatform|Available only when Status changed is the only selected work item action and at least one status is selected.',
          )
        }}
      </template>
      <template v-else>
        {{
          s__(
            'DuoAgentsPlatform|Update the work item and its merge requests after a session that this trigger started finishes.',
          )
        }}
      </template>
    </p>
    <div class="gl-flex gl-flex-col gl-gap-5">
      <gl-form-group
        :label="s__('DuoAgentsPlatform|Set work item status')"
        :label-for="statusToggleId"
        class="!gl-mb-0"
      >
        <gl-collapsible-listbox
          :toggle-id="statusToggleId"
          :items="statusOptions"
          :selected="statusOnFinish"
          :toggle-text="statusOnFinish || s__('DuoAgentsPlatform|Do not change status')"
          :header-text="s__('DuoAgentsPlatform|Select a status')"
          :reset-button-label="__('Clear')"
          :loading="$apollo.queries.workItemTypes.loading"
          :no-results-text="noResultsText"
          :disabled="disabled"
          block
          data-testid="on-finish-status-listbox"
          @select="$emit('update:status-on-finish', $event)"
          @reset="$emit('update:status-on-finish', null)"
        />
        <gl-alert
          v-if="restartsTrigger"
          variant="warning"
          :dismissible="false"
          class="gl-mt-3"
          data-testid="on-finish-restart-warning"
        >
          {{
            s__(
              'DuoAgentsPlatform|This trigger runs on this status, so setting it can start another session.',
            )
          }}
        </gl-alert>
      </gl-form-group>
      <gl-form-checkbox
        :checked="readyMergeRequestsOnFinish"
        :disabled="disabled"
        data-testid="on-finish-ready-checkbox"
        @change="$emit('update:ready-merge-requests-on-finish', $event)"
      >
        {{ s__('DuoAgentsPlatform|Mark merge requests as ready') }}
        <template #help>
          {{
            s__(
              'DuoAgentsPlatform|Marks the draft merge requests that the session created as ready. If one stays a draft, the status is not set.',
            )
          }}
        </template>
      </gl-form-checkbox>
    </div>
  </div>
</template>
