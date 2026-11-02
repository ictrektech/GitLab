import { mount } from '@vue/test-utils';
import Vue, { nextTick } from 'vue';
// eslint-disable-next-line no-restricted-imports
import Vuex from 'vuex';
import RuleInput from 'ee/approvals/components/rules/rule_input.vue';
import { createStoreOptions } from 'ee/approvals/stores';
import MREditModule from 'ee/approvals/stores/modules/mr_edit';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import showToast from '~/vue_shared/plugins/global_toast';

jest.mock('~/alert');
jest.mock('~/vue_shared/plugins/global_toast');

Vue.use(Vuex);

describe('Rule Input', () => {
  let wrapper;
  let store;

  const createComponent = (props = {}) => {
    wrapper = mount(RuleInput, {
      propsData: {
        rule: {
          approvalsRequired: 9,
          id: 5,
        },
        ...props,
      },
      store: new Vuex.Store(store),
    });
  };

  const findInput = () => wrapper.find('input');

  beforeEach(() => {
    store = createStoreOptions({ approvals: MREditModule() });
    store.state.settings.canEdit = true;

    store.modules.approvals.actions = {
      putRule: jest.fn(),
    };
  });

  afterEach(() => {
    store = null;
  });

  it('has value equal to the approvalsRequired', () => {
    createComponent();
    expect(Number(findInput().element.value)).toBe(9);
  });

  it('is disabled when settings cannot edit', () => {
    store.state.settings.canEdit = false;
    createComponent();

    expect(findInput().attributes().disabled).toBeDefined();
  });

  it('is not disabled when settings can edit', () => {
    createComponent();

    expect(findInput().attributes().disabled).not.toBeDefined();
  });

  it('has min equal to the minApprovalsRequired', () => {
    createComponent({
      rule: {
        minApprovalsRequired: 4,
      },
    });

    expect(Number(findInput().attributes().min)).toBe(4);
  });

  it('defaults min approvals required input to 0', () => {
    createComponent();
    delete wrapper.props().rule.approvalsRequired;
    expect(Number(findInput().attributes('min'))).toEqual(0);
  });

  it('dispatches putRule on change', async () => {
    const action = store.modules.approvals.actions.putRule;
    createComponent();
    findInput().setValue(wrapper.props().rule.approvalsRequired + 1);

    jest.runAllTimers();

    await nextTick();
    expect(action).toHaveBeenCalledWith(expect.anything(), { approvalsRequired: 10, id: 5 });
  });

  describe('save feedback', () => {
    const changeValue = async () => {
      findInput().setValue(wrapper.props().rule.approvalsRequired + 1);
      jest.runAllTimers();
      await waitForPromises();
    };

    it('does not show feedback on the MR edit form', async () => {
      store.modules.approvals.actions.putRule.mockResolvedValue();
      createComponent();
      await changeValue();

      expect(showToast).not.toHaveBeenCalled();
      expect(createAlert).not.toHaveBeenCalled();
    });

    describe('when the change is saved immediately', () => {
      it('shows a toast when the save succeeds', async () => {
        store.modules.approvals.actions.putRule.mockResolvedValue();
        createComponent({ isMrEdit: false });
        await changeValue();

        expect(showToast).toHaveBeenCalledWith('Required approvals updated.');
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('shows an alert when the save fails', async () => {
        const error = new Error('Request failed');
        store.modules.approvals.actions.putRule.mockRejectedValue(error);
        createComponent({ isMrEdit: false });
        await changeValue();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'An error occurred while updating the required approvals.',
          captureError: true,
          error,
        });
        expect(showToast).not.toHaveBeenCalled();
      });
    });
  });

  describe('on Branch rule details page', () => {
    it('is disabled when can edit settings is false', () => {
      store.state.settings.canEdit = false;
      createComponent({ isBranchRulesEdit: true });

      expect(findInput().attributes().disabled).toBeDefined();
    });

    it('is not disabled when can edit settings is true', () => {
      createComponent({ isBranchRulesEdit: true });

      expect(findInput().attributes().disabled).not.toBeDefined();
    });
  });
});
