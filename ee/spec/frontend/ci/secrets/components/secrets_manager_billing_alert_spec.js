import { GlAlert, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SecretsManagerBillingAlert from 'ee/ci/secrets/components/secrets_manager_billing_alert.vue';

describe('SecretsManagerBillingAlert', () => {
  let wrapper;

  beforeEach(() => {
    wrapper = shallowMountExtended(SecretsManagerBillingAlert, { stubs: { GlSprintf } });
  });

  it('renders the open beta warning with a credits docs link', () => {
    const alert = wrapper.findComponent(GlAlert);

    expect(alert.props()).toMatchObject({
      variant: 'warning',
      dismissible: false,
      title: 'Charges may be incurred at the end of open beta',
    });
    expect(wrapper.findComponent(GlLink).attributes('href')).toBe(
      '/help/subscriptions/gitlab_credits',
    );
  });
});
