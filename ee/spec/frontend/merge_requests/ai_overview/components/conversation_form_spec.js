import { GlButton, GlFormTextarea } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ConversationForm from 'ee/merge_requests/ai_overview/components/conversation_form.vue';

describe('AI Overview conversation form', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = mountExtended(ConversationForm, {
      propsData: { placeholder: 'Reply…', submitText: 'Reply', ...props },
      attachTo: document.body,
    });
  };

  const findInput = () => wrapper.findComponent(GlFormTextarea);
  const findSubmit = () => wrapper.findComponentByTestId('conversation-form-submit');
  const findCancel = () => wrapper.findAllComponents(GlButton).at(1);

  const type = async (value) => {
    findInput().vm.$emit('input', value);
    await nextTick();
  };

  describe('by default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the placeholder and focuses the input', () => {
      expect(findInput().attributes('placeholder')).toBe('Reply…');
      expect(document.activeElement).toBe(findInput().element);
    });

    it('cannot be submitted while empty', () => {
      expect(findSubmit().props('disabled')).toBe(true);
    });

    it('emits the text on submit', async () => {
      await type('On it.');
      await wrapper.find('form').trigger('submit');

      expect(wrapper.emitted('submit')).toEqual([['On it.']]);
    });

    it('emits cancel', () => {
      findCancel().vm.$emit('click');

      expect(wrapper.emitted('cancel')).toHaveLength(1);
    });
  });

  it('shows the submit button as loading while posting', () => {
    createComponent({ loading: true });

    expect(findSubmit().props('loading')).toBe(true);
  });
});
