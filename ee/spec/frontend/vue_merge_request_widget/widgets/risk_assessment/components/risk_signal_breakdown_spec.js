import { GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RiskSignalBreakdown from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_signal_breakdown.vue';

describe('RiskSignalBreakdown', () => {
  let wrapper;

  const contributions = [
    {
      signal: 'touches_auth',
      label: 'Authentication or authorization logic',
      contribution: 14,
      detail: 'touches_auth: true (lib/auth.rb:44)',
    },
    { signal: 'diff_shape.churn', label: 'Size of change', contribution: 2, detail: null },
  ];

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(RiskSignalBreakdown, {
      propsData: { contributions, ...props },
    });
  };

  const findBreakdown = () => wrapper.findByTestId('risk-signal-breakdown');
  const findRows = () => findBreakdown().findAll('li');
  const findImpacts = () => wrapper.findAllByTestId('risk-signal-impact');

  describe('default', () => {
    beforeEach(() => createComponent());

    it('renders a heading', () => {
      expect(wrapper.find('h5').text()).toBe('What affected the risk score');
    });

    it('lists every contribution with its label and evidence', () => {
      expect(findRows()).toHaveLength(2);
      expect(findRows().at(0).text()).toContain('Authentication or authorization logic');
      expect(findRows().at(0).text()).toContain('touches_auth: true (lib/auth.rb:44)');
      expect(findRows().at(1).text()).toContain('Size of change');
    });

    it('does not show points, because there are no user facing weights', () => {
      expect(wrapper.text()).not.toContain('14');
    });
  });

  describe('impact tag', () => {
    it.each`
      contribution | label               | icon            | textClass           | iconClass
      ${14}        | ${'Major increase'} | ${'trend-up'}   | ${'gl-font-bold'}   | ${'gl-text-danger'}
      ${10}        | ${'Major increase'} | ${'trend-up'}   | ${'gl-font-bold'}   | ${'gl-text-danger'}
      ${9.99}      | ${'Increase'}       | ${'trend-up'}   | ${null}             | ${'gl-text-danger'}
      ${4}         | ${'Increase'}       | ${'trend-up'}   | ${null}             | ${'gl-text-danger'}
      ${3.99}      | ${'Minor increase'} | ${'trend-up'}   | ${'gl-text-subtle'} | ${'gl-text-danger'}
      ${-10}       | ${'Major decrease'} | ${'trend-down'} | ${'gl-font-bold'}   | ${'gl-text-success'}
      ${-9.99}     | ${'Decrease'}       | ${'trend-down'} | ${null}             | ${'gl-text-success'}
      ${-4}        | ${'Decrease'}       | ${'trend-down'} | ${null}             | ${'gl-text-success'}
      ${-3.99}     | ${'Minor decrease'} | ${'trend-down'} | ${'gl-text-subtle'} | ${'gl-text-success'}
      ${0}         | ${'No change'}      | ${'dash'}       | ${'gl-text-subtle'} | ${'gl-text-subtle'}
    `(
      'shows "$label" with $icon for a contribution of $contribution',
      ({ contribution, label, icon, textClass, iconClass }) => {
        createComponent({
          contributions: [{ signal: 'coverage', label: 'Coverage', contribution, detail: null }],
        });

        const impact = findImpacts().at(0);
        const impactIcon = impact.findComponent(GlIcon);

        expect(impact.text()).toBe(label);
        if (textClass) expect(impact.classes()).toContain(textClass);
        expect(impactIcon.props('name')).toBe(icon);
        expect(impactIcon.classes()).toContain(iconClass);
        expect(impact.element.lastElementChild).toBe(impactIcon.element);
      },
    );

    it('keeps direction color off the text', () => {
      createComponent({
        contributions: [{ signal: 'coverage', label: 'Coverage', contribution: 14, detail: null }],
      });

      expect(findImpacts().at(0).classes()).not.toContain('gl-text-danger');
    });

    it('only bolds major rows', () => {
      createComponent({
        contributions: [{ signal: 'coverage', label: 'Coverage', contribution: 5, detail: null }],
      });

      expect(findImpacts().at(0).classes()).not.toContain('gl-font-bold');
    });
  });

  describe('when a row has no contribution', () => {
    beforeEach(() =>
      createComponent({
        contributions: [{ signal: 'coverage', label: 'Coverage', detail: null }],
      }),
    );

    it('still lists the row', () => {
      expect(findRows()).toHaveLength(1);
      expect(findRows().at(0).text()).toContain('Coverage');
    });

    it('shows no impact tag rather than claiming "No change"', () => {
      expect(findImpacts()).toHaveLength(0);
      expect(wrapper.text()).not.toContain('No change');
    });
  });

  describe('when the server sent no label for a signal', () => {
    beforeEach(() =>
      createComponent({
        contributions: [{ signal: 'coverage', label: null, contribution: 5, detail: null }],
      }),
    );

    it('falls back to the signal name', () => {
      expect(findRows().at(0).text()).toContain('coverage');
    });
  });

  describe('when the mitigation cap row is present', () => {
    beforeEach(() =>
      createComponent({
        contributions: [
          ...contributions,
          { signal: 'mitigation_cap', label: null, contribution: 2, detail: null },
        ],
      }),
    );

    it('leaves it out', () => {
      expect(findRows()).toHaveLength(2);
      expect(wrapper.text()).not.toContain('mitigation_cap');
    });
  });
});
