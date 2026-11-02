import { within } from '@testing-library/vue';
import initPipelineSubscriptionsApp from 'ee/ci/pipeline_subscriptions';
import {
  findButtonByText,
  getText,
  registerBootstrappedApp,
  screen,
  waitAndClick,
  waitAndSetValue,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';

// Mirrors the project the fixture generator records against.
export const PROJECT_PATH = 'frontend-fixtures/pipeline-subscriptions-project';

export function mountPipelineSubscriptionsApp() {
  const el = document.createElement('div');
  el.id = 'js-pipeline-subscriptions-app';
  el.dataset.projectPath = PROJECT_PATH;
  document.body.appendChild(el);

  return registerBootstrappedApp(initPipelineSubscriptionsApp());
}

export const findUpstreamSection = () => screen.queryByTestId('upstream-project-subscriptions');

export const findDownstreamSection = () => screen.queryByTestId('downstream-project-subscriptions');

export const findCount = (section) => within(section).queryByTestId('crud-count');

export const findSubscriptionRows = (section) =>
  within(section).queryAllByTestId('subscription-namespace');

const findAddNewButton = () => {
  const section = findUpstreamSection();

  return section ? findButtonByText('Add new', section) : null;
};

const findProjectPathInput = () => screen.queryByTestId('upstream-project-path-field');

const findSubscribeButton = () => screen.queryByTestId('subscribe-button');

export const findDeleteButton = () => screen.queryByTestId('delete-subscription-btn');

// BModal adds `show` only once the modal is open and its buttons are interactive.
const findDeleteModal = () => document.querySelector('#delete-subscription-modal.show');

const findDeleteModalConfirmButton = () => {
  const modal = findDeleteModal();

  return modal ? findButtonByText('OK', modal) : null;
};

export const subscribeTo = async (upstreamPath) => {
  await waitAndClick(findAddNewButton);
  await waitAndSetValue(findProjectPathInput, upstreamPath);
  await waitAndClick(findSubscribeButton);
};

export const deleteSubscription = async () => {
  await waitAndClick(findDeleteButton);
  await waitAndClick(findDeleteModalConfirmButton);
};

export const expectSectionCount = (findSection, count) =>
  waitForAssertion(() => {
    expect(getText(findCount(findSection()))).toBe(String(count));
  });

// `createAlert` renders into the `.flash-container` the harness provides.
export const findAlerts = () =>
  [...document.querySelectorAll('.flash-container .gl-alert')].map((alert) =>
    getText(alert.querySelector('.gl-alert-body')),
  );

export const expectAlert = (message) =>
  waitForAssertion(() => {
    expect(findAlerts()).toContain(message);
  });
