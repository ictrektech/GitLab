<script>
import {
  GlBadge,
  GlButton,
  GlCollapsibleListbox,
  GlIcon,
  GlLoadingIcon,
  GlTooltipDirective,
} from '@gitlab/ui';
import { gql } from '@apollo/client/core';
import { createAlert } from '~/alert';
import { s__, sprintf } from '~/locale';
import updateAiToolRuleMutation from '../../graphql/mutations/update_ai_tool_rule.mutation.graphql';

const ALLOW_OPTION = {
  value: 'ALLOW',
  icon: 'check',
  text: s__('AiGovernance|Always allow'),
  iconClass: 'gl-text-success',
};
const ASK_OPTION = {
  value: 'ASK',
  icon: 'notifications',
  text: s__('AiGovernance|Always ask'),
  iconClass: 'gl-text-warning',
};
const DENY_OPTION = {
  value: 'DENY',
  icon: 'close',
  text: s__('AiGovernance|Always deny'),
  iconClass: 'gl-text-danger',
};

// Runner (background) flows have no human present to respond, so "Always ask" is not
// offered for that access type. This is enforced at the model level on the backend.
const ACCESS_OPTIONS_BY_TYPE = {
  webAccess: [ALLOW_OPTION, ASK_OPTION, DENY_OPTION],
  localAccess: [ALLOW_OPTION, ASK_OPTION, DENY_OPTION],
  backgroundAccess: [ALLOW_OPTION, DENY_OPTION],
};

const ACCESS_TYPES = Object.keys(ACCESS_OPTIONS_BY_TYPE);

const ACCESS_OPTIONS_BY_VALUE = [ALLOW_OPTION, ASK_OPTION, DENY_OPTION].reduce((acc, option) => {
  acc[option.value] = option;
  return acc;
}, {});

const ACCESS_RANK = { ALLOW: 0, ASK: 1, DENY: 2 };

// Listbox value for "no rule at this scope". Picking it clears the cell.
const UNSET_VALUE = 'UNSET';

const FLOOR_DISABLED_TOOLTIP = s__(
  'AiGovernance|Set at the group level. Projects can only apply stricter rules.',
);

const UPDATED_TOOL_RULE_FRAGMENT = gql`
  fragment UpdatedAiToolRule on AiToolRule {
    webAccess
    localAccess
    backgroundAccess
    configuredAccess {
      webAccess
      localAccess
      backgroundAccess
    }
    defaultAccess {
      webAccess
      localAccess
      backgroundAccess
    }
  }
`;

export default {
  name: 'AiToolRuleAccessControl',
  components: {
    GlBadge,
    GlButton,
    GlCollapsibleListbox,
    GlIcon,
    GlLoadingIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  props: {
    toolRule: {
      type: Object,
      required: true,
    },
    accessType: {
      type: String,
      required: true,
      validator: (value) => ACCESS_TYPES.includes(value),
    },
    groupFullPath: {
      type: String,
      required: true,
    },
    projectFullPath: {
      type: String,
      required: false,
      default: '',
    },
    floorValue: {
      type: String,
      required: false,
      default: null,
    },
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
    disabledTooltip: {
      type: String,
      required: false,
      default: '',
    },
  },
  data() {
    return {
      pendingValue: null,
    };
  },
  computed: {
    value() {
      return this.toolRule[this.accessType];
    },
    isLoading() {
      return this.pendingValue !== null;
    },
    // An older backend returns no configuredAccess, so the cell behaves as before.
    notSetSupported() {
      return Boolean(this.toolRule.configuredAccess);
    },
    isConfigured() {
      return Boolean(this.toolRule.configuredAccess?.[this.accessType]);
    },
    showsUnset() {
      return this.notSetSupported && !this.isConfigured;
    },
    // An unset project cell follows the group's value, so it resolves to the floor.
    unsetResolvedValue() {
      const defaultValue = this.toolRule.defaultAccess?.[this.accessType] ?? null;

      return this.projectFullPath ? (this.floorValue ?? defaultValue) : defaultValue;
    },
    unsetOption() {
      const resolved = ACCESS_OPTIONS_BY_VALUE[this.unsetResolvedValue] ?? this.selectedOption;

      return {
        value: UNSET_VALUE,
        text: this.projectFullPath ? this.$options.i18n.inherit : this.$options.i18n.default,
        hint: resolved ? sprintf(this.$options.i18n.usesValue, { value: resolved.text }) : '',
      };
    },
    listboxItems() {
      if (!this.notSetSupported) return this.accessOptions;

      return [
        { text: this.$options.i18n.unsetGroup, textSrOnly: true, options: [this.unsetOption] },
        { text: this.$options.i18n.rulesGroup, textSrOnly: true, options: this.accessOptions },
      ];
    },
    listboxSelected() {
      return this.showsUnset ? UNSET_VALUE : this.value;
    },
    toggleLabel() {
      if (!this.selectedOption) return '';
      if (!this.isConfigured) return this.selectedOption.text;

      return sprintf(this.$options.i18n.overrideLabel, { value: this.selectedOption.text });
    },
    selectedOption() {
      return ACCESS_OPTIONS_BY_VALUE[this.value];
    },
    accessOptions() {
      const options = ACCESS_OPTIONS_BY_TYPE[this.accessType];

      if (!this.floorValue) {
        return options;
      }

      const floorRank = ACCESS_RANK[this.floorValue] ?? 0;

      return options.map((option) => ({
        ...option,
        disabled: ACCESS_RANK[option.value] < floorRank,
      }));
    },
    availableOptions() {
      return this.accessOptions.filter((option) => !option.disabled);
    },
    isStatic() {
      return this.disabled || (this.availableOptions.length <= 1 && !this.isConfigured);
    },
    staticTooltip() {
      if (!this.isStatic) return '';
      if (this.disabled) return this.disabledTooltip;
      if (this.floorValue) return FLOOR_DISABLED_TOOLTIP;
      return '';
    },
  },
  FLOOR_DISABLED_TOOLTIP,
  UNSET_ACCESS_TYPE_BY_ACCESS_TYPE: {
    webAccess: 'WEB_ACCESS',
    localAccess: 'LOCAL_ACCESS',
    backgroundAccess: 'BACKGROUND_ACCESS',
  },
  i18n: {
    updateError: s__('AiGovernance|Failed to update tool rule. Please try again.'),
    default: s__('AiGovernance|Default'),
    inherit: s__('AiGovernance|Inherit'),
    usesValue: s__('AiGovernance|Uses %{value}'),
    override: s__('AiGovernance|Override'),
    overrideLabel: s__('AiGovernance|%{value}, set as an override'),
    unsetGroup: s__('AiGovernance|No rule'),
    rulesGroup: s__('AiGovernance|Rules'),
  },
  methods: {
    handleSelect(newValue) {
      if (this.isLoading) return;

      if (newValue === UNSET_VALUE) {
        if (this.isConfigured) this.resetRule();
        return;
      }

      if (!this.showsUnset && newValue === this.value) return;

      this.updateRule(newValue, { [this.accessType]: newValue });
    },
    resetRule() {
      if (this.isLoading) return;

      this.updateRule(this.value, {
        unsetAccessTypes: [this.$options.UNSET_ACCESS_TYPE_BY_ACCESS_TYPE[this.accessType]],
      });
    },
    async updateRule(pendingValue, changes) {
      this.pendingValue = pendingValue;

      const input = {
        fullPath: this.groupFullPath,
        toolId: this.toolRule.id,
        ...changes,
      };

      if (this.projectFullPath) {
        input.projectPath = this.projectFullPath;
      }

      try {
        const { data } = await this.$apollo.mutate({
          mutation: updateAiToolRuleMutation,
          variables: { input },
        });

        if (data?.updateAiToolRule?.errors?.length > 0) {
          createAlert({ message: this.$options.i18n.updateError, captureError: true });
          return;
        }

        const { toolRule } = data.updateAiToolRule;

        this.$apollo.getClient().writeFragment({
          id: `AiToolRule:${this.toolRule.id}`,
          fragment: UPDATED_TOOL_RULE_FRAGMENT,
          data: {
            __typename: 'AiToolRule',
            webAccess: toolRule.webAccess,
            localAccess: toolRule.localAccess,
            backgroundAccess: toolRule.backgroundAccess,
            configuredAccess: toolRule.configuredAccess,
            defaultAccess: toolRule.defaultAccess,
          },
        });
      } catch {
        createAlert({ message: this.$options.i18n.updateError, captureError: true });
      } finally {
        this.pendingValue = null;
      }
    },
  },
};
</script>

<template>
  <span
    v-gl-tooltip="staticTooltip"
    class="gl-flex gl-w-full"
    :class="{ '!gl-pointer-events-auto': staticTooltip }"
  >
    <span
      v-if="isStatic"
      class="gl-flex gl-items-center gl-gap-2 gl-px-3 gl-py-2"
      data-testid="access-control-static"
    >
      <gl-icon
        v-if="selectedOption"
        :name="selectedOption.icon"
        :class="selectedOption.iconClass"
      />
      <span v-if="selectedOption" data-testid="access-control-static-text">
        {{ selectedOption.text }}
      </span>
      <gl-badge v-if="isConfigured" variant="info" data-testid="access-control-override">
        {{ $options.i18n.override }}
      </gl-badge>
    </span>

    <gl-collapsible-listbox
      v-else
      :items="listboxItems"
      :selected="listboxSelected"
      :disabled="disabled || isLoading"
      block
      panel-match-trigger-width
      class="gl-w-full"
      data-testid="access-control-listbox"
      @select="handleSelect"
    >
      <template #toggle>
        <gl-button
          category="secondary"
          size="small"
          block
          button-text-classes="gl-flex gl-items-center gl-gap-2"
          :disabled="disabled || isLoading"
          :aria-label="toggleLabel"
          data-testid="access-control-toggle"
        >
          <gl-loading-icon v-if="isLoading" size="sm" />
          <gl-icon
            v-else-if="selectedOption"
            :name="selectedOption.icon"
            :class="selectedOption.iconClass"
          />
          <span v-if="selectedOption" data-testid="access-control-toggle-text">
            {{ selectedOption.text }}
          </span>
          <gl-badge v-if="isConfigured" variant="info" data-testid="access-control-override">
            {{ $options.i18n.override }}
          </gl-badge>
          <gl-icon class="gl-ml-auto" name="chevron-down" />
        </gl-button>
      </template>
      <template #list-item="{ item }">
        <span
          v-gl-tooltip="item.disabled ? $options.FLOOR_DISABLED_TOOLTIP : ''"
          class="gl-flex gl-items-center gl-gap-3"
          :data-testid="`access-option-${item.value.toLowerCase()}`"
        >
          <gl-icon v-if="item.icon" :name="item.icon" :class="item.iconClass" />
          <span class="gl-flex gl-flex-col">
            {{ item.text }}
            <span
              v-if="item.hint"
              class="gl-text-sm gl-text-subtle"
              data-testid="access-option-hint"
            >
              {{ item.hint }}
            </span>
          </span>
        </span>
      </template>
    </gl-collapsible-listbox>
  </span>
</template>
