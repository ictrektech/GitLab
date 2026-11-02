import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RiskConfidenceNotice from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_confidence_notice.vue';

describe('RiskConfidenceNotice', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(RiskConfidenceNotice, {
      propsData: { ...props },
    });
  };

  const findNotice = () => wrapper.findByTestId('risk-low-confidence');
  const findItems = () => findNotice().findAll('li');

  it('lists each unmeasured input on its own line, under a heading that explains the why', () => {
    createComponent({ missingLabels: ['test coverage', 'commit authorship'] });

    expect(wrapper.find('h5').text()).toBe('What lowered confidence');
    expect(findNotice().text()).toContain('Could not be measured:');
    expect(findItems()).toHaveLength(2);
    expect(findItems().at(0).text()).toBe('test coverage');
    expect(findItems().at(1).text()).toBe('commit authorship');
  });

  it('drops the notice rather than showing an empty list', () => {
    createComponent({ missingLabels: [] });

    expect(findNotice().exists()).toBe(false);
  });
});
