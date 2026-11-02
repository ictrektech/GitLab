import { within } from '@testing-library/vue';
import setWindowLocation from 'helpers/set_window_location_helper';
import { initAdminJobsApp } from '~/ci/admin/jobs_table/index';
import {
  findButtonByText,
  getText,
  registerBootstrappedApp,
  screen,
  waitAndClick,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import getAllJobsVariants from './fixture_variants/get_all_jobs';
import getAllJobsCountVariants from './fixture_variants/get_all_jobs_count';
import getCancelableJobsCountVariants from './fixture_variants/get_cancelable_jobs_count';

const ADMIN_JOBS_PATH = '/admin/jobs';

// Mirrors Admin::JobsHelper#admin_jobs_app_data; ee/spec/requests/admin/jobs_controller_spec.rb
// asserts the page exposes these same attributes.
const DATASET = {
  jobStatuses: JSON.stringify({
    success: 'SUCCESS',
    failed: 'FAILED',
    canceled: 'CANCELED',
    pending: 'PENDING',
    running: 'RUNNING',
  }),
  url: `${ADMIN_JOBS_PATH}/cancel_all`,
  canUpdateAllJobs: 'true',
};

export function mountAdminJobsApp() {
  // Filtering pushes its params into the URL, so start every mount from a clean one.
  setWindowLocation(ADMIN_JOBS_PATH);

  const el = document.createElement('div');
  el.id = 'admin-jobs-app';
  Object.assign(el.dataset, DATASET);
  document.body.appendChild(el);

  return registerBootstrappedApp(initAdminJobsApp());
}

export function useEmptyJobs() {
  setQueryVariant(getAllJobsVariants).empty();
  setQueryVariant(getAllJobsCountVariants).empty();
  setQueryVariant(getCancelableJobsCountVariants).empty();
}

export const findAllTab = () => screen.queryByTestId('jobs-all-tab');

export const findFinishedTab = () => screen.queryByTestId('jobs-finished-tab');

export const findJobsTable = () => screen.queryByTestId('jobs-table');

export const findJobRows = () => screen.queryAllByTestId('jobs-table-row');

export const findJobNames = () =>
  findJobRows().map((row) => getText(within(row).getByTestId('job-name')));

export const findJobStatuses = () => {
  const table = findJobsTable();

  return table ? within(table).queryAllByTestId('ci-icon-text').map(getText) : [];
};

export const findEmptyState = () => screen.queryByTestId('jobs-empty-state');

export const findCancelAllJobsButton = () => findButtonByText('Cancel all jobs');

// BModal adds `show` only once the modal is actually open and interactive.
export const findCancelJobsModal = () => document.querySelector('#cancel-jobs-modal.show');

// The idle search input; focusing it swaps in the active token segment input.
const findFilteredSearchInput = () => screen.queryByTestId('filtered-search-term-input');

const findActiveFilteredSearchInput = () =>
  screen.queryByTestId('filtered-search-token-segment-input');

// The clickable element is the dropdown item button; its `li` wrapper swallows clicks.
const findSuggestion = (text) =>
  [...document.querySelectorAll('.gl-filtered-search-suggestion-list .dropdown-item')].find(
    (element) => getText(element) === text,
  ) ?? null;

// GlFilteredSearch commits a suggestion on mousedown so the segment input keeps focus;
// a bare click() is ignored.
const selectSuggestion = async (text) => {
  const suggestion = await waitForElement(() => findSuggestion(text));

  ['mousedown', 'mouseup', 'click'].forEach((type) => {
    suggestion.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true }));
  });

  return suggestion;
};

const findSearchButton = () => screen.queryByTestId('search-button');

// Drives the filtered search the way a user does: activate it, pick the Status token, pick the
// status value from its suggestions, and submit.
export const filterByStatus = async (statusText) => {
  const idleInput = await waitForElement(findFilteredSearchInput);
  idleInput.focus();
  idleInput.click();
  await waitForElement(findActiveFilteredSearchInput);

  await selectSuggestion('Status');
  await selectSuggestion(statusText);
  await waitAndClick(findSearchButton);
};

export const expectJobRowsCount = (count) =>
  waitForAssertion(() => {
    expect(findJobRows()).toHaveLength(count);
  });
