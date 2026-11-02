import { GlSearchBoxByType } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import BuildPolicyStep from 'ee/policy_store/components/editor/steps/build_policy_step.vue';
import CatalogGroup from 'ee/policy_store/components/editor/catalog_group.vue';
import CatalogSkeleton from 'ee/policy_store/components/editor/catalog_skeleton.vue';
import ConfigWrapper from 'ee/policy_store/components/editor/config_wrapper.vue';
import { emptyPolicyData } from 'ee/policy_store/components/editor/serializer';
import { ACTIONS } from 'ee/policy_store/catalog/actions';
import { HIDDEN_CATALOG_IDS } from 'ee/policy_store/catalog/hidden';
import { RULES } from 'ee/policy_store/catalog/rules';
import { TRIGGERS } from 'ee/policy_store/catalog/triggers';

// Spelled out rather than derived from HIDDEN_CATALOG_IDS: an expectation computed by
// re-running the filter under test adapts to a wrong id instead of failing on it.
const OFFERED_TRIGGERS = [
  'Project settings change requested',
  'Project created',
  'Project transferred',
];
const OFFERED_RULES = ['Setting validation'];
const OFFERED_ACTIONS = ['Block', 'Log audit trail', 'Set project setting'];
const HIDDEN_RULES = RULES.filter(({ id }) => HIDDEN_CATALOG_IDS.rules.includes(id));

describe('BuildPolicyStep', () => {
  let wrapper;

  // GlTabs (bootstrap-vue) registers its tabs asynchronously, so the nav links only
  // exist a tick after mount.
  const createComponent = async (policyData = {}, props = {}) => {
    wrapper = mountExtended(BuildPolicyStep, {
      propsData: {
        policyData: { ...emptyPolicyData(), ...policyData },
        catalogs: { triggers: TRIGGERS, rules: RULES, actions: ACTIONS },
        ...props,
      },
    });
    await nextTick();
  };

  // The drawer shows one tab at a time, so reaching a rule or action means opening its tab first.
  const openTab = async (tab) => {
    await wrapper.findByTestId(`${tab}-tab`).trigger('click');
  };

  const findTabs = () => wrapper.findAll('[role="tab"]');
  const findOptions = (tab) => wrapper.findAllByTestId(`${tab}-option`);
  // Exact match: with sibling labels like "Deployment requested" and
  // "Deployment promoted", a substring lookup would silently depend on
  // catalog ordering.
  const findOption = (tab, label) =>
    findOptions(tab).wrappers.find((option) => option.text().trim() === label);
  const labelsOf = (tab) => findOptions(tab).wrappers.map((option) => option.text().trim());
  const findSelected = (section) => wrapper.findAllByTestId(`${section}-selected`);
  const findAddButton = (section) => wrapper.findByTestId(`${section}-add`);
  const lastUpdate = () => {
    const updates = wrapper.emitted('update');
    return updates[updates.length - 1][0];
  };

  describe('drawer', () => {
    it('renders a tab per building block, with triggers open first', async () => {
      await createComponent();

      expect(findTabs().wrappers.map((tab) => tab.text())).toEqual([
        'Triggers',
        'Rules',
        'Actions',
      ]);
      expect(wrapper.findByTestId('triggers-tab').attributes('aria-selected')).toBe('true');
      expect(wrapper.findByTestId('rules-tab').attributes('aria-selected')).toBe('false');
    });

    it('shows only the open tab’s catalog', async () => {
      await createComponent();

      expect(labelsOf('triggers')).toEqual(OFFERED_TRIGGERS);
      expect(findOptions('rules')).toHaveLength(0);
    });

    it('lists the rules once its tab is open', async () => {
      await createComponent();

      await openTab('rules');

      expect(labelsOf('rules')).toEqual(OFFERED_RULES);
    });

    it('lists the actions once its tab is open', async () => {
      await createComponent();

      await openTab('actions');

      expect(labelsOf('actions')).toEqual(OFFERED_ACTIONS);
    });

    it('groups entries by category, in catalog order', async () => {
      await createComponent(
        {},
        {
          catalogs: {
            triggers: [
              { id: 'c1', label: 'Compliance one', category: 'compliance', fields: [] },
              { id: 'e1', label: 'Enforcement one', category: 'enforcement', fields: [] },
            ],
            rules: [],
            actions: [],
          },
        },
      );

      expect(
        wrapper.findAllComponents(CatalogGroup).wrappers.map((group) => group.props('group').label),
      ).toEqual(['Enforcement', 'Compliance']);
    });

    it('marks a selected entry as pressed', async () => {
      await createComponent({ trigger: 'project.after_create' });

      await openTab('triggers');

      expect(findOption('triggers', 'Project created').attributes('aria-pressed')).toBe('true');
      expect(findOption('triggers', 'Project transferred').attributes('aria-pressed')).toBe(
        'false',
      );
    });

    it('lists the catalog it receives rather than the local one', async () => {
      await createComponent(
        {},
        {
          catalogs: {
            triggers: [
              {
                id: 't1',
                label: 'Remote trigger',
                description: '',
                icon: 'question-o',
                fields: [],
              },
            ],
            rules: [],
            actions: [],
          },
        },
      );

      expect(findOptions('triggers')).toHaveLength(1);
      expect(findOptions('triggers').at(0).text()).toContain('Remote trigger');
    });

    it('shows the skeleton instead of the catalog while the catalogs load', async () => {
      await createComponent({}, { catalogsLoading: true });

      expect(wrapper.findComponent(CatalogSkeleton).exists()).toBe(true);
      expect(findOptions('triggers')).toHaveLength(0);
    });

    it('shows no skeleton once the catalogs have loaded', async () => {
      await createComponent();

      expect(wrapper.findComponent(CatalogSkeleton).exists()).toBe(false);
      expect(findOptions('triggers')).toHaveLength(OFFERED_TRIGGERS.length);
    });
  });

  describe('catalog error', () => {
    it('shows the alert on the failed tab, naming its catalog, with the items hidden', async () => {
      await createComponent({}, { failedCatalogs: ['triggers'] });

      expect(wrapper.findByTestId('catalogs-error').text()).toContain(
        'The available triggers could not be fetched from the Policy Store API.',
      );
      expect(findOptions('triggers')).toHaveLength(0);
      expect(wrapper.findByTestId('triggers-empty').exists()).toBe(false);
    });

    it('keeps the successful tabs intact when another catalog failed', async () => {
      await createComponent({}, { failedCatalogs: ['triggers'] });

      await openTab('rules');

      expect(wrapper.findByTestId('catalogs-error').exists()).toBe(false);
      expect(labelsOf('rules')).toEqual(OFFERED_RULES);
    });

    it('names the open tab’s catalog when several catalogs failed', async () => {
      await createComponent({}, { failedCatalogs: ['triggers', 'actions'] });

      await openTab('actions');

      expect(wrapper.findByTestId('catalogs-error').text()).toContain(
        'The available actions could not be fetched from the Policy Store API.',
      );
      expect(findOptions('actions')).toHaveLength(0);
    });

    it('shows no error alert by default', async () => {
      await createComponent();

      expect(wrapper.findByTestId('catalogs-error').exists()).toBe(false);
    });
  });

  describe('trigger selection', () => {
    it('selects a trigger', async () => {
      await createComponent();

      findOption('triggers', 'Project created').trigger('click');

      expect(lastUpdate().trigger).toBe('project.after_create');
    });

    it('clears the trigger when its option is clicked again', async () => {
      await createComponent({ trigger: 'project.after_create' });

      await openTab('triggers');
      findOption('triggers', 'Project created').trigger('click');

      expect(lastUpdate().trigger).toBeNull();
    });

    it('replaces the selected trigger and clears its config, since a policy stores one', async () => {
      await createComponent({
        trigger: 'project.after_create',
        triggerConfig: { environment: 'production' },
      });

      await openTab('triggers');
      findOption('triggers', 'Project transferred').trigger('click');

      expect(lastUpdate().trigger).toBe('project.after_transfer');
      expect(lastUpdate().triggerConfig).toEqual({});
    });

    it('clears the trigger config together with the selection', async () => {
      await createComponent({
        trigger: 'project.after_create',
        triggerConfig: { environment: 'production' },
      });

      await openTab('triggers');
      findOption('triggers', 'Project created').trigger('click');

      expect(lastUpdate().triggerConfig).toEqual({});
    });

    it('shows the selected trigger in the right panel', async () => {
      await createComponent({ trigger: 'project.after_create' });

      expect(findSelected('triggers')).toHaveLength(1);
      expect(findSelected('triggers').at(0).text()).toContain('Project created');
    });
  });

  describe('rule selection', () => {
    it('adds a rule without replacing the existing one', async () => {
      await createComponent({ rules: ['custom'] });

      await openTab('rules');
      findOption('rules', 'Setting validation').trigger('click');

      expect(lastUpdate().rules).toEqual(['custom', 'setting_validation']);
    });

    it('removes a rule when its catalog entry is clicked again', async () => {
      await createComponent({ rules: ['setting_validation', 'calendar'] });

      await openTab('rules');
      findOption('rules', 'Setting validation').trigger('click');

      expect(lastUpdate().rules).toEqual(['calendar']);
    });

    it('shows each selected rule in the right panel', async () => {
      await createComponent({ rules: ['custom', 'environment'] });

      expect(findSelected('rules')).toHaveLength(2);
    });

    it('joins selected rules with AND', async () => {
      await createComponent({ rules: ['custom', 'environment'] });

      expect(wrapper.text()).toContain('AND');
    });

    it('falls back to the raw id for a selection the catalog no longer knows', async () => {
      await createComponent({ rules: ['retired_rule'] });

      expect(findSelected('rules').at(0).text()).toContain('retired_rule');
      expect(wrapper.findByTestId('rules-selected-remove').attributes('aria-label')).toBe(
        'Remove retired_rule',
      );
    });
  });

  describe('configuration', () => {
    it('renders the config form for a selected rule with fields', async () => {
      await createComponent({ rules: ['environment'] });

      expect(wrapper.findComponent(ConfigWrapper).props('fields')).toHaveLength(2);
    });

    it('renders no config form for the trigger, which declares no fields', async () => {
      await createComponent({ trigger: 'project.after_create' });

      expect(wrapper.findComponent(ConfigWrapper).exists()).toBe(false);
    });

    it('records a rule config against that rule only', async () => {
      await createComponent({ rules: ['environment'] });

      wrapper.findComponent(ConfigWrapper).vm.$emit('input', { environment: 'production' });

      expect(lastUpdate().ruleConfigs).toEqual({
        environment: { environment: 'production' },
      });
    });

    it('keeps other rules’ configs when one changes', async () => {
      await createComponent({
        rules: ['environment', 'calendar'],
        ruleConfigs: { calendar: { timezone: 'UTC' } },
      });

      wrapper.findComponent(ConfigWrapper).vm.$emit('input', { environment: 'prod' });

      expect(lastUpdate().ruleConfigs).toEqual({
        calendar: { timezone: 'UTC' },
        environment: { environment: 'prod' },
      });
    });
  });

  describe('removing from the right panel', () => {
    it('removes a rule via its close button', async () => {
      await createComponent({ rules: ['custom', 'calendar'] });

      wrapper.findAllByTestId('rules-selected-remove').at(0).trigger('click');

      expect(lastUpdate().rules).toEqual(['calendar']);
    });

    it('keeps the configs of the remaining rules when one is removed', async () => {
      await createComponent({
        rules: ['custom', 'calendar'],
        ruleConfigs: { custom: { policy: 'package x' }, calendar: { timezone: 'UTC' } },
      });

      wrapper.findAllByTestId('rules-selected-remove').at(0).trigger('click');

      expect(lastUpdate().ruleConfigs).toEqual({
        custom: { policy: 'package x' },
        calendar: { timezone: 'UTC' },
      });
    });

    it('clears the trigger config when the trigger is removed', async () => {
      await createComponent({
        trigger: 'project.after_create',
        triggerConfig: { environment: 'production' },
      });

      wrapper.findByTestId('triggers-selected-remove').trigger('click');

      expect(lastUpdate().trigger).toBeNull();
      expect(lastUpdate().triggerConfig).toEqual({});
    });
  });

  describe('action selection', () => {
    it('adds an action', async () => {
      await createComponent({ actions: ['log_audit_trail'] });

      await openTab('actions');
      findOption('actions', 'Set project setting').trigger('click');

      expect(lastUpdate().actions).toEqual(['log_audit_trail', 'set_setting']);
    });
  });

  // An event trigger disables every offered blocking action and leaves the non-blocking ones
  // selectable. The rule runs one way only: a gate trigger disables nothing, blocking or not.
  // The reason sentences themselves are covered by
  // ee/spec/frontend/policy_store/catalog/compatibility_spec.js.
  describe('action compatibility with the selected trigger', () => {
    const findDisabledActions = () =>
      findOptions('actions')
        .wrappers.filter((option) => option.attributes('aria-disabled') === 'true')
        .map((option) => option.text().trim());

    it('disables a blocking action when the trigger runs after the change', async () => {
      await createComponent({ trigger: 'project.after_create' });

      await openTab('actions');

      expect(findDisabledActions()).toEqual(['Block']);
    });

    it.each([
      ['the trigger is asked before the change', { trigger: 'project.before_settings_update' }],
      ['no trigger is selected', {}],
    ])('disables no action when %s', async (_, policyData) => {
      await createComponent(policyData);

      await openTab('actions');

      expect(findDisabledActions()).toEqual([]);
    });

    // The config survives the deselection: only selected actions are serialized, so keeping
    // it makes switching triggers to compare, and switching back, non-destructive.
    it('deselects the actions a newly selected trigger disallows, keeping their config', async () => {
      await createComponent({
        trigger: 'project.before_settings_update',
        actions: ['block', 'require_approval'],
        actionConfigs: {
          block: { message: 'Not allowed' },
          require_approval: { roles: ['owner'] },
        },
      });

      await openTab('triggers');
      findOption('triggers', 'Project created').trigger('click');

      expect(lastUpdate().trigger).toBe('project.after_create');
      expect(lastUpdate().actions).toEqual([]);
      expect(lastUpdate().actionConfigs).toEqual({
        block: { message: 'Not allowed' },
        require_approval: { roles: ['owner'] },
      });
    });

    it('keeps a non-blocking action when the trigger disallows only the blocking ones', async () => {
      await createComponent({
        trigger: 'project.before_settings_update',
        actions: ['block', 'require_approval', 'log_audit_trail'],
      });

      await openTab('triggers');
      findOption('triggers', 'Project created').trigger('click');

      expect(lastUpdate().actions).toEqual(['log_audit_trail']);
    });

    it('keeps the config of an action the author merely deselected', async () => {
      await createComponent({
        trigger: 'project.before_settings_update',
        actions: [],
        actionConfigs: { block: { message: 'Not allowed' } },
      });

      await openTab('triggers');
      findOption('triggers', 'Project settings change requested').trigger('click');

      expect(lastUpdate().actionConfigs).toEqual({ block: { message: 'Not allowed' } });
    });

    it('ignores a click on an action the trigger disallows', async () => {
      await createComponent({ trigger: 'project.after_create' });

      await openTab('actions');
      findOption('actions', 'Block').trigger('click');

      expect(wrapper.emitted('update')).toBeUndefined();
    });

    it('keeps the selected actions when the new trigger still allows them', async () => {
      await createComponent({
        trigger: 'project.before_settings_update',
        actions: ['block'],
        actionConfigs: { block: { message: 'Not allowed' } },
      });

      await openTab('triggers');
      findOption('triggers', 'Project settings change requested').trigger('click');

      expect(lastUpdate().actions).toEqual(['block']);
      expect(lastUpdate().actionConfigs).toEqual({ block: { message: 'Not allowed' } });
    });
  });

  describe('search', () => {
    it('filters the open tab by label', async () => {
      await createComponent();

      await openTab('rules');
      wrapper.findComponent(GlSearchBoxByType).vm.$emit('input', 'validation');
      await nextTick();

      expect(findOptions('rules')).toHaveLength(1);
      expect(findOptions('rules').at(0).text()).toContain('Setting validation');
    });

    it('filters by description', async () => {
      await createComponent();

      await openTab('rules');
      wrapper.findComponent(GlSearchBoxByType).vm.$emit('input', 'does not match the required');
      await nextTick();

      expect(findOptions('rules')).toHaveLength(1);
      expect(findOptions('rules').at(0).text()).toContain('Setting validation');
    });

    it('shows a no-results message when nothing matches', async () => {
      await createComponent();

      await openTab('rules');
      wrapper.findComponent(GlSearchBoxByType).vm.$emit('input', 'nothing matches this');
      await nextTick();

      expect(wrapper.findByTestId('rules-empty').text()).toBe(
        'No building blocks match your search.',
      );
    });
  });

  describe('entries that are not ready to be authored', () => {
    it.each([
      ['triggers', OFFERED_TRIGGERS],
      ['rules', OFFERED_RULES],
      ['actions', OFFERED_ACTIONS],
    ])('offers exactly these %s', async (tab, labels) => {
      await createComponent();

      await openTab(tab);

      expect(labelsOf(tab)).toEqual(labels);
    });

    // The policy is still stored with that rule, so hiding it from the picker must not
    // reduce it to a raw id in the panel the author is editing.
    it('still names a hidden entry a policy already uses', async () => {
      await createComponent({ rules: ['custom'] });

      expect(findSelected('rules').at(0).text()).toContain('Custom Rule (Rego)');
    });

    // The hidden action is the only hidden entry carrying configuration, so a policy holding
    // it must still offer its fields rather than stranding the stored value.
    it('still configures a hidden action a policy already uses', async () => {
      await createComponent({
        actions: ['require_approval'],
        actionConfigs: { require_approval: { roles: ['owner'] } },
      });

      expect(findSelected('actions').at(0).text()).toContain('Require approval');
      expect(wrapper.findComponent(ConfigWrapper).props('value')).toEqual({
        roles: ['owner'],
      });
    });

    it('tells the author a tab offers nothing yet', async () => {
      await createComponent(
        {},
        { catalogs: { triggers: TRIGGERS, rules: HIDDEN_RULES, actions: ACTIONS } },
      );

      await openTab('rules');

      expect(wrapper.findByTestId('rules-empty').text()).toBe(
        'No building blocks are available yet.',
      );
    });

    // The author is likeliest to search for what used to be offered, and the search is not
    // why it is gone.
    it('still says so once the author searches a tab that offers nothing', async () => {
      await createComponent(
        {},
        { catalogs: { triggers: TRIGGERS, rules: HIDDEN_RULES, actions: ACTIONS } },
      );

      await openTab('rules');
      wrapper.findComponent(GlSearchBoxByType).vm.$emit('input', 'freeze');
      await nextTick();

      expect(wrapper.findByTestId('rules-empty').text()).toBe(
        'No building blocks are available yet.',
      );
    });
  });

  describe('field errors', () => {
    const findRuleConfig = () => wrapper.findComponent(ConfigWrapper);

    it('hands a rule the blockers its own config produced', async () => {
      await createComponent({ rules: ['custom'], ruleConfigs: {} });

      expect(findRuleConfig().props('fieldErrors')).toEqual({
        policy: 'Custom Rule (Rego) is missing Rego policy definition.',
      });
    });

    // Only the rules the wizard names: one the author added after stepping forward is not
    // a gap they skipped over, so it sits beside a revealed rule and stays neutral.
    it('reveals only the rules the wizard names', async () => {
      await createComponent(
        { rules: ['custom', 'environment'], ruleConfigs: {} },
        { revealedEntryIds: ['custom'] },
      );

      const forms = wrapper.findAllComponents(ConfigWrapper);

      expect(forms.at(0).props('showFieldErrors')).toBe(true);
      expect(forms.at(1).props('showFieldErrors')).toBe(false);
    });

    it('reveals nothing until the wizard names something', async () => {
      await createComponent({ rules: ['custom'], ruleConfigs: {} });

      expect(findRuleConfig().props('showFieldErrors')).toBe(false);
    });

    // Save only field-validates rules, so producing an inline message for an action would
    // send the author after a gap the save button never reports. Asserted beside a rule
    // that does produce one: an actions-only mount passes with the guard deleted. No action
    // declares a validatable field today, so the guard itself stays structurally untested.
    it('produces field errors for rules and none for actions', async () => {
      await createComponent({
        rules: ['custom'],
        ruleConfigs: {},
        actions: ['block'],
        actionConfigs: {},
      });

      const forms = wrapper.findAllComponents(ConfigWrapper);

      expect(forms.at(0).props('fieldErrors')).toEqual({
        policy: 'Custom Rule (Rego) is missing Rego policy definition.',
      });
      expect(forms.at(1).props('fieldErrors')).toEqual({});
    });

    it('hands a satisfied rule nothing', async () => {
      await createComponent({
        rules: ['custom'],
        ruleConfigs: { custom: { policy: 'package governance' } },
      });

      expect(findRuleConfig().props('fieldErrors')).toEqual({});
    });
  });

  describe('empty sections', () => {
    it.each([
      ['triggers', 'Add trigger'],
      ['rules', 'Add rule'],
      ['actions', 'Add action'],
    ])('offers an add button for the empty %s section', async (section, label) => {
      await createComponent();

      expect(findAddButton(section).text()).toBe(label);
    });

    it('opens the matching tab when the add button is clicked', async () => {
      await createComponent();

      await findAddButton('actions').trigger('click');

      expect(wrapper.findByTestId('actions-tab').attributes('aria-selected')).toBe('true');
      expect(findOptions('actions')).toHaveLength(OFFERED_ACTIONS.length);
    });

    it('hides the add button once the section has an entry', async () => {
      await createComponent({ rules: ['setting_validation'] });

      expect(findAddButton('rules').exists()).toBe(false);
    });
  });
});
