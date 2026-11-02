import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import LicenseRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/license_rule_builder.vue';
import RuleMultiSelect from 'ee/security_orchestration/components/policy_editor/rule_multi_select.vue';
import NameListTextarea from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/name_list_textarea.vue';

const PARSED_SOFTWARE_LICENSES = [
  { value: 'MIT', text: 'MIT' },
  { value: 'GPL-3.0', text: 'GPL-3.0' },
];

describe('LicenseRuleBuilder', () => {
  let wrapper;

  const createWrapper = (initRule = { type: 'license', denied: [{ name: 'MIT' }] }) => {
    wrapper = shallowMountExtended(LicenseRuleBuilder, {
      propsData: { initRule },
      provide: { parsedSoftwareLicenses: PARSED_SOFTWARE_LICENSES },
    });
  };

  const findNamesInput = () => wrapper.findComponent(RuleMultiSelect);
  const findExceptionsInput = () => wrapper.findComponent(NameListTextarea);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findMissingLicenses = () => wrapper.findByTestId('missing-licenses');

  it('shows the deny blurb and no allow-list alert for a deny rule', () => {
    createWrapper();
    expect(wrapper.findByTestId('license-blurb').text()).toBe(
      'Deny packages based on the selected software license.',
    );
    expect(findAlert().exists()).toBe(false);
  });

  it('shows the allow blurb and the allow-list alert for a legacy allow rule', () => {
    createWrapper({ type: 'license', allowed: [{ name: 'MIT' }] });
    expect(wrapper.findByTestId('license-blurb').text()).toBe(
      'Allow packages based on the selected software license.',
    );
    expect(findAlert().text()).toContain(
      'This rule is an allow list. New license rules can only deny',
    );
  });

  it('passes the current names and the known license catalogue to the multi-select', () => {
    createWrapper();
    expect(findNamesInput().props('value')).toEqual(['MIT']);
    expect(findNamesInput().props('items')).toEqual({ MIT: 'MIT', 'GPL-3.0': 'GPL-3.0' });
    expect(findNamesInput().props('searchable')).toBe(true);
  });

  it('lets the multi-select panel grow to fit long license names', () => {
    createWrapper();
    expect(findNamesInput().props('fluidWidth')).toBe(true);
  });

  it('labels the multi-select toggle via the field label, not a raw aria-labelledby', () => {
    createWrapper();
    expect(findNamesInput().attributes('toggle-aria-labelled-by')).toBe('license-names-label');
  });

  describe('missing-licenses validation', () => {
    it('stays quiet while the card is unchecked, even with no licenses selected', () => {
      createWrapper({ type: 'license', denied: [] });
      expect(findMissingLicenses().exists()).toBe(false);
    });

    it('stays quiet once checked if licenses are selected', () => {
      wrapper = shallowMountExtended(LicenseRuleBuilder, {
        propsData: { initRule: { type: 'license', denied: [{ name: 'MIT' }] }, isActive: true },
        provide: { parsedSoftwareLicenses: PARSED_SOFTWARE_LICENSES },
      });
      expect(findMissingLicenses().exists()).toBe(false);
    });

    it('asks for a license once checked with none selected', () => {
      wrapper = shallowMountExtended(LicenseRuleBuilder, {
        propsData: { initRule: { type: 'license', denied: [] }, isActive: true },
        provide: { parsedSoftwareLicenses: PARSED_SOFTWARE_LICENSES },
      });
      expect(findMissingLicenses().text()).toBe('Select at least one license to finish this rule.');
    });
  });

  describe('when names change', () => {
    beforeEach(() => {
      createWrapper();
      findNamesInput().vm.$emit('input', ['MIT', 'GPL-3.0']);
    });

    it('emits changed with an updated denied list', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'license',
        denied: [{ name: 'MIT' }, { name: 'GPL-3.0' }],
      });
    });
  });

  describe('when the exceptions input changes', () => {
    beforeEach(() => {
      createWrapper();
      findExceptionsInput().vm.$emit('input', ['pkg:npm/lodash@4.17.21']);
    });

    it('emits changed with exceptions', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'license',
        denied: [{ name: 'MIT' }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }],
      });
    });
  });

  describe('when the rule has a stray id exception (e.g. hand-edited YAML)', () => {
    beforeEach(() => {
      createWrapper({
        type: 'license',
        denied: [{ name: 'MIT' }],
        exceptions: [{ id: 'CVE-2021-23337' }],
      });
      findExceptionsInput().vm.$emit('input', ['pkg:npm/lodash@4.17.21']);
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
        type: 'license',
        denied: [{ name: 'MIT' }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }],
      });
      findExceptionsInput().vm.$emit('input', []);
    });

    it('emits changed with the exceptions key removed', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'license',
        denied: [{ name: 'MIT' }],
      });
      expect(wrapper.emitted('changed')[0][0]).not.toHaveProperty('exceptions');
    });
  });
});
