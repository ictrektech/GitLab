import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RuleList from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/rule_list.vue';
import FixedRuleCard from 'ee/security_orchestration/components/policy_editor/dependency_firewall/components/fixed_rule_card.vue';

describe('RuleList', () => {
  let wrapper;

  const createWrapper = (
    rules = [],
    glFeatures = { dependencyFirewallAccess: true, dependencyFirewallPackageVersion: true },
  ) => {
    wrapper = shallowMountExtended(RuleList, { propsData: { rules }, provide: { glFeatures } });
  };

  const findAllCards = () => wrapper.findAllComponents(FixedRuleCard);
  const findCard = (type) => findAllCards().wrappers.find((card) => card.props('type') === type);
  const cardTypes = () => findAllCards().wrappers.map((card) => card.props('type'));

  it('renders malicious, risk_severity, license, and package_version cards in order', () => {
    createWrapper();

    expect(cardTypes()).toEqual(['malicious', 'risk_severity', 'license', 'package_version']);
  });

  describe('when dependencyFirewallAccess is disabled', () => {
    it('hides the package_version card even when dependencyFirewallPackageVersion is enabled', () => {
      createWrapper([], {
        dependencyFirewallAccess: false,
        dependencyFirewallPackageVersion: true,
      });

      expect(cardTypes()).toEqual(['malicious', 'risk_severity', 'license']);
    });

    it('keeps a package_version rule when another rule changes', () => {
      const packageVersionRule = { type: 'package_version', denied: [{ name: 'a', version: '1' }] };
      createWrapper([packageVersionRule], { dependencyFirewallAccess: false });

      findCard('license').vm.$emit('toggle', {
        checked: true,
        draftRule: { type: 'license', denied: [] },
      });

      expect(wrapper.emitted('changed')[0][0]).toEqual([
        packageVersionRule,
        { type: 'license', denied: [] },
      ]);
    });
  });

  describe('when dependencyFirewallPackageVersion is disabled', () => {
    it('hides the package_version card even with dependencyFirewallAccess enabled', () => {
      createWrapper([], {
        dependencyFirewallAccess: true,
        dependencyFirewallPackageVersion: false,
      });

      expect(cardTypes()).toEqual(['malicious', 'risk_severity', 'license']);
    });
  });

  it('labels the risk_severity card "Known vulnerabilities"', () => {
    createWrapper();

    expect(findCard('risk_severity').props('label')).toBe('Known vulnerabilities');
  });

  it('marks only malicious as recommended', () => {
    createWrapper([]);

    expect(findCard('malicious').props('recommended')).toBe(true);
    expect(findCard('risk_severity').props('recommended')).toBe(false);
    expect(findCard('license').props('recommended')).toBe(false);
    expect(findCard('package_version').props('recommended')).toBe(false);
  });

  it('labels the package_version card "Package versions"', () => {
    createWrapper([]);

    expect(findCard('package_version').props('label')).toBe('Package versions');
  });

  it('passes each rule from the array to its matching card', () => {
    const licenseRule = { type: 'license', denied: [{ name: 'GPL-3.0' }] };
    createWrapper([licenseRule]);

    expect(findCard('license').props('rule')).toEqual(licenseRule);
    expect(findCard('malicious').props('rule')).toBeNull();
  });

  it('adds a rule when a card is toggled on', () => {
    createWrapper([]);

    findCard('license').vm.$emit('toggle', {
      checked: true,
      draftRule: { type: 'license', denied: [] },
    });

    expect(wrapper.emitted('changed')[0][0]).toEqual([{ type: 'license', denied: [] }]);
  });

  it('removes a rule when its card is toggled off', () => {
    const licenseRule = { type: 'license', denied: [] };
    const maliciousRule = { type: 'malicious', denied: [{ is_malicious: true }] };
    createWrapper([licenseRule, maliciousRule]);

    findCard('license').vm.$emit('toggle', { checked: false });

    expect(wrapper.emitted('changed')[0][0]).toEqual([maliciousRule]);
  });

  it('updates a rule in place when its card emits changed', () => {
    createWrapper([{ type: 'license', denied: [] }]);

    findCard('license').vm.$emit('changed', { type: 'license', denied: [{ name: 'MIT' }] });

    expect(wrapper.emitted('changed')[0][0]).toEqual([
      { type: 'license', denied: [{ name: 'MIT' }] },
    ]);
  });
});
