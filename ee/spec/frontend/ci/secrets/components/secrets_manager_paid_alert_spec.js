import { GlAlert, GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SecretsManagerPaidAlert from 'ee/ci/secrets/components/secrets_manager_paid_alert.vue';

describe('SecretsManagerPaidAlert', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(SecretsManagerPaidAlert, { propsData: props });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findLink = () => wrapper.findComponent(GlLink);

  it.each`
    enabled  | text
    ${true}  | ${'GitLab Secrets Manager consumes GitLab Credits when storing new secrets or fetching secrets.'}
    ${false} | ${'Project and group members can only view details or delete existing secrets. When enabled, GitLab Secrets Manager consumes GitLab Credits.'}
  `(
    'renders a non-dismissible info alert with the credits docs link when enabled is $enabled',
    ({ enabled, text }) => {
      createComponent({ enabled });

      expect(findAlert().props()).toMatchObject({ variant: 'info', dismissible: false });
      expect(findAlert().text()).toContain(text);
      expect(findLink().text()).toBe('How does GitLab Secrets Manager use GitLab Credits?');
      expect(findLink().attributes('href')).toBe('/help/ci/secrets/secrets_manager/credit_usage');
    },
  );
});
