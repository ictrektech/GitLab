import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import StaleSeverityStatusAlert from 'ee/security_orchestration/components/policy_editor/scan_result/rule/scanners/stale_severity_status_alert.vue';

describe('StaleSeverityStatusAlert', () => {
  let wrapper;

  const createComponent = (scanner) => {
    wrapper = shallowMountExtended(StaleSeverityStatusAlert, { propsData: { scanner } });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);

  it.each([
    ['severity_levels', { severity_levels: ['critical'] }],
    ['severity_levels (empty)', { severity_levels: [] }],
    ['vulnerability_states', { vulnerability_states: ['new_needs_triage'] }],
  ])('shows the alert when the scanner has %s', (_, values) => {
    createComponent({ type: 'dependency_scanning', ...values });

    expect(findAlert().props('variant')).toBe('warning');
  });

  it('does not show the alert when the scanner has no scanner-level values', () => {
    createComponent({ type: 'dependency_scanning', vulnerabilities_allowed: 0 });

    expect(findAlert().exists()).toBe(false);
  });

  it('removes only the scanner-level severity and status on primary action', () => {
    createComponent({
      type: 'dependency_scanning',
      vulnerabilities_allowed: 2,
      severity_levels: ['critical', 'high'],
      vulnerability_states: ['new_needs_triage'],
    });

    findAlert().vm.$emit('primary-action');

    expect(wrapper.emitted('changed')).toEqual([
      [{ type: 'dependency_scanning', vulnerabilities_allowed: 2 }],
    ]);
  });
});
