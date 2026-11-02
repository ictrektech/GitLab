import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ViewSessionButton from 'ee/ai/shared/widgets/view_session_button.vue';
import RiskFooter from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_footer.vue';
import RiskStaleWarning from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_stale_warning.vue';

describe('RiskFooter', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(RiskFooter, { propsData: props });
  };

  const findStaleWarning = () => wrapper.findComponent(RiskStaleWarning);
  const findSessionButton = () => wrapper.findComponent(ViewSessionButton);

  it('draws a line above itself unless it comes first', () => {
    createComponent();

    expect(wrapper.findByTestId('risk-footer').classes()).toEqual(
      expect.arrayContaining(['gl-border-t', 'first:gl-border-t-0']),
    );
  });

  describe('stale warning', () => {
    it('is not shown by default', () => {
      createComponent();

      expect(findStaleWarning().exists()).toBe(false);
    });

    it('is shown with the refresh state when the assessment is stale', () => {
      createComponent({ isStale: true, canRefresh: true, isSubmitting: true });

      expect(findStaleWarning().props()).toEqual({ canRefresh: true, isSubmitting: true });
    });

    it('passes refresh up', () => {
      createComponent({ isStale: true });

      findStaleWarning().vm.$emit('refresh');

      expect(wrapper.emitted('refresh')).toHaveLength(1);
    });
  });

  describe('view session button', () => {
    it('is not shown without a session', () => {
      createComponent();

      expect(findSessionButton().exists()).toBe(false);
    });

    it('is shown small, aligned to the right, for a session', () => {
      createComponent({ sessionId: 7 });

      expect(findSessionButton().props()).toMatchObject({ sessionId: 7, size: 'small' });
      expect(findSessionButton().classes()).toContain('gl-ml-auto');
    });
  });
});
