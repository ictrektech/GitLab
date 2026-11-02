import triggersFixture from 'test_fixtures/graphql/ci/pipeline_triggers/integration/triggers.json';
import initTriggersList from '~/ci_settings_pipeline_triggers';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import {
  findButtonByText,
  getText,
  registerBootstrappedApp,
  screen,
  waitAndClick,
  waitAndSetValue,
  within,
} from 'ee_jest/integration/helpers/test_helpers';

const PAGE_TESTID = 'pipeline-triggers-page';
const EDIT_MODAL_ID = 'edit-trigger-modal';

// `TriggersList` masks every token with 47 asterisks until values are revealed.
export const MASKED_TOKEN = '*'.repeat(47);

// The rows as the app sees them once `index.js` has parsed and camelCased `data-triggers`.
export const triggers = convertObjectPropsToCamelCase(triggersFixture, { deep: true });

// The signed-in maintainer's own token is exposed in full, another maintainer's token is
// shortened, and a guest owner's trigger cannot access the project.
export const ownedTrigger = triggers.find((trigger) => trigger.hasTokenExposed);
export const notOwnedTrigger = triggers.find(
  (trigger) => !trigger.hasTokenExposed && trigger.canAccessProject,
);
export const invalidTrigger = triggers.find((trigger) => !trigger.canAccessProject);

export function mountTriggersList() {
  // The reveal button is rendered by HAML in the CRUD header, outside the Vue root, and the
  // list binds to it through `document`, so the previous page must go before a new one mounts.
  screen.queryByTestId(PAGE_TESTID)?.remove();

  const page = document.createElement('div');
  page.dataset.testid = PAGE_TESTID;
  page.innerHTML = `
    <button type="button" data-testid="reveal-hide-values-button">Reveal values</button>
    <div id="js-ci-pipeline-triggers-list"></div>
  `;
  page.querySelector('#js-ci-pipeline-triggers-list').dataset.triggers =
    JSON.stringify(triggersFixture);
  document.body.appendChild(page);

  return registerBootstrappedApp(initTriggersList());
}

export const findRevealButton = () => screen.queryByTestId('reveal-hide-values-button');

export const findRows = () => Array.from(document.querySelectorAll('.triggers-list tbody tr'));

export const findTokenCell = (row) => row.querySelectorAll('td')[0];

const findDescriptionCell = (row) => row.querySelectorAll('td')[1];

export const findRowByDescription = (description) =>
  findRows().find((row) => getText(findDescriptionCell(row)) === description) ?? null;

export const findClipboardButton = (row) => within(row).queryByTestId('clipboard-btn');

export const findInvalidBadge = (row) => row.querySelector('.gl-badge');

export const findOwnerLink = (row) => row.querySelector('.trigger-owner');

export const findEditButton = (row) => within(row).queryByTestId('edit-btn');

export const findRevokeButton = (row) => within(row).queryByTestId('trigger_revoke_button');

// BModal adds `show` only once the modal is open and its buttons are interactive.
export const findEditModal = () => document.querySelector(`#${EDIT_MODAL_ID}.show`);

const findDescriptionInput = () =>
  findEditModal()?.querySelector('#edit_trigger_description') ?? null;

const findUpdateButton = () => {
  const modal = findEditModal();

  return modal ? findButtonByText('Update', modal) : null;
};

export const editTriggerDescription = async (row, description) => {
  await waitAndClick(() => findEditButton(row));
  await waitAndSetValue(findDescriptionInput, description);
  await waitAndClick(findUpdateButton);
};
