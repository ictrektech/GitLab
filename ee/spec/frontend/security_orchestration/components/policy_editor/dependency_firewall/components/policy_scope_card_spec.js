import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PolicyScopeCard from 'ee/security_orchestration/components/policy_editor/dependency_firewall/components/policy_scope_card.vue';
import ScopeSection from 'ee/security_orchestration/components/policy_editor/scope/scope_section.vue';
import DimDisableContainer from 'ee/security_orchestration/components/policy_editor/dim_disable_container.vue';

describe('PolicyScopeCard', () => {
  let wrapper;

  const policyScope = { projects: { excluding: [] } };

  const createWrapper = (propsData = {}) => {
    wrapper = shallowMountExtended(PolicyScopeCard, {
      propsData: { policyScope, ...propsData },
    });
  };

  it('passes the policy scope through to the scope section', () => {
    createWrapper();

    expect(wrapper.findComponent(ScopeSection).props('policyScope')).toEqual(policyScope);
  });

  it('emits update-property with policy_scope when the scope section changes', () => {
    createWrapper();

    const newScope = { projects: { excluding: [{ id: 1 }] } };
    wrapper.findComponent(ScopeSection).vm.$emit('changed', newScope);

    expect(wrapper.emitted('update-property')).toEqual([['policy_scope', newScope]]);
  });

  it('emits remove-property with policy_scope when the scope section emits remove', () => {
    createWrapper();

    wrapper.findComponent(ScopeSection).vm.$emit('remove');

    expect(wrapper.emitted('remove-property')).toEqual([['policy_scope']]);
  });

  it('disables the scope section when hasParsingError is true', () => {
    createWrapper({ hasParsingError: true });

    expect(wrapper.findComponent(DimDisableContainer).props('disabled')).toBe(true);
  });
});
