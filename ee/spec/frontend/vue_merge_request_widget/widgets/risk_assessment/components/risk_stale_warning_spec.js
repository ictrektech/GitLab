import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RiskStaleWarning from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_stale_warning.vue';

describe('RiskStaleWarning', () => {
  let wrapper;

  const createComponent = ({ canRefresh = false, isSubmitting = false } = {}) => {
    wrapper = shallowMountExtended(RiskStaleWarning, {
      propsData: { canRefresh, isSubmitting },
    });
  };

  const findRefreshButton = () => wrapper.findComponent(GlButton);

  it('says the assessment reflects an earlier version of the changes', () => {
    createComponent();

    expect(wrapper.findByTestId('risk-stale-warning').text()).toBe(
      'New commits were pushed after this assessment and it reflects an earlier version of the changes.',
    );
  });

  describe('refresh button', () => {
    it('is not offered by default, so the warning stays a notice on its own', () => {
      createComponent();

      expect(findRefreshButton().exists()).toBe(false);
    });

    it('is offered when the caller allows a refresh', () => {
      createComponent({ canRefresh: true });

      expect(findRefreshButton().text()).toBe('Refresh');
    });

    it('stays as quiet as the View session button beside it', () => {
      createComponent({ canRefresh: true });

      expect(findRefreshButton().props()).toMatchObject({
        category: 'tertiary',
        icon: 'retry',
        size: 'small',
      });
    });

    it('emits refresh when clicked', () => {
      createComponent({ canRefresh: true });

      findRefreshButton().vm.$emit('click');

      expect(wrapper.emitted('refresh')).toHaveLength(1);
    });

    it('loads while the run is being started, and drops its icon for the spinner', () => {
      createComponent({ canRefresh: true, isSubmitting: true });

      expect(findRefreshButton().props()).toMatchObject({ loading: true, icon: '' });
    });
  });
});
