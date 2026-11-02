<script>
import { GlFormGroup, GlFormSelect } from '@gitlab/ui';
import { s__ } from '~/locale';
import DuoReadinessRow from '~/ai/settings/readiness/components/duo_readiness_row.vue';
import DuoReadinessSection from '~/ai/settings/readiness/components/duo_readiness_section.vue';
import {
  ACCESS_LEVEL_DEVELOPER_INTEGER,
  ACCESS_LEVEL_MAINTAINER_INTEGER,
  ACCESS_LEVEL_ADMIN_INTEGER,
  ACCESS_LEVEL_OWNER_INTEGER,
  ACCESS_LEVEL_ADMIN,
  ACCESS_LEVEL_LABELS,
  ACCESS_LEVEL_GUEST_INTEGER,
  ACCESS_LEVEL_REPORTER_INTEGER,
  ACCESS_LEVEL_PLANNER_INTEGER,
} from '~/access_level/constants';

import { ACCESS_LEVEL_EVERYONE_INTEGER } from '../constants';

const ALL_ACCESS_LEVELS_LABELS = {
  [ACCESS_LEVEL_EVERYONE_INTEGER]: s__('AiPowered|Everyone'),
  ...ACCESS_LEVEL_LABELS,
  [ACCESS_LEVEL_ADMIN_INTEGER]: ACCESS_LEVEL_ADMIN,
};

export default {
  name: 'AiRolePermissions',
  components: {
    GlFormGroup,
    GlFormSelect,
    DuoReadinessRow,
    DuoReadinessSection,
  },
  inject: ['isSaaS'],
  props: {
    initialMinimumAccessLevelExecuteAsync: {
      type: Number,
      required: true,
    },
    initialMinimumAccessLevelExecuteSync: {
      type: Number,
      required: true,
    },
    // Renders the redesigned "User permissions" section instead of the form
    // groups: same selects, same events, row copy from the group settings design.
    sectioned: {
      type: Boolean,
      required: false,
      default: false,
    },
    headingTag: {
      type: String,
      required: false,
      default: 'h2',
      validator: (value) => ['h2', 'h3', 'h4'].includes(value),
    },
  },
  emits: ['minimum-access-level-execute-async-change', 'minimum-access-level-execute-sync-change'],
  data() {
    return {
      minimumAccessLevelExecuteAsync: this.initialMinimumAccessLevelExecuteAsync,
      minimumAccessLevelExecuteSync: this.initialMinimumAccessLevelExecuteSync,
    };
  },
  computed: {
    minimumAccessLevelExecuteAsyncOptions() {
      const roles = [
        ACCESS_LEVEL_DEVELOPER_INTEGER,
        ACCESS_LEVEL_MAINTAINER_INTEGER,
        ACCESS_LEVEL_OWNER_INTEGER,
      ];
      if (!this.isSaaS) {
        roles.push(ACCESS_LEVEL_ADMIN_INTEGER);
      }
      return this.generateSelectOptions(roles);
    },
    minimumAccessLevelExecuteSyncOptions() {
      const roles = [
        ACCESS_LEVEL_EVERYONE_INTEGER,
        ACCESS_LEVEL_GUEST_INTEGER,
        ACCESS_LEVEL_PLANNER_INTEGER,
        ACCESS_LEVEL_REPORTER_INTEGER,
        ACCESS_LEVEL_DEVELOPER_INTEGER,
        ACCESS_LEVEL_MAINTAINER_INTEGER,
        ACCESS_LEVEL_OWNER_INTEGER,
      ];

      if (!this.isSaaS) {
        roles.push(ACCESS_LEVEL_ADMIN_INTEGER);
      }

      return this.generateSelectOptions(roles);
    },
  },
  methods: {
    generateSelectOptions(roles) {
      return roles.map((role) => ({
        text: ALL_ACCESS_LEVELS_LABELS[role],
        value: role,
      }));
    },
    changeMinimumAccessLevelExecuteAsync(role) {
      this.minimumAccessLevelExecuteAsync = role;
      this.$emit('minimum-access-level-execute-async-change', role);
    },
    changeMinimumAccessLevelExecuteSync(role) {
      this.minimumAccessLevelExecuteSync = role;
      this.$emit('minimum-access-level-execute-sync-change', role);
    },
  },
  i18n: {
    // Row titles double as the select labels, so they stay here; the rest is inline.
    asyncRowTitle: s__('DuoAgentPlatform|Minimum role for features that use CI/CD pipelines'),
    syncRowTitle: s__('DuoAgentPlatform|Minimum role for all other Agent Platform features'),
    minimumAccessLevelExecuteAsyncLabel: s__('AiPowered|Features with CI/CD pipelines'),
    minimumAccessLevelExecuteSyncLabel: s__('AiPowered|Features without CI/CD pipelines'),
    sectionDescription: s__(
      'AiPowered|Control who can access AI-native features executed with or without CI/CD pipelines.',
    ),
    sectionTitle: s__('AiPowered|Access to GitLab Duo Agent Platform'),
  },
};
</script>
<template>
  <duo-readiness-section
    v-if="sectioned"
    :title="s__('DuoAgentPlatform|User permissions')"
    :subtitle="s__('DuoAgentPlatform|Who can use GitLab Duo in this group.')"
    :heading-tag="headingTag"
    data-testid="user-permissions-section"
  >
    <duo-readiness-row
      :title="$options.i18n.asyncRowTitle"
      :description="s__('DuoAgentPlatform|Includes flows, which run as CI/CD jobs.')"
      data-testid="minimum-access-level-execute-async-row"
    >
      <gl-form-select
        id="minimum-access-level-execute-async-selector"
        v-model="minimumAccessLevelExecuteAsync"
        :options="minimumAccessLevelExecuteAsyncOptions"
        :aria-label="$options.i18n.asyncRowTitle"
        data-testid="minimum-access-level-execute-async-selector"
        class="gl-max-w-26"
        @change="changeMinimumAccessLevelExecuteAsync"
      />
    </duo-readiness-row>

    <duo-readiness-row
      :title="$options.i18n.syncRowTitle"
      :description="s__('DuoAgentPlatform|Agents, chat, and code suggestions.')"
      data-testid="minimum-access-level-execute-sync-row"
    >
      <gl-form-select
        id="minimum-access-level-execute-sync-selector"
        v-model="minimumAccessLevelExecuteSync"
        :options="minimumAccessLevelExecuteSyncOptions"
        :aria-label="$options.i18n.syncRowTitle"
        data-testid="minimum-access-level-execute-sync-selector"
        class="gl-max-w-26"
        @change="changeMinimumAccessLevelExecuteSync"
      />
    </duo-readiness-row>
  </duo-readiness-section>

  <div v-else>
    <gl-form-group :label="$options.i18n.sectionTitle" class="gl-mb-0">
      <template #label-description>
        <p class="gl-mb-3 gl-text-subtle">{{ $options.i18n.sectionDescription }}</p>
      </template>

      <div>
        <gl-form-group
          :label="$options.i18n.minimumAccessLevelExecuteAsyncLabel"
          label-for="minimum-access-level-execute-async-selector"
        >
          <gl-form-select
            id="minimum-access-level-execute-async-selector"
            v-model="minimumAccessLevelExecuteAsync"
            :options="minimumAccessLevelExecuteAsyncOptions"
            data-testid="minimum-access-level-execute-async-selector"
            class="gl-max-w-26"
            @change="changeMinimumAccessLevelExecuteAsync"
          />
        </gl-form-group>

        <gl-form-group
          :label="$options.i18n.minimumAccessLevelExecuteSyncLabel"
          label-for="minimum-access-level-execute-sync-selector"
        >
          <gl-form-select
            id="minimum-access-level-execute-sync-selector"
            v-model="minimumAccessLevelExecuteSync"
            :options="minimumAccessLevelExecuteSyncOptions"
            data-testid="minimum-access-level-execute-sync-selector"
            class="gl-max-w-26"
            @change="changeMinimumAccessLevelExecuteSync"
          />
        </gl-form-group>
      </div>
    </gl-form-group>
  </div>
</template>
