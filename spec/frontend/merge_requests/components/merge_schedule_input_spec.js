import { shallowMount } from '@vue/test-utils';
import { GlCollapsibleListbox, GlFormInput } from '@gitlab/ui';
import MergeScheduleInput from '~/merge_requests/components/merge_schedule_input.vue';

let wrapper;

function createComponent(propsData = {}) {
  wrapper = shallowMount(MergeScheduleInput, {
    propsData: { paramKey: 'merge_request', ...propsData },
  });
}

const findInputs = () => wrapper.findAllComponents(GlFormInput);
const findHiddenInputs = () => wrapper.findAll('input[type="hidden"]');
const findHiddenMergeAfterInput = () =>
  wrapper.find('input[type="hidden"][name="merge_request[merge_after]"]');
const findHiddenMergeBeforeInput = () =>
  wrapper.find('input[type="hidden"][name="merge_request[merge_before]"]');
const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);

describe('Merge schedule input component', () => {
  describe('ANYTIME mode', () => {
    beforeEach(() => {
      createComponent({ mergeAfter: undefined, mergeBefore: undefined });
    });

    it('shows no datetime inputs', () => {
      expect(findInputs()).toHaveLength(0);
    });

    it('renders both hidden inputs with empty values', () => {
      expect(findHiddenInputs()).toHaveLength(2);
      expect([undefined, '']).toContain(findHiddenMergeAfterInput().attributes('value'));
      expect([undefined, '']).toContain(findHiddenMergeBeforeInput().attributes('value'));
    });

    it('selects ANYTIME in the listbox', () => {
      expect(findListbox().props('selected')).toBe('anytime');
    });
  });

  describe('AFTER mode', () => {
    beforeEach(() => {
      createComponent({ mergeAfter: '2024-10-27T20:40', mergeBefore: undefined });
    });

    it('shows one datetime input for merge_after', () => {
      expect(findInputs()).toHaveLength(1);
    });

    it('sets the merge_after hidden input value', () => {
      expect(findHiddenMergeAfterInput().attributes('value')).toBe('2024-10-27T20:40:00.000Z');
    });

    it('leaves the merge_before hidden input empty', () => {
      expect([undefined, '']).toContain(findHiddenMergeBeforeInput().attributes('value'));
    });

    it('selects AFTER in the listbox', () => {
      expect(findListbox().props('selected')).toBe('after');
    });
  });

  describe('BETWEEN mode', () => {
    beforeEach(() => {
      createComponent({
        mergeAfter: '2024-10-27T20:40',
        mergeBefore: '2024-10-28T08:00',
      });
    });

    it('shows two datetime inputs', () => {
      expect(findInputs()).toHaveLength(2);
    });

    it('sets the merge_after hidden input value', () => {
      expect(findHiddenMergeAfterInput().attributes('value')).toBe('2024-10-27T20:40:00.000Z');
    });

    it('sets the merge_before hidden input value', () => {
      expect(findHiddenMergeBeforeInput().attributes('value')).toBe('2024-10-28T08:00:00.000Z');
    });

    it('selects BETWEEN in the listbox', () => {
      expect(findListbox().props('selected')).toBe('between');
    });
  });

  describe('hidden inputs', () => {
    it('always renders exactly two hidden inputs', () => {
      createComponent();
      expect(findHiddenInputs()).toHaveLength(2);
    });

    it('uses the paramKey prop to name the hidden inputs', () => {
      createComponent({ paramKey: 'my_mr' });
      expect(wrapper.find('input[name="my_mr[merge_after]"]').exists()).toBe(true);
      expect(wrapper.find('input[name="my_mr[merge_before]"]').exists()).toBe(true);
    });
  });
});
