import { GlFormInput } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import RepositorySizeLimitRegistrationCta from '~/groups_projects/components/repository_size_limit_registration_cta.vue';

describe('RepositorySizeLimitRegistrationCta', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = mountExtended(RepositorySizeLimitRegistrationCta, {
      propsData: {
        fieldNamePrefix: 'project',
        ...props,
      },
    });
  };

  const findInput = () => wrapper.findComponent(GlFormInput);
  const findServicePingSettingsLink = () => wrapper.findByTestId('service-ping-settings-link');
  const findDocsLink = () => wrapper.findByTestId('registration-features-docs-link');

  it.each`
    fieldNamePrefix | expectedName                                 | expectedId
    ${'project'}    | ${'project[disabled_repository_size_limit]'} | ${'project_disabled_repository_size_limit'}
    ${'group'}      | ${'group[disabled_repository_size_limit]'}   | ${'group_disabled_repository_size_limit'}
  `(
    'renders a disabled number input named $expectedName for $fieldNamePrefix',
    ({ fieldNamePrefix, expectedName, expectedId }) => {
      createComponent({ fieldNamePrefix });

      const input = findInput();
      expect(input.attributes('name')).toBe(expectedName);
      expect(input.attributes('id')).toBe(expectedId);
      expect(input.attributes('type')).toBe('number');
      expect(input.attributes('disabled')).toBeDefined();
    },
  );

  it('renders the registration features message', () => {
    createComponent();

    expect(wrapper.text()).toContain('Want to use this feature for free?');
  });

  it('links to the Registration Features Program docs', () => {
    createComponent();

    expect(findDocsLink().text()).toBe('Registration Features Program');
    expect(findDocsLink().attributes('href')).toBe(
      '/help/administration/settings/usage_statistics#registration-features-program',
    );
  });

  it('does not render the Service Ping settings link without a path', () => {
    createComponent();

    expect(findServicePingSettingsLink().exists()).toBe(false);
  });

  it('renders the Service Ping settings link when a path is given', () => {
    createComponent({
      servicePingSettingsPath: '/admin/application_settings/metrics_and_profiling',
    });

    expect(findServicePingSettingsLink().text()).toBe(
      'Enable Service Ping and register for this feature.',
    );
    expect(findServicePingSettingsLink().attributes('href')).toBe(
      '/admin/application_settings/metrics_and_profiling',
    );
  });
});
