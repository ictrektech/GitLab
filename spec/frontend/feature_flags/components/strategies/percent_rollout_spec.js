import { GlFormInput, GlFormGroup } from '@gitlab/ui';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { parseBoolean } from '@gitlab/frontend-utils';
import ParameterFormGroup from '~/feature_flags/components/strategies/parameter_form_group.vue';
import PercentRollout from '~/feature_flags/components/strategies/percent_rollout.vue';
import { percentRolloutStrategy } from '../../mock_data';

const DEFAULT_PROPS = {
  strategy: percentRolloutStrategy,
};

describe('~/feature_flags/components/strategies/percent_rollout.vue', () => {
  let wrapper;

  const factory = (props = {}) =>
    mount(PercentRollout, { propsData: { ...DEFAULT_PROPS, ...props } });

  const findPercentageFormGroup = () =>
    wrapper
      .find('[data-testid="strategy-percent-rollout-percentage"]')
      .findComponent(ParameterFormGroup);
  const findPercentageInput = () => findPercentageFormGroup().findComponent(GlFormInput);
  const findPercentageGlFormGroup = () => findPercentageFormGroup().findComponent(GlFormGroup);
  const findGroupIdFormGroup = () =>
    wrapper
      .find('[data-testid="strategy-percent-rollout-group-id"]')
      .findComponent(ParameterFormGroup);
  const findGroupIdInput = () => findGroupIdFormGroup().findComponent(GlFormInput);

  describe('with a new strategy', () => {
    beforeEach(() => {
      wrapper = factory({ strategy: { parameters: {} } });
    });

    it('displays and emits the default group ID', async () => {
      expect(findGroupIdInput().props('value')).toBe('default');

      await findPercentageInput().setValue('25');

      expect(wrapper.emitted('change')).toEqual([
        [{ parameters: { percentage: '25', groupId: 'default' } }],
      ]);
    });
  });

  describe.each(['payments', 'a', 'a'.repeat(32)])('with group ID %s', (groupId) => {
    beforeEach(() => {
      wrapper = factory({
        strategy: {
          ...percentRolloutStrategy,
          parameters: { ...percentRolloutStrategy.parameters, groupId },
        },
      });
    });

    it('displays the current group ID without errors', () => {
      expect(findGroupIdInput().props('value')).toBe(groupId);
      expect(findGroupIdInput().props('state')).toBe(true);
      expect(findGroupIdInput().props('width')).toBe('md');
      expect(parseBoolean(findGroupIdFormGroup().attributes('state'))).toBe(true);
      expect(findGroupIdFormGroup().text()).toContain(
        'Strategies with the same group ID and percentage select the same users.',
      );
    });

    it('preserves the group ID when the percentage changes', async () => {
      await findPercentageInput().setValue('75');

      expect(wrapper.emitted('change')).toEqual([[{ parameters: { percentage: '75', groupId } }]]);
    });
  });

  describe.each([undefined, null])('without a group ID (%s)', (groupId) => {
    beforeEach(() => {
      wrapper = factory({ strategy: { parameters: { groupId } } });
    });

    it('displays the default group ID', () => {
      expect(findGroupIdInput().props('value')).toBe('default');
    });
  });

  describe.each(['Bad-ID', '', 'a'.repeat(33)])('with invalid group ID %s', (groupId) => {
    beforeEach(() => {
      wrapper = factory({ strategy: { parameters: { groupId } } });
    });

    it('shows invalid feedback', () => {
      expect(findGroupIdInput().props('value')).toBe(groupId);
      expect(findGroupIdInput().props('state')).toBe(false);
      expect(findGroupIdInput().props('width')).toBe('md');
      expect(parseBoolean(findGroupIdFormGroup().attributes('state'))).toBe(false);
      expect(findGroupIdFormGroup().text()).toContain(
        'Group ID must contain 1 to 32 lowercase letters (a-z).',
      );
      expect(findGroupIdFormGroup().text()).not.toContain(
        'Strategies with the same group ID and percentage select the same users.',
      );
    });
  });

  describe('with valid percentage', () => {
    beforeEach(() => {
      wrapper = factory();
    });

    it('displays the current value', () => {
      expect(findPercentageInput().props('value')).toBe(
        percentRolloutStrategy.parameters.percentage,
      );
    });

    it('emits a change when the value changes', async () => {
      findPercentageInput().setValue('75');
      await nextTick();
      expect(wrapper.emitted('change')).toEqual([
        [{ parameters: { percentage: '75', groupId: 'default' } }],
      ]);
    });

    it('does not show errors', () => {
      expect(parseBoolean(findPercentageGlFormGroup().attributes('state'))).toBe(true);
    });

    it('emits a change when the group ID changes', async () => {
      await findGroupIdInput().setValue('checkout');

      expect(wrapper.emitted('change')).toEqual([
        [{ parameters: { ...percentRolloutStrategy.parameters, groupId: 'checkout' } }],
      ]);

      await wrapper.setProps({ strategy: wrapper.emitted('change')[0][0] });
      await findPercentageInput().setValue('75');

      expect(wrapper.emitted('change')[1]).toEqual([
        { parameters: { percentage: '75', groupId: 'checkout' } },
      ]);
    });
  });

  describe('with percentage that is out of range', () => {
    beforeEach(() => {
      wrapper = factory({ strategy: { parameters: { percentage: '101' } } });
    });

    it('shows errors', () => {
      expect(findPercentageFormGroup().attributes('state')).toBeUndefined();
    });
  });

  describe('with percentage that is not an integer number', () => {
    beforeEach(() => {
      wrapper = factory({ strategy: { parameters: { percentage: '3.14' } } });
    });

    it('shows errors', () => {
      expect(findPercentageFormGroup().attributes('state')).toBeUndefined();
    });
  });
});
