import initVulnerabilities from 'ee/vulnerabilities/vulnerabilities_init';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';

jest.mock('~/lib/utils/vue3compat/init_vue_app', () => ({
  initVueApp: jest.fn(),
}));

// `secrets_manager_vulnerability_cta_data` serializes snake_case, so it has to be normalized
// here or the sidebar CTA silently never renders.
describe('vulnerabilities_init Secrets Manager CTA wiring', () => {
  const secretsManagerCta = {
    secrets_manager_available: true,
    can_start_trial: false,
    secrets_path: '/group/project/-/secrets',
    start_trial_path: '/groups/group/-/secrets',
  };

  const createApp = (dataset = {}) => {
    const el = document.createElement('div');
    Object.assign(el.dataset, {
      vulnerability: JSON.stringify({
        id: 1,
        title: 'Token detected',
        report_type: 'secret_detection',
      }),
      secretsManagerCta: JSON.stringify(secretsManagerCta),
      ...dataset,
    });

    initVulnerabilities(el);

    return initVueApp.mock.calls[0][0].provide;
  };

  beforeEach(() => {
    initVueApp.mockClear();
  });

  it('camelCases the CTA payload so the component can read it', () => {
    expect(createApp().secretsManagerCta).toEqual({
      secretsManagerAvailable: true,
      canStartTrial: false,
      secretsPath: '/group/project/-/secrets',
      startTrialPath: '/groups/group/-/secrets',
    });
  });

  it('provides an empty object when the payload is absent', () => {
    expect(createApp({ secretsManagerCta: '' }).secretsManagerCta).toEqual({});
  });
});
