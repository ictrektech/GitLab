import { GlIcon, GlToken } from '@gitlab/ui';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import GoalToken from 'ee/ai/duo_agentic_chat/components/prompt_composer/goal_token.vue';

describe('GoalToken', () => {
  let wrapper;

  const createComponent = ({ mountFn = shallowMountExtended, propsData = {} } = {}) => {
    wrapper = mountFn(GoalToken, { propsData });
  };

  const findToken = () => wrapper.findComponent(GlToken);

  it('reads as the goal it stands in for', () => {
    createComponent({ mountFn: mountExtended });

    expect(wrapper.text()).toBe('Goal');
    expect(wrapper.findComponent(GlIcon).props('name')).toBe('work-item-objective');
  });

  // The close button cannot inherit the token's own text, so it says what removing it
  // does rather than repeating the label.
  it('labels the close button with what it removes', () => {
    createComponent();

    expect(findToken().props('removeLabel')).toBe('Remove goal');
  });

  // Leaving goal mode belongs to whoever owns the draft, so this only reports the click.
  it('emits remove when dismissed', () => {
    createComponent();

    findToken().vm.$emit('close');

    expect(wrapper.emitted('remove')).toEqual([[]]);
  });

  it('emits nothing until dismissed', () => {
    createComponent();

    expect(wrapper.emitted('remove')).toBeUndefined();
  });

  describe('view only', () => {
    it('is dismissable by default', () => {
      createComponent({ mountFn: mountExtended });

      expect(wrapper.findByRole('button', { name: 'Remove goal' }).exists()).toBe(true);
    });

    it('drops the close button', () => {
      createComponent({ mountFn: mountExtended, propsData: { viewOnly: true } });

      expect(wrapper.findByRole('button', { name: 'Remove goal' }).exists()).toBe(false);
      expect(wrapper.text()).toBe('Goal');
    });
  });
});
