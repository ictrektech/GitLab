<script>
import { GlCollapsibleListbox, GlFormGroup } from '@gitlab/ui';
import { isEqual, omit, uniq, uniqueId } from 'lodash-es';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { s__ } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import { WIDGET_TYPE_WORKPLAN } from '~/work_items/constants';
import namespaceWorkItemTypesQuery from '~/work_items/graphql/namespace_work_item_types.query.graphql';
import {
  FILTER_FIELD_ACTION,
  FILTER_FIELD_WORK_ITEM_SOFTWARE_FACTORY_ENABLED,
  FILTER_FIELD_WORK_ITEM_STATUS_NAME,
  FILTER_FIELD_WORK_ITEM_TYPE_ID,
  FILTER_OPERATOR_IN,
  FLOW_TRIGGER_TYPE_WORK_ITEM,
  WORK_ITEM_ACTION_STATUS_CHANGED,
  WORK_ITEM_ACTIONS,
  WORK_ITEM_SOFTWARE_FACTORY_OPTIONS,
} from 'ee/ai/duo_agents_platform/constants';
import {
  filterWorkItemTypesByIds,
  parseWorkItemActionFilter,
  parseWorkItemSoftwareFactoryFilter,
  parseWorkItemStatusNamesFilter,
  parseWorkItemTypeIdsFilter,
  workItemTypeOptions,
} from 'ee/ai/duo_agents_platform/utils';
import { workItemTypesStatusNameOptions } from 'ee/ai/duo_agents_platform/utils/work_item_statuses';
import EventActionsConfiguration from './event_actions_configuration.vue';

const SCOPE = FLOW_TRIGGER_TYPE_WORK_ITEM.value;

const hasStatusChangedAction = (filter) =>
  parseWorkItemActionFilter(filter).includes(WORK_ITEM_ACTION_STATUS_CHANGED.value);

// Only work items of a type with the workplan widget can get the Software Factory marker.
// The query lists the widget only when the namespace has the license and the flag for it.
const hasWorkplanWidget = (workItemType) =>
  workItemType.widgetDefinitions?.some(({ type }) => type === WIDGET_TYPE_WORKPLAN) ?? false;

// Rules in a scope are AND-ed, so a status rule next to a "created" action would block
// creation events (they carry no status). Only allow it when "Status changed" is the sole action.
const allowsStatusFilter = (filter) =>
  isEqual(parseWorkItemActionFilter(filter), [WORK_ITEM_ACTION_STATUS_CHANGED.value]);

export default {
  name: 'WorkItemEventsConfiguration',
  components: {
    EventActionsConfiguration,
    GlCollapsibleListbox,
    GlFormGroup,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: ['projectPath'],
  props: {
    value: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    invalidFeedback: {
      type: String,
      required: false,
      default: null,
    },
  },
  emits: ['input'],
  apollo: {
    workItemTypes: {
      query: namespaceWorkItemTypesQuery,
      variables() {
        return { fullPath: this.projectPath };
      },
      update(data) {
        return data.namespace?.workItemTypes?.nodes ?? [];
      },
      error(error) {
        this.workItemTypesFailedToLoad = true;
        createAlert({
          message: s__(
            'DuoAgentsPlatform|Something went wrong while fetching work item types and statuses. Please try again.',
          ),
          captureError: true,
          error,
        });
      },
    },
  },
  data() {
    return {
      workItemTypes: [],
      workItemTypesFailedToLoad: false,
      typeToggleId: uniqueId('work-item-type-toggle-'),
      softwareFactoryToggleId: uniqueId('work-item-software-factory-toggle-'),
      statusToggleId: uniqueId('work-item-status-toggle-'),
    };
  },
  computed: {
    // When no type has the widget, only a selected option shows the listbox, so the user can
    // clear it. Before the types load, or after the query fails, the form cannot tell, so it
    // shows the listbox.
    showSoftwareFactoryListbox() {
      return (
        Boolean(this.glFeatures.dapSoftwareFactory) &&
        (this.softwareFactoryEnabled !== null ||
          !this.workItemTypes.length ||
          this.workplanTypeIds.length > 0)
      );
    },
    // When the flag is off, the form keeps a stored rule and does not limit the types by it.
    softwareFactoryEnabled() {
      return this.glFeatures.dapSoftwareFactory
        ? parseWorkItemSoftwareFactoryFilter(this.value)
        : null;
    },
    selectedSoftwareFactoryOption() {
      return (
        WORK_ITEM_SOFTWARE_FACTORY_OPTIONS.find(
          ({ ruleValue }) => ruleValue === this.softwareFactoryEnabled,
        )?.value ?? null
      );
    },
    workplanTypes() {
      return this.workItemTypes.filter(hasWorkplanWidget);
    },
    workplanTypeIds() {
      return this.workplanTypes.map(({ id }) => getIdFromGraphQLId(id));
    },
    // Before the types load, or after the query fails, no type would have the widget.
    softwareFactoryUnavailable() {
      return (
        this.workItemTypes.length > 0 &&
        !filterWorkItemTypesByIds(this.workItemTypes, this.selectedTypeIds).some(hasWorkplanWidget)
      );
    },
    softwareFactoryOptions() {
      return WORK_ITEM_SOFTWARE_FACTORY_OPTIONS.map(({ value, text, ruleValue }) => ({
        value,
        text,
        disabled: ruleValue && this.softwareFactoryUnavailable,
      }));
    },
    softwareFactoryToggleText() {
      return (
        WORK_ITEM_SOFTWARE_FACTORY_OPTIONS.find(
          ({ value }) => value === this.selectedSoftwareFactoryOption,
        )?.text ?? s__('DuoAgentsPlatform|Any work item')
      );
    },
    softwareFactoryDescription() {
      return this.softwareFactoryUnavailable
        ? s__('DuoAgentsPlatform|None of the available work item types support Software Factory.')
        : s__(
            'DuoAgentsPlatform|Run only for Software Factory work items, or only for other work items. Leave empty to run for any work item.',
          );
    },
    showStatusListbox() {
      return hasStatusChangedAction(this.value);
    },
    statusFilterEnabled() {
      return allowsStatusFilter(this.value);
    },
    isLoadingWorkItemTypes() {
      return this.$apollo.queries.workItemTypes.loading;
    },
    typeOptions() {
      return workItemTypeOptions(this.workItemTypes);
    },
    // A stored type without the workplan widget stays listed, so the user can clear it.
    typeItems() {
      if (this.softwareFactoryEnabled !== true) return this.typeOptions;

      const options = this.typeOptions.filter(({ value }) => this.workplanTypeIds.includes(value));
      const unsupportedOptions = this.typeOptions.filter(
        ({ value }) =>
          !this.workplanTypeIds.includes(value) && this.selectedTypeIds.includes(value),
      );

      if (!unsupportedOptions.length) return options;

      return [
        { text: s__('DuoAgentsPlatform|Work item types'), textSrOnly: true, options },
        {
          text: s__('DuoAgentsPlatform|Not supported by Software Factory'),
          options: unsupportedOptions,
        },
      ].filter((group) => group.options.length);
    },
    selectedTypeIds() {
      return parseWorkItemTypeIdsFilter(this.value);
    },
    // Undefined falls back to the listbox's own "No results found" text.
    typeNoResultsText() {
      return this.workItemTypesFailedToLoad
        ? s__('DuoAgentsPlatform|Could not load work item types. Refresh the page to try again.')
        : undefined;
    },
    // A type that the project does not list shows its ID. The type can be unavailable, such as
    // an OKR type when OKRs are off, or a project transfer can leave an ID with no type.
    typeToggleText() {
      if (!this.selectedTypeIds.length) return s__('DuoAgentsPlatform|Any type');

      return this.selectedTypeIds
        .map((id) => this.typeOptions.find((option) => option.value === id)?.text ?? String(id))
        .join(', ');
    },
    // A stored status that the types do not use stays listed, so the user can clear it.
    // Before the types load, or after the query fails, every status would look unused.
    statusOptions() {
      const options = workItemTypesStatusNameOptions(
        this.matchingWorkItemTypes(this.value),
        this.selectedTypeIds,
      );
      const unusedStatusNames = this.workItemTypes.length
        ? uniq(this.selectedStatusNames).filter(
            (name) => !options.some(({ value }) => value === name),
          )
        : [];

      if (!unusedStatusNames.length) return options;

      return [
        { text: s__('DuoAgentsPlatform|Statuses'), textSrOnly: true, options },
        {
          text: this.unusedStatusesText,
          options: unusedStatusNames.map((name) => ({ value: name, text: name })),
        },
      ].filter((group) => group.options.length);
    },
    unusedStatusesText() {
      if (this.selectedTypeIds.length) {
        return s__('DuoAgentsPlatform|Not used by the selected types');
      }

      return this.softwareFactoryEnabled === true
        ? s__('DuoAgentsPlatform|Not used by types that support Software Factory')
        : s__('DuoAgentsPlatform|Not used by any type');
    },
    selectedStatusNames() {
      return parseWorkItemStatusNamesFilter(this.value);
    },
    noResultsText() {
      return this.workItemTypesFailedToLoad
        ? s__('DuoAgentsPlatform|Could not load statuses. Refresh the page to try again.')
        : undefined;
    },
    toggleText() {
      return this.selectedStatusNames.length
        ? this.selectedStatusNames.join(', ')
        : s__('DuoAgentsPlatform|Any status');
    },
    statusDescription() {
      return this.statusFilterEnabled
        ? s__(
            'DuoAgentsPlatform|Run only when the work item changes to one of the selected statuses. Leave empty to run on any status change.',
          )
        : s__('DuoAgentsPlatform|Available only when Status changed is the only selected action.');
    },
  },
  methods: {
    onActionsInput(filter) {
      this.$emit(
        'input',
        allowsStatusFilter(filter)
          ? filter
          : this.withRule(filter, FILTER_FIELD_WORK_ITEM_STATUS_NAME, []),
      );
    },
    onTypeSelect(typeIds) {
      this.$emit('input', this.withTypeRule(this.value, typeIds));
    },
    onSoftwareFactorySelect(selectedValue) {
      const ruleValue = WORK_ITEM_SOFTWARE_FACTORY_OPTIONS.find(
        ({ value }) => value === selectedValue,
      )?.ruleValue;
      const filter = this.withRule(
        this.value,
        FILTER_FIELD_WORK_ITEM_SOFTWARE_FACTORY_ENABLED,
        ruleValue === undefined ? [] : [ruleValue],
      );

      // Before the types load, or after the query fails, no type would have the widget.
      if (ruleValue !== true || !this.workItemTypes.length) {
        this.$emit('input', filter);
        return;
      }

      // A type without the widget has no Software Factory work items, so it is not kept.
      // The form cannot tell if an unlisted type has the widget, so the type stays.
      const listedTypeIds = this.typeOptions.map(({ value }) => value);
      const typeIds = this.selectedTypeIds.filter(
        (id) => this.workplanTypeIds.includes(id) || !listedTypeIds.includes(id),
      );

      this.$emit(
        'input',
        typeIds.length === this.selectedTypeIds.length
          ? this.withMatchingStatuses(filter)
          : this.withTypeRule(filter, typeIds),
      );
    },
    onStatusSelect(statusNames) {
      this.$emit(
        'input',
        this.withRule(this.value, FILTER_FIELD_WORK_ITEM_STATUS_NAME, statusNames),
      );
    },
    withTypeRule(filter, typeIds) {
      return this.withMatchingStatuses(
        this.withRule(filter, FILTER_FIELD_WORK_ITEM_TYPE_ID, typeIds),
      );
    },
    // A status that none of the matching types has can never match, so it is not kept.
    withMatchingStatuses(filter) {
      const availableStatusNames = workItemTypesStatusNameOptions(
        this.matchingWorkItemTypes(filter),
        parseWorkItemTypeIdsFilter(filter),
      ).map(({ value }) => value);
      const selectedStatusNames = parseWorkItemStatusNamesFilter(filter);
      // Before the types load, or after the query fails, no status would be available.
      const statusNames = this.workItemTypes.length
        ? selectedStatusNames.filter((name) => availableStatusNames.includes(name))
        : selectedStatusNames;

      return statusNames.length === selectedStatusNames.length
        ? filter
        : this.withRule(filter, FILTER_FIELD_WORK_ITEM_STATUS_NAME, statusNames);
    },
    // With the rule in [true], only the types with the workplan widget can match.
    // When the flag is off, the form does not limit the types by a stored rule.
    matchingWorkItemTypes(filter) {
      return this.glFeatures.dapSoftwareFactory &&
        parseWorkItemSoftwareFactoryFilter(filter) === true
        ? this.workplanTypes
        : this.workItemTypes;
    },
    withRule(filter, field, values) {
      // This form owns every rule of the fields it edits.
      // API-authored variants are replaced, not AND-ed.
      const rules = (filter?.[SCOPE]?.rules ?? []).filter((rule) => rule.field !== field);

      if (values.length) {
        rules.push({ field, operator: FILTER_OPERATOR_IN, value: values });
      }

      if (!rules.length) return omit(filter, SCOPE);

      return { ...filter, [SCOPE]: { ...filter[SCOPE], rules } };
    },
  },
  WORK_ITEM_ACTIONS,
  FILTER_FIELD_ACTION,
  SCOPE,
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-4">
    <event-actions-configuration
      :scope="$options.SCOPE"
      :field="$options.FILTER_FIELD_ACTION"
      :actions="$options.WORK_ITEM_ACTIONS"
      :listbox-header-text="s__('DuoAgentsPlatform|Select work item actions')"
      :value="value"
      :invalid-feedback="invalidFeedback"
      @input="onActionsInput"
    />

    <gl-form-group
      :label="__('Type')"
      :label-for="typeToggleId"
      :description="
        s__(
          'DuoAgentsPlatform|Run only for work items of the selected types. Leave empty to run for any type.',
        )
      "
      class="!gl-mb-0"
      data-testid="type-form-group"
    >
      <gl-collapsible-listbox
        :toggle-id="typeToggleId"
        :items="typeItems"
        :selected="selectedTypeIds"
        :toggle-text="typeToggleText"
        :header-text="s__('DuoAgentsPlatform|Select work item types')"
        :loading="isLoadingWorkItemTypes"
        :no-results-text="typeNoResultsText"
        :reset-button-label="__('Clear')"
        multiple
        block
        data-testid="type-listbox"
        @select="onTypeSelect"
        @reset="onTypeSelect([])"
      />
    </gl-form-group>

    <gl-form-group
      v-if="showSoftwareFactoryListbox"
      :label="s__('DuoAgentsPlatform|Software Factory')"
      :label-for="softwareFactoryToggleId"
      :description="softwareFactoryDescription"
      class="!gl-mb-0"
      data-testid="software-factory-form-group"
    >
      <gl-collapsible-listbox
        :toggle-id="softwareFactoryToggleId"
        :items="softwareFactoryOptions"
        :selected="selectedSoftwareFactoryOption"
        :toggle-text="softwareFactoryToggleText"
        :header-text="s__('DuoAgentsPlatform|Select work items')"
        :reset-button-label="__('Clear')"
        block
        data-testid="software-factory-listbox"
        @select="onSoftwareFactorySelect"
        @reset="onSoftwareFactorySelect(null)"
      />
    </gl-form-group>

    <gl-form-group
      v-if="showStatusListbox"
      :label="s__('DuoAgentsPlatform|Status')"
      :label-for="statusToggleId"
      :description="statusDescription"
      class="!gl-mb-0"
      data-testid="status-form-group"
    >
      <gl-collapsible-listbox
        :toggle-id="statusToggleId"
        :items="statusOptions"
        :selected="selectedStatusNames"
        :toggle-text="toggleText"
        :header-text="s__('DuoAgentsPlatform|Select statuses')"
        :loading="isLoadingWorkItemTypes"
        :no-results-text="noResultsText"
        :disabled="!statusFilterEnabled"
        multiple
        block
        data-testid="status-listbox"
        @select="onStatusSelect"
      />
    </gl-form-group>
  </div>
</template>
