import { shallowMount } from '@vue/test-utils';
import MetaApp from 'ee/usage_quotas/usage_billing/components/meta_app.vue';
import FreeTierTrialApp from 'ee/usage_quotas/usage_billing/components/free_tier_trial_app.vue';

describe('UsageBillingMetaApp', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMount(MetaApp);
  };

  const findFreeTierTrialApp = () => wrapper.findComponent(FreeTierTrialApp);

  it('renders FreeTierTrialApp', () => {
    createComponent();

    expect(findFreeTierTrialApp().exists()).toBe(true);
  });
});
