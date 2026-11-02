<script>
import { GlAlert, GlSearchBoxByType, GlTab, GlTabs } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import { disabledActionReasons } from '../../../catalog/compatibility';
import { HIDDEN_CATALOG_IDS } from '../../../catalog/hidden';
import { RULES } from '../../../catalog/rules';
import { entryFieldBlockers } from '../../../catalog/validation';
import { EMPTY_CATALOGS } from '../../../utils';
import { BUILD_TAB_ACTIONS, BUILD_TAB_RULES, BUILD_TAB_TRIGGERS } from '../constants';
import BuilderSection from '../builder_section.vue';
import CatalogGroup from '../catalog_group.vue';
import CatalogSkeleton from '../catalog_skeleton.vue';
import { groupCatalogItems } from '../utils';
import { TABS } from './constants';

const PANE_MIN_HEIGHT = { minHeight: 'max(24rem, calc(100vh - 16rem))' };
const TRIGGERS_TAB = TABS.find(({ id }) => id === BUILD_TAB_TRIGGERS);
const ACTIONS_TAB = TABS.find(({ id }) => id === BUILD_TAB_ACTIONS);
// Shared so the prop keeps its identity across renders of a tab that disables nothing.
const NO_DISABLED_ITEMS = Object.freeze({});
// Shared so an entry with nothing wrong keeps its prop identity across renders.
const NO_FIELD_ERRORS = Object.freeze({});

export default {
  name: 'BuildPolicyStep',
  components: {
    BuilderSection,
    CatalogGroup,
    CatalogSkeleton,
    GlAlert,
    GlSearchBoxByType,
    GlTab,
    GlTabs,
  },
  TABS,
  PANE_MIN_HEIGHT,
  i18n: {
    triggers: s__('PolicyStore|Triggers'),
    triggersDesc: s__('PolicyStore|When should this policy be evaluated?'),
    rules: s__('PolicyStore|Rules'),
    rulesDesc: s__('PolicyStore|What conditions must be met?'),
    actions: s__('PolicyStore|Actions'),
    actionsDesc: s__('PolicyStore|What happens when rules are matched?'),
    addTrigger: s__('PolicyStore|Add trigger'),
    addRule: s__('PolicyStore|Add rule'),
    addAction: s__('PolicyStore|Add action'),
    catalogTriggers: s__('PolicyStore|triggers'),
    catalogRules: s__('PolicyStore|rules'),
    catalogActions: s__('PolicyStore|actions'),
    noSearchResults: s__('PolicyStore|No building blocks match your search.'),
    noneAvailable: s__('PolicyStore|No building blocks are available yet.'),
  },
  props: {
    policyData: {
      type: Object,
      required: true,
    },
    catalogs: {
      type: Object,
      required: false,
      default: () => EMPTY_CATALOGS,
    },
    catalogsLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    failedCatalogs: {
      type: Array,
      required: false,
      default: () => [],
    },
    // The entries whose field errors are revealed without waiting for the author to edit
    // the control. The wizard decides which, since only it survives a step change.
    revealedEntryIds: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['update'],
  data() {
    return {
      activeTabId: BUILD_TAB_TRIGGERS,
      search: '',
    };
  },
  computed: {
    activeTab() {
      return TABS.find(({ id }) => id === this.activeTabId);
    },
    activeTabIndex: {
      get() {
        return TABS.findIndex(({ id }) => id === this.activeTabId);
      },
      set(index) {
        this.activeTabId = TABS[index].id;
      },
    },
    // What the active tab offers an author. `catalogFor` stays whole, so a policy that already
    // uses a hidden entry keeps resolving its label and configuration fields.
    offerable() {
      const hidden = HIDDEN_CATALOG_IDS[this.activeTab.id] || [];

      return this.catalogFor(this.activeTab).filter(({ id }) => !hidden.includes(id));
    },
    activeGroups() {
      return groupCatalogItems(this.offerable, this.search);
    },
    // Keyed on what the tab offers rather than on the search box: a tab offering nothing
    // has nothing to match, so blaming the author's search for it would be wrong.
    activeTabEmptyMessage() {
      return this.offerable.length
        ? this.$options.i18n.noSearchResults
        : this.$options.i18n.noneAvailable;
    },
    // Each catalog fails independently, so the alert belongs to the tab whose
    // catalog failed; the other tabs keep rendering their entries.
    activeTabFailed() {
      return this.failedCatalogs.includes(this.activeTabId);
    },
    catalogsErrorMessage() {
      const names = {
        [BUILD_TAB_TRIGGERS]: this.$options.i18n.catalogTriggers,
        [BUILD_TAB_RULES]: this.$options.i18n.catalogRules,
        [BUILD_TAB_ACTIONS]: this.$options.i18n.catalogActions,
      };

      return sprintf(
        s__(
          'PolicyStore|The available %{catalog} could not be fetched from the Policy Store API. Refresh the page to try again.',
        ),
        { catalog: names[this.activeTabId] },
      );
    },
    disabledActions() {
      return this.actionReasonsFor(this.policyData.trigger);
    },
    sections() {
      return TABS.map((tab) => {
        const errors = this.fieldErrorsFor(tab);

        return {
          ...tab,
          heading: this.tabLabel(tab),
          description: this.descriptionFor(tab),
          addLabel: this.addLabelFor(tab),
          entries: this.selectedIds(tab).map((id) => ({
            ...this.entryDefinition(tab, id),
            config: this.configFor(tab, id),
            fieldErrors: errors[id] ?? NO_FIELD_ERRORS,
            showFieldErrors: this.revealedEntryIds.includes(id),
          })),
        };
      });
    },
  },
  methods: {
    tabLabel({ id }) {
      return {
        [BUILD_TAB_TRIGGERS]: this.$options.i18n.triggers,
        [BUILD_TAB_RULES]: this.$options.i18n.rules,
        [BUILD_TAB_ACTIONS]: this.$options.i18n.actions,
      }[id];
    },
    tabLinkAttributes({ id }) {
      // eslint-disable-next-line @gitlab/require-i18n-strings -- a testid, not copy
      return { 'data-testid': `${id}-tab` };
    },
    descriptionFor({ id }) {
      return {
        [BUILD_TAB_TRIGGERS]: this.$options.i18n.triggersDesc,
        [BUILD_TAB_RULES]: this.$options.i18n.rulesDesc,
        [BUILD_TAB_ACTIONS]: this.$options.i18n.actionsDesc,
      }[id];
    },
    addLabelFor({ id }) {
      return {
        [BUILD_TAB_TRIGGERS]: this.$options.i18n.addTrigger,
        [BUILD_TAB_RULES]: this.$options.i18n.addRule,
        [BUILD_TAB_ACTIONS]: this.$options.i18n.addAction,
      }[id];
    },
    catalogFor({ id }) {
      return this.catalogs[id] || [];
    },
    definition(tab, id) {
      return this.catalogFor(tab).find((entry) => entry.id === id);
    },
    // A selection the catalog no longer knows still renders as its raw id rather
    // than a blank, broken entry.
    entryDefinition(tab, id) {
      return (
        this.definition(tab, id) ?? {
          id,
          label: id,
          description: '',
          icon: 'question-o',
          fields: [],
        }
      );
    },
    selectedIds({ single, selectionKey }) {
      const value = this.policyData[selectionKey];

      if (single) return value ? [value] : [];

      return value || [];
    },
    isSelected(tab, id) {
      return this.selectedIds(tab).includes(id);
    },
    // Rules are the only building block the save button field-validates, and it validates
    // them against the static catalog so blockers survive a fetch failure (step_wizard's
    // saveBlockers). Both choices are repeated here: an inline message naming a gap the
    // save button does not also report would send the author after nothing.
    fieldErrorsFor(tab) {
      if (tab.id !== BUILD_TAB_RULES) return NO_FIELD_ERRORS;

      const ids = this.selectedIds(tab);
      // Through `configFor`, so a single-selection tab's un-keyed config still resolves if
      // this ever validates one: reading `policyData[configKey]` flat would hand every id
      // the same object.
      const configs = Object.fromEntries(ids.map((id) => [id, this.configFor(tab, id)]));

      return entryFieldBlockers(RULES, ids, configs);
    },
    configFor({ configKey, single }, id) {
      const configs = this.policyData[configKey] || {};

      return single ? configs : configs[id] || {};
    },
    emit(changes) {
      this.$emit('update', { ...this.policyData, ...changes });
    },
    disabledItemsFor({ id }) {
      return id === BUILD_TAB_ACTIONS ? this.disabledActions : NO_DISABLED_ITEMS;
    },
    // Resolved against the fetched catalog rather than the static TRIGGERS import, so the
    // kind comes from the same entry the picker rendered. That entry is still the local one:
    // `presentable` keeps the local catalog's fields for any id it knows.
    actionReasonsFor(triggerId) {
      return disabledActionReasons(
        this.definition(TRIGGERS_TAB, triggerId),
        this.catalogFor(ACTIONS_TAB),
      );
    },
    // Changing the trigger can invalidate an action already selected, so the same emit that
    // replaces the trigger deselects those actions. That clears the pairings this rule rules
    // out, not every pairing the store could refuse.
    //
    // Their configuration stays: only selected actions are serialized, so an author who
    // switches triggers to compare and switches back still has what they typed.
    actionsAllowedBy(triggerId) {
      const reasons = this.actionReasonsFor(triggerId);

      return {
        [ACTIONS_TAB.selectionKey]: this.selectedIds(ACTIONS_TAB).filter((id) => !reasons[id]),
      };
    },
    add(tab, id) {
      const { single, selectionKey, configKey } = tab;

      // Triggers are the only single-selection tab, and the trigger is what the action
      // compatibility rule reads.
      if (single) {
        const selected = this.isSelected(tab, id) ? null : id;

        this.emit({
          [selectionKey]: selected,
          [configKey]: {},
          ...this.actionsAllowedBy(selected),
        });
      } else {
        const selected = this.selectedIds(tab);

        this.emit({
          [selectionKey]: this.isSelected(tab, id)
            ? selected.filter((selectedId) => selectedId !== id)
            : [...selected, id],
        });
      }
    },
    remove(tab, id) {
      const { single, selectionKey, configKey } = tab;

      if (single) {
        this.emit({ [selectionKey]: null, [configKey]: {} });
      } else {
        this.emit({
          [selectionKey]: this.selectedIds(tab).filter((selectedId) => selectedId !== id),
        });
      }
    },
    updateConfig(tab, id, config) {
      const { configKey, single } = tab;

      this.emit({
        [configKey]: single ? config : { ...(this.policyData[configKey] || {}), [id]: config },
      });
    },
    openTab(tab) {
      this.activeTabId = tab.id;
    },
  },
};
</script>

<template>
  <div
    class="gl-flex gl-flex-col gl-gap-5 md:gl-flex-row md:gl-gap-0 md:gl-overflow-hidden"
    :style="$options.PANE_MIN_HEIGHT"
  >
    <div class="gl-flex gl-w-full gl-flex-shrink-0 gl-flex-col md:gl-my-6 md:gl-w-1/4">
      <div
        class="gl-border gl-flex gl-max-h-62 gl-min-h-0 gl-flex-1 gl-flex-col gl-overflow-hidden gl-rounded-2xl gl-border-subtle gl-bg-strong md:gl-max-h-none"
      >
        <gl-tabs
          v-model="activeTabIndex"
          justified
          content-class="gl-hidden"
          class="gl-flex-shrink-0"
        >
          <gl-tab
            v-for="tab in $options.TABS"
            :key="tab.id"
            :title="tabLabel(tab)"
            :title-link-attributes="tabLinkAttributes(tab)"
          />
        </gl-tabs>

        <!-- Search stays put; only the list below it scrolls. -->
        <div class="gl-flex gl-flex-shrink-0 gl-items-center gl-gap-2 gl-px-3 gl-pb-2 gl-pt-3">
          <gl-search-box-by-type
            v-model="search"
            :placeholder="s__('PolicyStore|Search…')"
            class="gl-flex-1"
          />
        </div>

        <gl-alert
          v-if="activeTabFailed"
          variant="danger"
          :dismissible="false"
          class="gl-mx-4 gl-mb-3"
          data-testid="catalogs-error"
        >
          {{ catalogsErrorMessage }}
        </gl-alert>

        <div
          class="gl-flex gl-flex-1 gl-flex-col gl-gap-3 gl-overflow-y-auto gl-px-3 gl-pb-3 gl-pt-1"
        >
          <catalog-skeleton v-if="catalogsLoading" />

          <template v-else-if="!activeTabFailed">
            <p
              v-if="!activeGroups.length"
              :data-testid="`${activeTab.id}-empty`"
              class="gl-mb-0 gl-text-subtle"
            >
              {{ activeTabEmptyMessage }}
            </p>

            <catalog-group
              v-for="group in activeGroups"
              :key="group.label"
              :group="group"
              :selected-ids="selectedIds(activeTab)"
              :disabled-items="disabledItemsFor(activeTab)"
              :option-testid="`${activeTab.id}-option`"
              @select="add(activeTab, $event)"
            />
          </template>
        </div>
      </div>
    </div>

    <div class="gl-flex gl-min-w-0 gl-flex-1 gl-flex-col md:gl-overflow-hidden">
      <div
        class="gl-flex gl-flex-1 gl-flex-col gl-items-center gl-px-0 gl-py-4 md:gl-overflow-y-auto md:gl-px-10"
      >
        <div class="gl-flex gl-w-full gl-flex-col gl-gap-5">
          <builder-section
            v-for="section in sections"
            :key="section.id"
            :section="section"
            @add="openTab(section)"
            @remove="remove(section, $event)"
            @update-config="updateConfig(section, $event.id, $event.config)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
