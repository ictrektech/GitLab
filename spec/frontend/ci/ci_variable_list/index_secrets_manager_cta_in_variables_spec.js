import initCiVariableList from '~/ci/ci_variable_list';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';

jest.mock('~/lib/utils/vue3compat/init_vue_app', () => ({
  initVueApp: jest.fn(),
}));

describe('ci_variable_list Secrets Manager CTA wiring', () => {
  const containerId = 'js-ci-variables';
  const secretsManagerCtaInVariables = {
    secrets_manager_available: false,
    can_start_trial: true,
    secrets_path: '/groups/group/-/secrets',
    start_trial_path: '/groups/group/-/settings/secure',
  };

  const createApp = (dataset = {}) => {
    const el = document.createElement('div');
    el.id = containerId;
    Object.assign(el.dataset, {
      isGroup: 'true',
      secretsManagerCtaInVariables: JSON.stringify(secretsManagerCtaInVariables),
      ...dataset,
    });
    document.body.appendChild(el);

    initCiVariableList(containerId);

    return initVueApp.mock.calls[0][0].provide;
  };

  beforeEach(() => {
    initVueApp.mockClear();
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('camelCases the CTA payload so the component can read it', () => {
    expect(createApp().secretsManagerCtaInVariables).toEqual({
      secretsManagerAvailable: false,
      canStartTrial: true,
      secretsPath: '/groups/group/-/secrets',
      startTrialPath: '/groups/group/-/settings/secure',
    });
  });

  it('provides null when the payload is absent', () => {
    expect(createApp({ secretsManagerCtaInVariables: '' }).secretsManagerCtaInVariables).toBeNull();
  });
});
