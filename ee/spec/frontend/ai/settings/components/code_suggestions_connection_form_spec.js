import { GlFormRadio, GlFormRadioGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CodeSuggestionsConnectionForm from 'ee/ai/settings/components/code_suggestions_connection_form.vue';

describe('CodeSuggestionsConnectionForm', () => {
  let wrapper;

  const createComponent = ({ provide = {} } = {}) => {
    wrapper = shallowMountExtended(CodeSuggestionsConnectionForm, {
      provide: {
        disabledDirectConnectionMethod: false,
        codeCompletionsSelfHosted: false,
        ...provide,
      },
    });
  };

  const findFormRadioButtons = () => wrapper.findAllComponents(GlFormRadio);
  const findFormRadioGroup = () => wrapper.findComponent(GlFormRadioGroup);
  const findSelfHostedNote = () => wrapper.findByTestId('self-hosted-connection-note');

  beforeEach(() => {
    createComponent();
  });

  it('renders radio buttons', () => {
    expect(findFormRadioButtons()).toHaveLength(2);
  });

  it('sets correct values for radio buttons', () => {
    expect(findFormRadioButtons().at(0).attributes('value')).toBeUndefined();
    expect(findFormRadioButtons().at(1).attributes('value')).toBe('true');
  });

  it('does not render the self-hosted note', () => {
    expect(findSelfHostedNote().exists()).toBe(false);
  });

  it('emits change event to parent when radio option is updated', () => {
    findFormRadioGroup().vm.$emit('change', true);
    expect(wrapper.emitted('change')).toStrictEqual([[true]]);
  });

  describe('when code completions use a self-hosted model', () => {
    beforeEach(() => {
      createComponent({ provide: { codeCompletionsSelfHosted: true } });
    });

    it('renders the self-hosted note instead of the radio buttons', () => {
      expect(findSelfHostedNote().text()).toBe(
        'Direct connections are not available because code completion uses a self-hosted model. Requests are sent through the GitLab instance.',
      );
      expect(findFormRadioGroup().exists()).toBe(false);
    });
  });
});
