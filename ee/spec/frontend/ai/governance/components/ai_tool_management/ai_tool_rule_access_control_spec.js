import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlBadge, GlCollapsibleListbox, GlIcon, GlLoadingIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import AiToolRuleAccessControl from 'ee/ai/governance/components/ai_tool_management/ai_tool_rule_access_control.vue';
import updateAiToolRuleMutation from 'ee/ai/governance/graphql/mutations/update_ai_tool_rule.mutation.graphql';

jest.mock('~/alert');

Vue.use(VueApollo);

const accessValues = ({ webAccess = null, localAccess = null, backgroundAccess = null } = {}) => ({
  webAccess,
  localAccess,
  backgroundAccess,
  __typename: 'AiToolRuleAccess',
});

const mockDefaultAccess = accessValues({
  webAccess: 'ASK',
  localAccess: 'ASK',
  backgroundAccess: 'ALLOW',
});

const mockToolRule = {
  id: 'list_issues',
  name: 'list_issues',
  webAccess: 'ALLOW',
  localAccess: null,
  backgroundAccess: null,
  configuredAccess: accessValues({ webAccess: 'ALLOW' }),
  defaultAccess: mockDefaultAccess,
  __typename: 'AiToolRule',
};

const unsetToolRule = {
  ...mockToolRule,
  webAccess: 'ASK',
  localAccess: 'ASK',
  backgroundAccess: 'ALLOW',
  configuredAccess: accessValues(),
};

const mockMutationSuccess = ({ toolRule: toolRuleOverrides, ...overrides } = {}) => {
  const toolRule =
    toolRuleOverrides === null
      ? null
      : {
          id: 'list_issues',
          webAccess: 'ASK',
          localAccess: 'ASK',
          backgroundAccess: 'ALLOW',
          configuredAccess: accessValues({ webAccess: 'ASK' }),
          defaultAccess: mockDefaultAccess,
          __typename: 'AiToolRule',
          ...toolRuleOverrides,
        };

  return {
    data: {
      updateAiToolRule: {
        toolRule,
        errors: [],
        __typename: 'UpdateAiToolRulePayload',
        ...overrides,
      },
    },
  };
};

describe('AiToolRuleAccessControl', () => {
  let wrapper;
  let mutationHandler;
  let apolloProvider;

  const createComponent = ({
    toolRule = mockToolRule,
    accessType = 'webAccess',
    groupFullPath = 'gitlab-org',
    projectFullPath = '',
    floorValue = null,
    disabled = false,
    disabledTooltip = '',
    mutationHandlerImpl = jest.fn().mockResolvedValue(mockMutationSuccess()),
  } = {}) => {
    mutationHandler = mutationHandlerImpl;
    apolloProvider = createMockApollo([[updateAiToolRuleMutation, mutationHandler]]);

    wrapper = mountExtended(AiToolRuleAccessControl, {
      apolloProvider,
      propsData: {
        toolRule,
        accessType,
        groupFullPath,
        projectFullPath,
        floorValue,
        disabled,
        disabledTooltip,
      },
    });
  };

  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findToggle = () => wrapper.findByTestId('access-control-toggle');
  const findToggleText = () => wrapper.findByTestId('access-control-toggle-text');
  const findToggleLoadingIcon = () => findToggle().findComponent(GlLoadingIcon);
  const findListItem = (value) => wrapper.findByTestId(`access-option-${value.toLowerCase()}`);
  const findStatic = () => wrapper.findByTestId('access-control-static');
  const findStaticText = () => wrapper.findByTestId('access-control-static-text');
  const findItems = () =>
    findListbox()
      .props('items')
      .flatMap((item) => item.options ?? [item]);
  const selectOption = (value) => findListbox().vm.$emit('select', value);

  describe('rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a collapsible listbox', () => {
      expect(findListbox().exists()).toBe(true);
    });

    it('renders the toggle with the selected option text', () => {
      expect(findToggleText().text()).toBe('Always allow');
    });
  });

  describe('selected state', () => {
    it('reflects the value from toolRule[accessType] for webAccess', () => {
      createComponent({
        toolRule: { ...mockToolRule, webAccess: 'ASK' },
        accessType: 'webAccess',
      });

      expect(findToggleText().text()).toBe('Always ask');
    });

    it('renders a bell icon on the toggle for ASK', () => {
      createComponent({ toolRule: { ...mockToolRule, webAccess: 'ASK' } });

      expect(findToggle().findAllComponents(GlIcon).at(0).props('name')).toBe('notifications');
    });

    it('reflects the value from toolRule[accessType] for localAccess', () => {
      createComponent({
        toolRule: {
          ...mockToolRule,
          localAccess: 'DENY',
          configuredAccess: accessValues({ localAccess: 'DENY' }),
        },
        accessType: 'localAccess',
      });

      expect(findToggleText().text()).toBe('Always deny');
    });

    it('renders the toggle blank when no value is set', () => {
      createComponent({
        toolRule: { ...mockToolRule, webAccess: null, localAccess: null },
        accessType: 'webAccess',
      });

      expect(findToggleText().exists()).toBe(false);
    });
  });

  describe('list items', () => {
    beforeEach(() => {
      createComponent({ toolRule: { ...mockToolRule, webAccess: 'ASK' } });
    });

    it.each(['ALLOW', 'ASK', 'DENY'])('renders the %s option with its icon', (value) => {
      const item = findListItem(value);
      expect(item.exists()).toBe(true);
      expect(item.findComponent(GlIcon).exists()).toBe(true);
    });

    it('renders a bell icon for the ASK option', () => {
      expect(findListItem('ASK').findComponent(GlIcon).props('name')).toBe('notifications');
    });
  });

  describe('when an option is selected', () => {
    it('does not call the mutation when the already-selected value is chosen', async () => {
      createComponent({
        toolRule: {
          ...mockToolRule,
          webAccess: 'ASK',
          configuredAccess: accessValues({ webAccess: 'ASK' }),
        },
      });

      selectOption('ASK');
      await waitForPromises();

      expect(mutationHandler).not.toHaveBeenCalled();
    });

    it('calls the mutation with only the changed accessType for webAccess', async () => {
      createComponent({ accessType: 'webAccess' });

      selectOption('ASK');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: {
          fullPath: 'gitlab-org',
          toolId: 'list_issues',
          webAccess: 'ASK',
        },
      });
    });

    describe('disabled (read-only) state', () => {
      it('renders the value statically instead of a listbox', () => {
        createComponent({ disabled: true });

        expect(findListbox().exists()).toBe(false);
        expect(findStatic().exists()).toBe(true);
        expect(findStaticText().text()).toBe('Always allow');
      });

      it('renders a bell icon for a static ASK value', () => {
        createComponent({ toolRule: { ...mockToolRule, webAccess: 'ASK' }, disabled: true });

        expect(findStatic().findComponent(GlIcon).props('name')).toBe('notifications');
      });
    });

    it('calls the mutation with only the changed accessType for localAccess', async () => {
      createComponent({
        toolRule: { ...mockToolRule, localAccess: null },
        accessType: 'localAccess',
      });

      selectOption('DENY');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: {
          fullPath: 'gitlab-org',
          toolId: 'list_issues',
          localAccess: 'DENY',
        },
      });
    });

    it('disables the listbox and shows a loading indicator in the toggle while the mutation is in flight', async () => {
      let resolveMutation;
      createComponent({
        mutationHandlerImpl: jest.fn(
          () =>
            new Promise((resolve) => {
              resolveMutation = resolve;
            }),
        ),
      });

      selectOption('ASK');
      await Vue.nextTick();

      expect(findListbox().props('disabled')).toBe(true);
      expect(findToggleLoadingIcon().exists()).toBe(true);

      resolveMutation(mockMutationSuccess());
      await waitForPromises();

      expect(findListbox().props('disabled')).toBe(false);
      expect(findToggleLoadingIcon().exists()).toBe(false);
    });

    it('does not call the mutation while a previous request is in flight', async () => {
      createComponent({
        mutationHandlerImpl: jest.fn(() => new Promise(() => {})),
      });

      selectOption('ASK');
      await Vue.nextTick();
      selectOption('DENY');
      await Vue.nextTick();

      expect(mutationHandler).toHaveBeenCalledTimes(1);
    });

    it('writes the updated value to the Apollo cache for the AiToolRule entity', async () => {
      createComponent({ accessType: 'webAccess' });
      const writeFragmentSpy = jest.spyOn(apolloProvider.defaultClient, 'writeFragment');

      selectOption('ASK');
      await waitForPromises();

      expect(writeFragmentSpy).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'AiToolRule:list_issues',
          data: expect.objectContaining({
            __typename: 'AiToolRule',
            webAccess: 'ASK',
            localAccess: 'ASK',
            configuredAccess: expect.objectContaining({ webAccess: 'ASK', localAccess: null }),
            defaultAccess: expect.objectContaining({ webAccess: 'ASK' }),
          }),
        }),
      );
    });

    it('writes the updated backgroundAccess value to the Apollo cache', async () => {
      createComponent({
        toolRule: { ...mockToolRule, backgroundAccess: null },
        accessType: 'backgroundAccess',
        mutationHandlerImpl: jest.fn().mockResolvedValue(
          mockMutationSuccess({
            toolRule: { backgroundAccess: 'DENY' },
          }),
        ),
      });
      const writeFragmentSpy = jest.spyOn(apolloProvider.defaultClient, 'writeFragment');

      selectOption('DENY');
      await waitForPromises();

      expect(writeFragmentSpy).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'AiToolRule:list_issues',
          data: expect.objectContaining({
            __typename: 'AiToolRule',
            backgroundAccess: 'DENY',
          }),
        }),
      );
    });
  });

  describe('error handling', () => {
    afterEach(() => {
      createAlert.mockClear();
    });

    it('shows an alert and does not write to the cache when the mutation returns errors', async () => {
      createComponent({
        mutationHandlerImpl: jest.fn().mockResolvedValue(
          mockMutationSuccess({
            toolRule: null,
            errors: ['Something went wrong'],
          }),
        ),
      });
      const writeFragmentSpy = jest.spyOn(apolloProvider.defaultClient, 'writeFragment');

      selectOption('ASK');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to update tool rule. Please try again.',
        captureError: true,
      });
      expect(writeFragmentSpy).not.toHaveBeenCalled();
    });

    it('shows an alert and does not write to the cache when the mutation throws', async () => {
      createComponent({
        mutationHandlerImpl: jest.fn().mockRejectedValue(new Error('Network error')),
      });
      const writeFragmentSpy = jest.spyOn(apolloProvider.defaultClient, 'writeFragment');

      selectOption('ASK');
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to update tool rule. Please try again.',
        captureError: true,
      });
      expect(writeFragmentSpy).not.toHaveBeenCalled();
    });

    it('clears the loading state after a failed mutation', async () => {
      createComponent({
        mutationHandlerImpl: jest.fn().mockRejectedValue(new Error('Network error')),
      });

      selectOption('ASK');
      await waitForPromises();

      expect(findListbox().props('disabled')).toBe(false);
      expect(findToggleLoadingIcon().exists()).toBe(false);
    });
  });

  describe('project mode', () => {
    const findItem = (value) => findItems().find((item) => item.value === value);

    it('includes projectPath in the mutation input when projectFullPath is set', async () => {
      createComponent({
        accessType: 'webAccess',
        projectFullPath: 'gitlab-org/my-project',
      });

      selectOption('DENY');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: {
          fullPath: 'gitlab-org',
          projectPath: 'gitlab-org/my-project',
          toolId: 'list_issues',
          webAccess: 'DENY',
        },
      });
    });

    it.each(['webAccess', 'localAccess', 'backgroundAccess'])(
      'sends only the changed %s cell',
      async (accessType) => {
        createComponent({
          toolRule: {
            ...mockToolRule,
            webAccess: 'ALLOW',
            localAccess: 'ASK',
            backgroundAccess: 'ALLOW',
          },
          accessType,
          projectFullPath: 'gitlab-org/my-project',
        });

        selectOption('DENY');
        await waitForPromises();

        expect(mutationHandler).toHaveBeenCalledWith({
          input: {
            fullPath: 'gitlab-org',
            projectPath: 'gitlab-org/my-project',
            toolId: 'list_issues',
            [accessType]: 'DENY',
          },
        });
      },
    );

    describe('floor enforcement', () => {
      it('keeps a listbox and disables options less restrictive than an ASK floor', () => {
        createComponent({
          toolRule: { ...mockToolRule, webAccess: 'ASK' },
          floorValue: 'ASK',
        });

        expect(findListbox().exists()).toBe(true);
        expect(findItem('ALLOW').disabled).toBe(true);
        expect(findItem('ASK').disabled).toBe(false);
        expect(findItem('DENY').disabled).toBe(false);
      });

      it('does not show the floor tooltip while the dropdown is still interactive', () => {
        createComponent({
          toolRule: { ...mockToolRule, webAccess: 'ASK' },
          floorValue: 'ASK',
        });

        expect(findListbox().exists()).toBe(true);
        expect(wrapper.vm.staticTooltip).toBe('');
      });

      it('leaves every option enabled when no floor value is provided (group mode)', () => {
        createComponent({ floorValue: null });

        expect(findListbox().exists()).toBe(true);
        expect(findItem('ALLOW').disabled).toBeUndefined();
        expect(findItem('ASK').disabled).toBeUndefined();
        expect(findItem('DENY').disabled).toBeUndefined();
      });
    });
  });

  describe('not set state', () => {
    const findOverride = () => wrapper.findByTestId('access-control-override');
    const findUnsetItem = () => findListbox().props('items')[0].options[0];

    describe('when the cell is unset', () => {
      beforeEach(() => {
        createComponent({ toolRule: unsetToolRule });
      });

      it('shows only the value and ticks the default option', () => {
        expect(findToggleText().text()).toBe('Always ask');
        expect(findToggle().attributes('aria-label')).toBe('Always ask');
        expect(findOverride().exists()).toBe(false);
        expect(findListbox().props('selected')).toBe('UNSET');
      });

      it('offers a default option with the value it uses as a hint', () => {
        expect(findUnsetItem()).toMatchObject({
          value: 'UNSET',
          text: 'Default',
          hint: 'Uses Always ask',
        });
        expect(wrapper.findByTestId('access-option-hint').text()).toBe('Uses Always ask');
      });

      it('saves the default value as a rule when picked', async () => {
        selectOption('ASK');
        await waitForPromises();

        expect(mutationHandler).toHaveBeenCalledWith({
          input: { fullPath: 'gitlab-org', toolId: 'list_issues', webAccess: 'ASK' },
        });
      });

      it('does nothing when the default option is picked', async () => {
        selectOption('UNSET');
        await waitForPromises();

        expect(mutationHandler).not.toHaveBeenCalled();
      });
    });

    describe('when the cell is set', () => {
      beforeEach(() => {
        createComponent();
      });

      it('shows the value with an override badge and ticks it', () => {
        expect(findToggleText().text()).toBe('Always allow');
        expect(findOverride().text()).toBe('Override');
        expect(wrapper.findComponent(GlBadge).props('variant')).toBe('info');
        expect(findToggle().attributes('aria-label')).toBe('Always allow, set as an override');
        expect(findListbox().props('selected')).toBe('ALLOW');
      });

      it('does nothing when the current value is picked', async () => {
        selectOption('ALLOW');
        await waitForPromises();

        expect(mutationHandler).not.toHaveBeenCalled();
      });

      it('clears the cell when the default option is picked', async () => {
        selectOption('UNSET');
        await waitForPromises();

        expect(mutationHandler).toHaveBeenCalledWith({
          input: {
            fullPath: 'gitlab-org',
            toolId: 'list_issues',
            unsetAccessTypes: ['WEB_ACCESS'],
          },
        });
      });
    });

    it('shows the value and the override badge in the static view', () => {
      createComponent({ disabled: true });

      expect(findStaticText().text()).toBe('Always allow');
      expect(findOverride().exists()).toBe(true);
    });

    it('shows only the value in the static view of an unset cell', () => {
      createComponent({ toolRule: unsetToolRule, disabled: true });

      expect(findStaticText().text()).toBe('Always ask');
      expect(findOverride().exists()).toBe(false);
    });

    describe('at project scope', () => {
      const projectFullPath = 'gitlab-org/my-project';
      const allowDefaultRule = {
        ...unsetToolRule,
        defaultAccess: accessValues({ webAccess: 'ALLOW' }),
      };

      it('offers an inherit option that uses the floor value', () => {
        createComponent({ toolRule: allowDefaultRule, projectFullPath, floorValue: 'ASK' });

        expect(findUnsetItem()).toMatchObject({ text: 'Inherit', hint: 'Uses Always ask' });
      });

      it('uses the default when there is no floor', () => {
        createComponent({ toolRule: allowDefaultRule, projectFullPath });

        expect(findUnsetItem()).toMatchObject({ text: 'Inherit', hint: 'Uses Always allow' });
      });

      it('sends projectPath when clearing a project cell', async () => {
        createComponent({ projectFullPath });

        selectOption('UNSET');
        await waitForPromises();

        expect(mutationHandler).toHaveBeenCalledWith({
          input: {
            fullPath: 'gitlab-org',
            projectPath: projectFullPath,
            toolId: 'list_issues',
            unsetAccessTypes: ['WEB_ACCESS'],
          },
        });
      });

      it('renders an unset single-option cell statically', () => {
        createComponent({
          toolRule: { ...unsetToolRule, webAccess: 'DENY' },
          projectFullPath,
          floorValue: 'DENY',
        });

        expect(findListbox().exists()).toBe(false);
        expect(findStaticText().text()).toBe('Always deny');
      });

      it('keeps the listbox on a set single-option cell so it can be cleared', () => {
        createComponent({
          toolRule: {
            ...mockToolRule,
            webAccess: 'DENY',
            configuredAccess: accessValues({ webAccess: 'DENY' }),
          },
          projectFullPath,
          floorValue: 'DENY',
        });

        expect(findListbox().exists()).toBe(true);
      });
    });

    describe('with an older backend', () => {
      it('behaves as before when configuredAccess is missing', async () => {
        createComponent({
          toolRule: { ...mockToolRule, configuredAccess: null, defaultAccess: null },
        });

        expect(findToggleText().text()).toBe('Always allow');
        expect(findOverride().exists()).toBe(false);
        expect(findListbox().props('selected')).toBe('ALLOW');
        expect(
          findListbox()
            .props('items')
            .map((item) => item.value),
        ).toEqual(['ALLOW', 'ASK', 'DENY']);

        selectOption('ALLOW');
        await waitForPromises();

        expect(mutationHandler).not.toHaveBeenCalled();
      });

      it('falls back to the effective value when defaultAccess is missing', () => {
        createComponent({ toolRule: { ...unsetToolRule, defaultAccess: null } });

        expect(findUnsetItem().hint).toBe('Uses Always ask');
      });
    });
  });

  describe('accessType prop validator', () => {
    const { validator } = AiToolRuleAccessControl.props.accessType;

    it('accepts webAccess, localAccess, and backgroundAccess', () => {
      expect(validator('webAccess')).toBe(true);
      expect(validator('localAccess')).toBe(true);
      expect(validator('backgroundAccess')).toBe(true);
    });

    it('rejects an unknown access type', () => {
      expect(validator('runnerAccess')).toBe(false);
      expect(validator('somethingElse')).toBe(false);
    });
  });

  describe('backgroundAccess (Runner)', () => {
    const findItem = (value) => findItems().find((item) => item.value === value);

    it('never offers the ASK option', () => {
      createComponent({
        toolRule: { ...mockToolRule, backgroundAccess: 'ALLOW' },
        accessType: 'backgroundAccess',
      });

      const values = findItems()
        .map((item) => item.value)
        .filter((value) => value !== 'UNSET');

      expect(values).toEqual(['ALLOW', 'DENY']);
      expect(values).not.toContain('ASK');
      expect(findListItem('ASK').exists()).toBe(false);
    });

    it('offers only ALLOW and DENY, both enabled, when no floor is set', () => {
      createComponent({
        toolRule: { ...mockToolRule, backgroundAccess: 'ALLOW' },
        accessType: 'backgroundAccess',
        floorValue: null,
      });

      expect(findItem('ALLOW').disabled).toBeUndefined();
      expect(findItem('DENY').disabled).toBeUndefined();
    });

    it('renders the value statically when a DENY floor collapses to a single option', () => {
      createComponent({
        toolRule: { ...unsetToolRule, backgroundAccess: 'DENY' },
        accessType: 'backgroundAccess',
        projectFullPath: 'gitlab-org/my-project',
        floorValue: 'DENY',
      });

      expect(findListbox().exists()).toBe(false);
      expect(findStatic().exists()).toBe(true);
      expect(findStaticText().text()).toBe('Always deny');
    });

    it('calls the mutation with only backgroundAccess when changed at the group level', async () => {
      createComponent({
        toolRule: { ...mockToolRule, backgroundAccess: 'ALLOW' },
        accessType: 'backgroundAccess',
      });

      selectOption('DENY');
      await waitForPromises();

      expect(mutationHandler).toHaveBeenCalledWith({
        input: {
          fullPath: 'gitlab-org',
          toolId: 'list_issues',
          backgroundAccess: 'DENY',
        },
      });
    });
  });
});
