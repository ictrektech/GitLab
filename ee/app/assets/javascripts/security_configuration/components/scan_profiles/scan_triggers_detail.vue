<script>
import { GlIcon } from '@gitlab/ui';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import TriggerInfoPopover from './trigger_info_popover.vue';
import TriggerVariableTable from './trigger_variable_table.vue';
import { isPushProtectionTrigger } from './utils';

export default {
  name: 'ScanTriggersDetail',
  components: {
    CrudComponent,
    GlIcon,
    TriggerInfoPopover,
    TriggerVariableTable,
  },
  props: {
    profileHelpLink: {
      type: String,
      required: false,
      default: () => '',
    },
    triggers: {
      type: Array,
      required: true,
    },
    variableDefinitions: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      collapsed: true,
    };
  },
  methods: {
    isPushProtectionTrigger,
    variableRows(trigger) {
      return trigger.variableRows ?? [];
    },
    learnMoreLink(trigger) {
      return trigger.helpLink || this.profileHelpLink;
    },
  },
};
</script>

<template>
  <div>
    <crud-component
      v-for="trigger in triggers"
      :key="trigger.anchor"
      :is-collapsible="true"
      :collapsed="collapsed"
      :anchor-id="trigger.anchor"
      plain-toggle
      title-tag="h5"
      body-class="!gl-p-3"
      class="hover:!gl-bg-neutral-100 dark:hover:!gl-bg-neutral-800"
    >
      <template #title>
        <gl-icon v-if="trigger.icon" :name="trigger.icon" />
        {{ trigger.title }}
        <trigger-info-popover
          :anchor="trigger.anchor"
          :title="trigger.title"
          :description="trigger.infoDescription"
          :help-link="learnMoreLink(trigger)"
        />
      </template>

      <div
        v-if="trigger.targetBranch || trigger.results"
        class="gl-mb-4 gl-flex gl-flex-col gl-gap-1"
      >
        <div v-if="trigger.targetBranch" class="gl-grid gl-grid-cols-5 gl-gap-3">
          <span class="gl-text-subtle">{{ s__('ScanProfiles|Target branch') }}</span>
          <span class="gl-col-span-4 gl-font-semibold">{{ trigger.targetBranch }}</span>
        </div>
        <div v-if="trigger.results" class="gl-grid gl-grid-cols-5 gl-gap-3">
          <span class="gl-text-subtle">{{ s__('ScanProfiles|Results') }}</span>
          <span class="gl-col-span-4 gl-font-semibold">{{ trigger.results }}</span>
        </div>
      </div>

      <template v-if="variableRows(trigger).length || isPushProtectionTrigger(trigger)">
        <h6 class="gl-heading-5 gl-mb-2">
          {{ s__('ScanProfiles|Advanced configuration for this trigger') }}
        </h6>
        <trigger-variable-table
          v-if="variableRows(trigger).length"
          :trigger-title="trigger.title"
          :rows="variableRows(trigger)"
          :variable-definitions="variableDefinitions"
        />
        <p v-else class="gl-m-0 gl-text-subtle">
          {{ s__("ScanProfiles|Push protection can't carry analyzer configuration.") }}
        </p>
      </template>
    </crud-component>
  </div>
</template>
