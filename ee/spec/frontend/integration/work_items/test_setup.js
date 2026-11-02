import waitForPromises from 'helpers/wait_for_promises';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import {
  assignRouter,
  fullMount,
  screen,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';

const FULL_PATH = 'gitlab-org/gitlab';

let createPage;

export const mountWorkItemCreatePage = async () => {
  window.gon = {
    ...window.gon,
    current_user_avatar_url:
      'https://www.gravatar.com/avatar/d3dd6864c3471bf0791642098d9758bdd63d307d3a31ec1c0f43e49ea97d2b68?s=80&d=identicon',
    current_username: 'user136',
    current_user_fullname: 'Sidney Jones263',
  };

  const router = assignRouter(createRouter, {
    fullPath: FULL_PATH,
    routerPath: 'work_items',
    routerLocation: '/work_items/work_items/new',
  });

  createPage = fullMount(WorkItemsRoot, {
    router,
    propsData: { rootPageFullPath: FULL_PATH },
    apolloProvider,
    provide: {
      isGroup: false,
      fullPath: FULL_PATH,
      groupPath: 'gitlab-org',
      workItemType: 'Issue',
      isSignedIn: true,
      initialSort: 'created_desc',
    },
  });

  await waitForAssertion(() => {
    expect(screen.queryByTestId('work-item-title-input')).not.toBe(null);
  });
};

export const reloadWorkItemCreatePage = async () => {
  await waitForPromises();
  createPage.destroy();
  await apolloProvider.defaultClient.cache.reset();
  await mountWorkItemCreatePage();
};
