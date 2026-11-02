import { GlCollapsibleListbox, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RiskSeverityRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/risk_severity_rule_builder.vue';
import NameListTextarea from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/name_list_textarea.vue';

describe('RiskSeverityRuleBuilder', () => {
  let wrapper;

  const createWrapper = (initRule = { type: 'risk_severity', denied: [] }, props = {}) => {
    wrapper = shallowMountExtended(RiskSeverityRuleBuilder, {
      propsData: { initRule, ...props },
      // Rendered for real so the threshold input and severity select, passed via its
      // named scoped slots, actually appear in the output.
      stubs: { GlSprintf },
    });
  };

  const findRows = () => wrapper.findAllComponents(GlCollapsibleListbox);
  const findRemoveButtons = () => wrapper.findAllComponentsByTestId('remove-severity-row');
  const findAddRowButtons = () => wrapper.findAllComponentsByTestId('add-severity-row');
  const findThreshold = (index = 0) =>
    wrapper.findComponentByTestId(`risk-severity-threshold-${index}`);
  const findMissingSeverity = () => wrapper.findByTestId('missing-severity');
  const findSeveritySelect = (index) =>
    wrapper.findComponentByTestId(`risk-severity-select-${index}`);

  it('renders the deny blurb', () => {
    createWrapper();

    expect(wrapper.findByTestId('risk-severity-blurb').text()).toBe(
      'Deny packages that exceed a specified number of vulnerabilities.',
    );
  });

  describe('when denied is empty', () => {
    it('renders no rows and shows the add button', () => {
      createWrapper();

      expect(findRows()).toHaveLength(0);
      expect(findAddRowButtons()).toHaveLength(1);
    });

    it('asks for a severity once checked, even with no rows at all', () => {
      createWrapper({ type: 'risk_severity', denied: [] }, { isActive: true });

      expect(findMissingSeverity().text()).toBe('Select a severity to finish this rule.');
    });

    it('adds a row with no severity chosen yet on click', () => {
      createWrapper();
      findAddRowButtons().at(0).vm.$emit('click');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ threshold: 0 }],
      });
    });
  });

  describe('when a severity is already added', () => {
    beforeEach(() => {
      createWrapper({ type: 'risk_severity', denied: [{ severity: 'high', threshold: 5 }] });
    });

    it('renders the row as an inline sentence with the threshold and severity', () => {
      expect(wrapper.findComponentByTestId('threshold-field').props('label')).toBe(
        'Block packages that have',
      );
      expect(wrapper.text()).toContain('more than');
      expect(wrapper.text()).not.toContain('or more');
      expect(wrapper.text()).toContain('vulnerabilities');
      expect(findThreshold().props('value')).toBe(5);
      expect(findSeveritySelect(0).props('toggleText')).toBe('High');
      expect(findSeveritySelect(0).props('selected')).toBe('high');
    });

    it('gives each row its own accessible label instead of a shared static one', () => {
      expect(findSeveritySelect(0).props('toggleAriaLabelledBy')).toBe(
        'risk-severity-select-label-0',
      );
      expect(findThreshold().attributes('aria-label')).toBe('Vulnerability count threshold (High)');
    });

    it("offers every severity in that row's own selector, including its current one", () => {
      const values = findSeveritySelect(0)
        .props('items')
        .map(({ value }) => value);
      expect(values).toEqual(['critical', 'high', 'medium', 'low']);
    });

    it('updates the threshold, coercing to a non-negative integer', () => {
      findThreshold().vm.$emit('input', '-3');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'high', threshold: 0 }],
      });
    });

    it('lazily reformats the displayed value on blur so an invalid entry is visibly corrected', () => {
      expect(findThreshold().props('lazyFormatter')).toBe(true);
      expect(findThreshold().props('formatter')('-3')).toBe('0');
    });

    it('changes the severity via the row selector, keeping the threshold', () => {
      findSeveritySelect(0).vm.$emit('select', 'critical');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'critical', threshold: 5 }],
      });
    });

    it('removes the row', () => {
      findRemoveButtons().at(0).vm.$emit('click');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [],
      });
    });

    it('shows a single add button since fewer than four severities are used', () => {
      expect(findAddRowButtons()).toHaveLength(1);
    });
  });

  describe('when all four severities are added', () => {
    beforeEach(() => {
      createWrapper({
        type: 'risk_severity',
        denied: [
          { severity: 'critical', threshold: 0 },
          { severity: 'high', threshold: 0 },
          { severity: 'medium', threshold: 0 },
          { severity: 'low', threshold: 0 },
        ],
      });
    });

    it('does not render any add button', () => {
      expect(findAddRowButtons()).toHaveLength(0);
    });

    it("excludes other rows' severities from each row's own selector", () => {
      const values = findSeveritySelect(1)
        .props('items')
        .map(({ value }) => value);
      expect(values).toEqual(['high']);
    });
  });

  describe('when the rule has a stray allowed key', () => {
    beforeEach(() => {
      createWrapper({
        type: 'risk_severity',
        allowed: [],
        denied: [{ severity: 'critical', threshold: 10 }],
      });
    });

    it('still reads the denied list rather than treating allowed as authoritative', () => {
      expect(findRemoveButtons()).toHaveLength(1);
      expect(findThreshold().props('value')).toBe(10);
    });

    it('drops allowed when a severity row changes', () => {
      findThreshold().vm.$emit('input', '20');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'critical', threshold: 20 }],
      });
    });

    it('drops allowed when only the exceptions input changes', () => {
      wrapper.findComponent(NameListTextarea).vm.$emit('input', ['CVE-2021-23337']);

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'critical', threshold: 10 }],
        exceptions: [{ id: 'CVE-2021-23337' }],
      });
    });
  });

  describe('when a threshold input produces a non-numeric value', () => {
    it('falls back to the default threshold instead of emitting NaN', () => {
      createWrapper({ type: 'risk_severity', denied: [{ severity: 'high', threshold: 5 }] });
      findThreshold().vm.$emit('input', '.5');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'high', threshold: 0 }],
      });
    });
  });

  describe('when the same severity appears twice in the rule', () => {
    it('renders only one row', () => {
      createWrapper({
        type: 'risk_severity',
        denied: [
          { severity: 'high', threshold: 1 },
          { severity: 'high', threshold: 9 },
        ],
      });

      expect(findRemoveButtons()).toHaveLength(1);
    });
  });

  describe('when a row has no severity selected', () => {
    const unselected = { type: 'risk_severity', denied: [{ threshold: 0 }] };

    it('shows the placeholder rather than a severity', () => {
      createWrapper(unselected);

      expect(findSeveritySelect(0).props('toggleText')).toBe('Select');
    });

    it('offers every severity', () => {
      createWrapper(unselected);

      expect(findSeveritySelect(0).props('items')).toHaveLength(4);
    });

    it('does not offer to add another row, which would collapse into this one', () => {
      createWrapper(unselected);

      expect(findAddRowButtons()).toHaveLength(0);
    });

    it('stays quiet while the card is still unchecked', () => {
      createWrapper(unselected);

      expect(findMissingSeverity().exists()).toBe(false);
    });

    it('asks for a severity once the card is checked', () => {
      createWrapper(unselected, { isActive: true });

      expect(findMissingSeverity().text()).toBe('Select a severity to finish this rule.');
    });

    it('keeps the threshold when the severity is chosen', () => {
      createWrapper({ type: 'risk_severity', denied: [{ threshold: 7 }] });
      findSeveritySelect(0).vm.$emit('select', 'medium');

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [{ severity: 'medium', threshold: 7 }],
      });
    });
  });

  describe('when the exceptions input changes', () => {
    beforeEach(() => {
      createWrapper();
      wrapper.findComponent(NameListTextarea).vm.$emit('input', ['CVE-2021-23337']);
    });

    it('emits changed with exceptions', () => {
      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [],
        exceptions: [{ id: 'CVE-2021-23337' }],
      });
    });
  });

  describe('exception fields', () => {
    const findVulnerabilityExceptions = () =>
      wrapper.findComponentByTestId('vulnerability-exceptions');
    const findPackageExceptions = () => wrapper.findComponentByTestId('package-exceptions');

    it('splits existing exceptions across the two fields', () => {
      createWrapper({
        type: 'risk_severity',
        denied: [],
        exceptions: [{ id: 'CVE-2021-23337' }, { purl: 'pkg:npm/my-internal-lib' }],
      });

      expect(findVulnerabilityExceptions().props('items')).toEqual(['CVE-2021-23337']);
      expect(findPackageExceptions().props('items')).toEqual(['pkg:npm/my-internal-lib']);
    });

    it('keeps a half-typed package URL in the packages field', () => {
      createWrapper({ type: 'risk_severity', denied: [] });
      findPackageExceptions().vm.$emit('input', ['pk']);

      expect(wrapper.emitted('changed')[0][0].exceptions).toEqual([{ purl: 'pk' }]);
    });

    it('replaces rather than accumulates as the packages field is edited', () => {
      createWrapper({ type: 'risk_severity', denied: [], exceptions: [{ purl: 'pk' }] });
      findPackageExceptions().vm.$emit('input', ['pkg']);

      expect(wrapper.emitted('changed')[0][0].exceptions).toEqual([{ purl: 'pkg' }]);
    });

    it('clears the packages field without disturbing the vulnerabilities field', () => {
      createWrapper({
        type: 'risk_severity',
        denied: [],
        exceptions: [{ id: 'CVE-2021-23337' }, { purl: 'pkg:npm/my-internal-lib' }],
      });
      findPackageExceptions().vm.$emit('input', []);

      expect(wrapper.emitted('changed')[0][0].exceptions).toEqual([{ id: 'CVE-2021-23337' }]);
    });

    it('drops the exceptions key once both fields are empty', () => {
      createWrapper({
        type: 'risk_severity',
        denied: [],
        exceptions: [{ purl: 'pkg:npm/my-internal-lib' }],
      });
      findPackageExceptions().vm.$emit('input', []);

      expect(wrapper.emitted('changed')[0][0]).not.toHaveProperty('exceptions');
    });

    it('keeps the vulnerability exceptions when the package field changes', () => {
      createWrapper({
        type: 'risk_severity',
        denied: [],
        exceptions: [{ id: 'CVE-2021-23337' }],
      });

      findPackageExceptions().vm.$emit('input', ['pkg:npm/my-internal-lib']);

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'risk_severity',
        denied: [],
        exceptions: [{ id: 'CVE-2021-23337' }, { purl: 'pkg:npm/my-internal-lib' }],
      });
    });
  });
});
