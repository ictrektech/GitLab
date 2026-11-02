import baseFixture from 'test_fixtures/graphql/home_panel/integration/get_project_by_path.query.graphql.json';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { initHomePanel } from '~/projects/home_panel';
import { registerBootstrappedApp, screen } from 'ee_jest/integration/helpers/test_helpers';

// Derived from the recorded fixture so the HAML-provided values (dataset) and the
// GraphQL-served ones agree, the way they do on the real page.
export const PROJECT_FULL_PATH = baseFixture.data.project.fullPath;
export const PROJECT_ID = getIdFromGraphQLId(baseFixture.data.project.id);
export const SIGN_IN_PATH = '/users/sign_in';

const PROJECT_BASE = `/${PROJECT_FULL_PATH}`;

// Mirrors the dataset app/views/projects/_home_panel.html.haml renders through
// ProjectsHelper#home_panel_data_attributes.
export function mountHomePanel(dataset = {}) {
  const el = document.createElement('div');
  el.id = 'js-home-panel';

  Object.assign(el.dataset, {
    canReadProject: 'true',
    isProjectEmpty: 'false',
    projectId: String(PROJECT_ID),
    projectFullPath: PROJECT_FULL_PATH,
    canRequestAccess: 'false',
    canWithdrawAccessRequest: 'false',
    requestAccessPath: `${PROJECT_BASE}/-/project_members/request_access`,
    withdrawAccessRequestPath: `${PROJECT_BASE}/-/project_members/leave`,
    dashboardPath: '/dashboard/projects',
    canForkProject: 'true',
    canReadCode: 'true',
    forksCount: '0',
    newForkUrl: `${PROJECT_BASE}/-/forks/new`,
    projectForksUrl: `${PROJECT_BASE}/-/forks`,
    emailsDisabled: 'false',
    notificationDropdownItems: JSON.stringify([
      'global',
      'watch',
      'participating',
      'mention',
      'disabled',
    ]),
    notificationHelpPagePath: '/help/user/profile/notifications.md',
    notificationLevel: 'global',
    signInPath: SIGN_IN_PATH,
    starCount: '0',
    starred: 'false',
    starrersPath: `${PROJECT_BASE}/-/starrers`,
    ...dataset,
  });

  document.body.appendChild(el);

  return registerBootstrappedApp(initHomePanel());
}

export const findStarButton = () => screen.queryByTestId('star-button');

export const findStarCount = () => screen.queryByTestId('star-count');

export const findNotificationsDropdown = () => screen.queryByTestId('notification-dropdown');

export const findActionsDropdown = () => screen.queryByTestId('projects-list-item-actions');

// GlCollapsibleListbox/GlDisclosureDropdown default toggles carry their own testid.
export const findDropdownToggle = (dropdown) =>
  dropdown && dropdown.querySelector('[data-testid="base-dropdown-toggle"]');
