import { GlFormInput, GlFormSelect } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { parseBoolean } from '@gitlab/frontend-utils';
import FlexibleRollout from '~/feature_flags/components/strategies/flexible_rollout.vue';
import ParameterFormGroup from '~/feature_flags/components/strategies/parameter_form_group.vue';
import { flexibleRolloutStrategy } from '../../mock_data';

const DEFAULT_PROPS = {
  strategy: flexibleRolloutStrategy,
};

describe('feature_flags/components/strategies/flexible_rollout.vue', () => {
  let wrapper;

  const factory = (props = {}) =>
    shallowMount(FlexibleRollout, { propsData: { ...DEFAULT_PROPS, ...props } });

  const findPercentageFormGroup = () =>
    wrapper
      .find('[data-testid="strategy-flexible-rollout-percentage"]')
      .findComponent(ParameterFormGroup);
  const findPercentageInput = () => findPercentageFormGroup().findComponent(GlFormInput);
  const findStickinessFormGroup = () =>
    wrapper
      .find('[data-testid="strategy-flexible-rollout-stickiness"]')
      .findComponent(ParameterFormGroup);
  const findStickinessSelect = () => findStickinessFormGroup().findComponent(GlFormSelect);
  const findGroupIdFormGroup = () =>
    wrapper
      .find('[data-testid="strategy-flexible-rollout-group-id"]')
      .findComponent(ParameterFormGroup);
  const findGroupIdInput = () => findGroupIdFormGroup().findComponent(GlFormInput);

  describe('with a new strategy', () => {
    beforeEach(() => {
      wrapper = factory({ strategy: { parameters: {} } });
    });

    it('displays and emits the default group ID', () => {
      expect(findGroupIdInput().props('value')).toBe('default');

      findPercentageInput().vm.$emit('input', '25');

      expect(wrapper.emitted('change')).toEqual([
        [{ parameters: { rollout: '25', stickiness: 'default', groupId: 'default' } }],
      ]);
    });

    it('emits the default group ID when the stickiness changes', () => {
      findStickinessSelect().vm.$emit('change', 'userId');

      expect(wrapper.emitted('change')).toEqual([
        [{ parameters: { rollout: '100', stickiness: 'userId', groupId: 'default' } }],
      ]);
    });
  });

  describe.each(['payments', 'a', 'a'.repeat(32)])('with group ID %s', (groupId) => {
    beforeEach(() => {
      wrapper = factory({
        strategy: {
          ...flexibleRolloutStrategy,
          parameters: { ...flexibleRolloutStrategy.parameters, groupId },
        },
      });
    });

    it('displays the current group ID without errors', () => {
      expect(findGroupIdInput().props('value')).toBe(groupId);
      expect(findGroupIdInput().props('state')).toBe(true);
      expect(findGroupIdInput().props('width')).toBe('md');
      expect(parseBoolean(findGroupIdFormGroup().attributes('state'))).toBe(true);
      expect(findGroupIdFormGroup().attributes('description')).toBe(
        'Strategies with the same group ID and percentage select the same users.',
      );
    });

    it('preserves the group ID when the percentage changes', () => {
      findPercentageInput().vm.$emit('input', '75');

      expect(wrapper.emitted('change')).toEqual([
        [{ parameters: { ...flexibleRolloutStrategy.parameters, groupId, rollout: '75' } }],
      ]);
    });

    it('preserves the group ID when the stickiness changes', () => {
      findStickinessSelect().vm.$emit('change', 'sessionId');

      expect(wrapper.emitted('change')).toEqual([
        [
          {
            parameters: { ...flexibleRolloutStrategy.parameters, groupId, stickiness: 'sessionId' },
          },
        ],
      ]);
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
      expect(findGroupIdFormGroup().attributes('invalid-feedback')).toBe(
        'Group ID must contain 1 to 32 lowercase letters (a-z).',
      );
      expect(findGroupIdFormGroup().attributes('description')).toBe('');
    });
  });

  describe('with valid percentage', () => {
    beforeEach(() => {
      wrapper = factory();
    });

    it('displays the current percentage value', () => {
      expect(findPercentageInput().attributes('value')).toBe(
        flexibleRolloutStrategy.parameters.rollout,
      );
    });

    it('displays the current stickiness value', () => {
      expect(findStickinessSelect().attributes('value')).toBe(
        flexibleRolloutStrategy.parameters.stickiness,
      );
    });

    it('emits a change when the percentage value changes', async () => {
      findPercentageInput().vm.$emit('input', '75');

      await nextTick();
      expect(wrapper.emitted('change')).toEqual([
        [
          {
            parameters: {
              rollout: '75',
              groupId: 'default',
              stickiness: flexibleRolloutStrategy.parameters.stickiness,
            },
          },
        ],
      ]);
    });

    it('emits a change when the stickiness value changes', async () => {
      findStickinessSelect().vm.$emit('change', 'userId');
      await nextTick();
      expect(wrapper.emitted('change')).toEqual([
        [
          {
            parameters: {
              rollout: flexibleRolloutStrategy.parameters.rollout,
              groupId: 'default',
              stickiness: 'userId',
            },
          },
        ],
      ]);
    });

    it('does not show errors', () => {
      expect(parseBoolean(findPercentageFormGroup().attributes('state'))).toBe(true);
    });

    it('emits a change when the group ID changes', async () => {
      findGroupIdInput().vm.$emit('input', 'checkout');

      expect(wrapper.emitted('change')).toEqual([
        [{ parameters: { ...flexibleRolloutStrategy.parameters, groupId: 'checkout' } }],
      ]);

      await wrapper.setProps({ strategy: wrapper.emitted('change')[0][0] });
      findPercentageInput().vm.$emit('input', '75');

      expect(wrapper.emitted('change')[1]).toEqual([
        {
          parameters: { ...flexibleRolloutStrategy.parameters, groupId: 'checkout', rollout: '75' },
        },
      ]);
    });
  });

  describe('with percentage that is out of range', () => {
    beforeEach(() => {
      wrapper = factory({ strategy: { parameters: { rollout: '101' } } });
    });

    it('shows errors', () => {
      expect(findPercentageFormGroup().attributes('state')).toBeUndefined();
    });
  });

  describe('with percentage that is not an integer number', () => {
    beforeEach(() => {
      wrapper = factory({ strategy: { parameters: { rollout: '3.14' } } });
    });

    it('shows errors', () => {
      expect(findPercentageFormGroup().attributes('state')).toBeUndefined();
    });
  });
});
