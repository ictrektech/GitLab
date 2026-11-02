import { GlSegmentedControl } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnforcementModeControl from 'ee/security_orchestration/components/policy_editor/dependency_firewall/components/enforcement_mode_control.vue';

describe('EnforcementModeControl', () => {
  let wrapper;

  const createWrapper = (propsData = {}) => {
    wrapper = shallowMountExtended(EnforcementModeControl, {
      propsData: { enforcementType: 'warn', ...propsData },
    });
  };

  const findSegmentedControl = () => wrapper.findComponent(GlSegmentedControl);

  it('passes the current enforcement type to the segmented control', () => {
    createWrapper({ enforcementType: 'enforced' });

    expect(findSegmentedControl().props('value')).toBe('enforced');
  });

  it('emits change with the new value', () => {
    createWrapper();

    findSegmentedControl().vm.$emit('input', 'enforced');

    expect(wrapper.emitted('change')).toEqual([['enforced']]);
  });

  it('shows the description matching the current enforcement type', () => {
    createWrapper({ enforcementType: 'warn' });

    expect(wrapper.text()).toContain('Applies to every rule in this policy.');
  });

  it('disables every option when disabled is true', () => {
    createWrapper({ disabled: true });

    const options = findSegmentedControl().props('options');

    expect(options.every((option) => option.disabled)).toBe(true);
  });
});
