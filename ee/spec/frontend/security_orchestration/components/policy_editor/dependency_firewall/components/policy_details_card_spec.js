import { GlFormInput } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PolicyDetailsCard from 'ee/security_orchestration/components/policy_editor/dependency_firewall/components/policy_details_card.vue';
import EnforcementModeControl from 'ee/security_orchestration/components/policy_editor/dependency_firewall/components/enforcement_mode_control.vue';

describe('PolicyDetailsCard', () => {
  let wrapper;

  const createWrapper = (propsData = {}) => {
    wrapper = shallowMountExtended(PolicyDetailsCard, {
      propsData: {
        policy: { name: '', description: '' },
        enforcementType: 'warn',
        ...propsData,
      },
    });
  };

  const findNameInput = () => wrapper.findComponentByTestId('policy-name-text');
  const findDescriptionInput = () => wrapper.findComponentByTestId('policy-description-text');

  it('renders the current name and description', () => {
    createWrapper({ policy: { name: 'My policy', description: 'Blocks stuff' } });

    expect(findNameInput().props('value')).toBe('My policy');
    expect(findDescriptionInput().props('value')).toBe('Blocks stuff');
  });

  it('emits update-property when the name changes', () => {
    createWrapper();

    findNameInput().vm.$emit('input', 'New name');

    expect(wrapper.emitted('update-property')).toEqual([['name', 'New name']]);
  });

  it('emits update-property when the description changes', () => {
    createWrapper();

    findDescriptionInput().vm.$emit('input', 'New description');

    expect(wrapper.emitted('update-property')).toEqual([['description', 'New description']]);
  });

  it('does not show a validation error before the name field is touched', () => {
    createWrapper({ policy: { name: '', description: '' } });

    expect(findNameInput().props('state')).toBe(true);
  });

  it('shows a validation error once the name is cleared after being touched', async () => {
    createWrapper({ policy: { name: '', description: '' } });

    findNameInput().vm.$emit('input', '');
    await nextTick();

    expect(findNameInput().props('state')).toBe(false);
  });

  it('passes the enforcement type through to the enforcement mode control', () => {
    createWrapper({ enforcementType: 'enforced' });

    expect(wrapper.findComponent(EnforcementModeControl).props('enforcementType')).toBe('enforced');
  });

  it('emits change-enforcement-type when the enforcement mode control changes', () => {
    createWrapper();

    wrapper.findComponent(EnforcementModeControl).vm.$emit('change', 'enforced');

    expect(wrapper.emitted('change-enforcement-type')).toEqual([['enforced']]);
  });

  it('disables inputs when hasParsingError is true', () => {
    createWrapper({ hasParsingError: true });

    expect(findNameInput().props('disabled')).toBe(true);
    expect(findDescriptionInput().props('disabled')).toBe(true);
    expect(wrapper.findComponent(EnforcementModeControl).props('disabled')).toBe(true);
  });

  it('does not render Policy status radios', () => {
    createWrapper();

    expect(wrapper.findAllComponents(GlFormInput)).toHaveLength(2);
  });
});
