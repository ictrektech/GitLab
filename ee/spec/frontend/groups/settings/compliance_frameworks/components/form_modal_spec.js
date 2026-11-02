import { shallowMount } from '@vue/test-utils';
import { GlModal } from '@gitlab/ui';

import FormModal from 'ee/groups/settings/compliance_frameworks/components/form_modal.vue';
import CreateForm from 'ee/groups/settings/compliance_frameworks/components/create_form.vue';

jest.mock('~/lib/utils/url_utility');

describe('FormModal', () => {
  let wrapper;

  const findModal = () => wrapper.findComponent(GlModal);
  const findCreateForm = () => wrapper.findComponent(CreateForm);

  function createComponent(props = {}, mountFn = shallowMount) {
    return mountFn(FormModal, {
      propsData: {
        ...props,
      },
    });
  }

  describe('create', () => {
    beforeEach(() => {
      wrapper = createComponent();
    });

    it('sets the modal title', () => {
      expect(findModal().props('title')).toBe('New compliance framework');
    });

    it('emits the change event on success', async () => {
      expect(wrapper.emitted('change')).toBe(undefined);

      const MESSAGE = 'success-message';
      await findCreateForm().vm.$emit('success', { message: MESSAGE });

      expect(wrapper.emitted('change').at(-1)).toStrictEqual([MESSAGE]);
    });
  });
});
