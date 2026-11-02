import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import MaliciousRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/malicious_rule_builder.vue';
import NameListTextarea from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/name_list_textarea.vue';
import AllowDenyToggle from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/allow_deny_toggle.vue';

describe('MaliciousRuleBuilder', () => {
  let wrapper;

  const createWrapper = (initRule = { type: 'malicious', denied: [{ is_malicious: true }] }) => {
    wrapper = shallowMountExtended(MaliciousRuleBuilder, { propsData: { initRule } });
  };

  it('renders the explanatory blurb and no allow/deny toggle', () => {
    createWrapper();
    expect(wrapper.findByTestId('malicious-blurb').text()).toBe(
      'Deny packages flagged as malicious by GitLab.',
    );
    expect(wrapper.findComponent(AllowDenyToggle).exists()).toBe(false);
  });

  describe('when the exceptions input changes', () => {
    beforeEach(() => {
      createWrapper();
      wrapper.findComponent(NameListTextarea).vm.$emit('input', ['pkg:npm/lodash@4.17.21']);
    });

    it('emits changed with exceptions, preserving the fixed denied list', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'malicious',
        denied: [{ is_malicious: true }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }],
      });
    });
  });

  describe('when the rule has a stray id exception (e.g. hand-edited YAML)', () => {
    beforeEach(() => {
      createWrapper({
        type: 'malicious',
        denied: [{ is_malicious: true }],
        exceptions: [{ id: 'CVE-2021-23337' }],
      });
      wrapper.findComponent(NameListTextarea).vm.$emit('input', ['pkg:npm/lodash@4.17.21']);
    });

    it('keeps the id exception rather than relabelling it as a purl', () => {
      expect(wrapper.emitted('changed')[0][0].exceptions).toEqual([
        { id: 'CVE-2021-23337' },
        { purl: 'pkg:npm/lodash@4.17.21' },
      ]);
    });
  });

  describe('when exceptions are cleared', () => {
    beforeEach(() => {
      createWrapper({
        type: 'malicious',
        denied: [{ is_malicious: true }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }],
      });
      wrapper.findComponent(NameListTextarea).vm.$emit('input', []);
    });

    it('emits changed with the exceptions key removed', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'malicious',
        denied: [{ is_malicious: true }],
      });
      expect(wrapper.emitted('changed')[0][0]).not.toHaveProperty('exceptions');
    });
  });
});
