import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import FoundationalFlowPicker from 'ee/ai/settings/components/foundational_flow_picker.vue';
import FoundationalFlowSelector from 'ee/ai/settings/components/foundational_flow_selector.vue';
import DuoCodeReviewConsentMessage from 'ee/ai/settings/components/duo_code_review_consent_message.vue';

jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal');

const CODE_REVIEW_REFERENCE = 'code_review/v1';
const OTHER_FLOW_REFERENCE = 'bug_triage/v1';

describe('FoundationalFlowPicker', () => {
  let wrapper;

  const createComponent = ({ props = {}, provide = {} } = {}) => {
    wrapper = shallowMountExtended(FoundationalFlowPicker, {
      propsData: { value: [], ...props },
      provide: {
        duoEnterpriseActive: true,
        initialCodeReviewFlowConsentGiven: false,
        availableFoundationalFlows: [
          { reference: CODE_REVIEW_REFERENCE, name: 'Code Review' },
          { reference: OTHER_FLOW_REFERENCE, name: 'Bug Triage' },
        ],
        ...provide,
      },
      stubs: { FoundationalFlowSelector },
    });
  };

  const findSelector = () => wrapper.findComponent(FoundationalFlowSelector);
  const findConsentMessage = () => wrapper.findComponent(DuoCodeReviewConsentMessage);
  const selectFlows = async (flowIds) => {
    findSelector().vm.$emit('input', flowIds);
    await waitForPromises();
  };

  afterEach(() => {
    confirmAction.mockReset();
  });

  it('passes the selection and disabled state to the selector', () => {
    createComponent({ props: { value: [OTHER_FLOW_REFERENCE], disabled: true } });

    expect(findSelector().props()).toMatchObject({ value: [OTHER_FLOW_REFERENCE], disabled: true });
  });

  it('points the checkboxes at the note they are described by', () => {
    createComponent({ props: { selectAll: true, describedBy: 'flows-note' } });

    expect(
      wrapper.findByTestId('foundational-flow-select-all').attributes('aria-describedby'),
    ).toBe('flows-note');
    expect(findSelector().props('describedBy')).toBe('flows-note');
  });

  it('renders the consent message only after the Code Review flow', () => {
    createComponent({ props: { value: [CODE_REVIEW_REFERENCE] } });

    expect(wrapper.findAllComponents(DuoCodeReviewConsentMessage)).toHaveLength(1);
    expect(findConsentMessage().props()).toMatchObject({
      codeReviewFlowSelected: true,
      codeReviewFlowConsentGiven: false,
    });
  });

  it('emits the new selection without a dialog for other flows', async () => {
    createComponent();

    await selectFlows([OTHER_FLOW_REFERENCE]);

    expect(confirmAction).not.toHaveBeenCalled();
    expect(wrapper.emitted('input')).toEqual([[[OTHER_FLOW_REFERENCE]]]);
  });

  describe('when the Code Review flow is added and consent is required', () => {
    beforeEach(() => {
      createComponent();
    });

    it('asks for consent and drops the change when the user cancels', async () => {
      confirmAction.mockResolvedValue(false);

      await selectFlows([CODE_REVIEW_REFERENCE]);

      expect(confirmAction).toHaveBeenCalledTimes(1);
      expect(wrapper.emitted('input')).toBeUndefined();
      expect(wrapper.emitted('consent-given')).toBeUndefined();
    });

    it('records consent and emits the selection when the user confirms', async () => {
      confirmAction.mockResolvedValue(true);

      await selectFlows([CODE_REVIEW_REFERENCE]);
      await wrapper.setProps({ value: [CODE_REVIEW_REFERENCE] });

      expect(wrapper.emitted('input')).toEqual([[[CODE_REVIEW_REFERENCE]]]);
      expect(wrapper.emitted('consent-given')).toHaveLength(1);
      expect(findConsentMessage().props('codeReviewFlowConsentGiven')).toBe(true);
    });
  });

  it('does not ask again once consent was already given', async () => {
    createComponent({ provide: { initialCodeReviewFlowConsentGiven: true } });

    await selectFlows([CODE_REVIEW_REFERENCE]);

    expect(confirmAction).not.toHaveBeenCalled();
    expect(wrapper.emitted('input')).toEqual([[[CODE_REVIEW_REFERENCE]]]);
  });

  it('does not ask when the namespace has no Duo Enterprise add-on', async () => {
    createComponent({ provide: { duoEnterpriseActive: false } });

    await selectFlows([CODE_REVIEW_REFERENCE]);

    expect(confirmAction).not.toHaveBeenCalled();
    expect(wrapper.emitted('input')).toEqual([[[CODE_REVIEW_REFERENCE]]]);
  });

  describe('with select all', () => {
    const findSelectAll = () => wrapper.findComponentByTestId('foundational-flow-select-all');
    const toggleSelectAll = async (checked) => {
      findSelectAll().vm.$emit('change', checked);
      await waitForPromises();
    };

    it('is hidden by default', () => {
      createComponent();

      expect(findSelectAll().exists()).toBe(false);
    });

    it('is hidden when no flow is available', () => {
      createComponent({ props: { selectAll: true }, provide: { availableFoundationalFlows: [] } });

      expect(findSelectAll().exists()).toBe(false);
    });

    it.each`
      value                                            | checked  | indeterminate
      ${[]}                                            | ${false} | ${false}
      ${[OTHER_FLOW_REFERENCE]}                        | ${false} | ${true}
      ${[CODE_REVIEW_REFERENCE, OTHER_FLOW_REFERENCE]} | ${true}  | ${false}
    `(
      'is checked=$checked and indeterminate=$indeterminate for $value',
      ({ value, checked, indeterminate }) => {
        createComponent({ props: { selectAll: true, value } });

        expect(findSelectAll().props()).toMatchObject({ checked, indeterminate });
      },
    );

    it('passes the disabled state on', () => {
      createComponent({ props: { selectAll: true, disabled: true } });

      expect(findSelectAll().props('disabled')).toBe(true);
    });

    it('selects every flow after the Code Review consent is given', async () => {
      confirmAction.mockResolvedValue(true);
      createComponent({ props: { selectAll: true } });

      await toggleSelectAll(true);

      expect(confirmAction).toHaveBeenCalledTimes(1);
      expect(wrapper.emitted('consent-given')).toHaveLength(1);
      expect(wrapper.emitted('input')).toEqual([[[CODE_REVIEW_REFERENCE, OTHER_FLOW_REFERENCE]]]);
    });

    it('selects every other flow when the Code Review consent is declined', async () => {
      confirmAction.mockResolvedValue(false);
      createComponent({ props: { selectAll: true } });

      await toggleSelectAll(true);

      expect(wrapper.emitted('consent-given')).toBeUndefined();
      expect(wrapper.emitted('input')).toEqual([[[OTHER_FLOW_REFERENCE]]]);
    });

    it('selects every flow without a dialog once consent exists', async () => {
      createComponent({
        props: { selectAll: true },
        provide: { initialCodeReviewFlowConsentGiven: true },
      });

      await toggleSelectAll(true);

      expect(confirmAction).not.toHaveBeenCalled();
      expect(wrapper.emitted('input')).toEqual([[[CODE_REVIEW_REFERENCE, OTHER_FLOW_REFERENCE]]]);
    });

    it('deselects every flow without a dialog', async () => {
      createComponent({
        props: { selectAll: true, value: [CODE_REVIEW_REFERENCE, OTHER_FLOW_REFERENCE] },
      });

      await toggleSelectAll(false);

      expect(confirmAction).not.toHaveBeenCalled();
      expect(wrapper.emitted('input')).toEqual([[[]]]);
    });
  });
});
