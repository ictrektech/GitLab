import { within } from '@testing-library/vue';
import setWindowLocation from 'helpers/set_window_location_helper';
import {
  getText,
  registerBootstrappedApp,
  screen,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';
import { initCdRoot } from 'ee/cd';

const ENVIRONMENTS_PATH = '/environments';

export function mountCdApp() {
  setWindowLocation(ENVIRONMENTS_PATH);

  const el = document.createElement('div');
  el.className = 'js-cd-root';
  el.dataset.baseRoute = '/';
  document.body.appendChild(el);

  return registerBootstrappedApp(initCdRoot());
}

export const findRegisterButton = () => screen.queryByTestId('register-environment-button');

export const findEnvironmentCards = () => screen.queryAllByTestId('environment-card');

export const findEnvironmentNames = () =>
  findEnvironmentCards().map((card) =>
    getText(card.querySelector('[data-testid="environment-card-link"]')),
  );

export const findEnvironmentCard = (name) =>
  findEnvironmentCards().find(
    (card) => getText(card.querySelector('[data-testid="environment-card-link"]')) === name,
  ) ?? null;

export const readCardField = (name, testId) => {
  const card = findEnvironmentCard(name);

  return card && getText(card.querySelector(`[data-testid="${testId}"]`));
};

export const findPanel = () => screen.queryByTestId('environment-panel');

export const withinPanel = () => {
  const panel = findPanel();

  return panel && within(panel);
};

export const expectListToShow = (names) =>
  waitForAssertion(() => {
    expect(findEnvironmentNames()).toEqual(names);
  });
