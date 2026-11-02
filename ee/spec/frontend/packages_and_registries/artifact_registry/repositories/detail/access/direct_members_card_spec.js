import { GlAlert, GlAvatarLabeled, GlButton, GlTableLite } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import roleAssignmentsFixture from 'test_fixtures/ee/graphql/packages_and_registries/artifact_registry/graphql/queries/get_repository_role_assignments.query.graphql.json';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { typePolicies as artifactRegistryTypePolicies } from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import getRepositoryRoleAssignmentsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_role_assignments.query.graphql';
import DirectMembersCard from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/direct_members_card.vue';
import {
  REPOSITORY_ID,
  mockRoleAssignmentsErrorResponse,
  mockRoleAssignmentsLastPage,
} from '../../../mock_data';

Vue.use(VueApollo);

const firstPage = roleAssignmentsFixture.data.artifactRegistryRoleAssignments;
const [currentUserAssignment] = firstPage.nodes;

const pageResponse = (connection) => ({ data: { artifactRegistryRoleAssignments: connection } });

describe('ArtifactRegistryDirectMembersCard', () => {
  let wrapper;
  let handler;

  const findCrud = () => wrapper.findComponent(CrudComponent);
  const findTable = () => wrapper.findComponent(GlTableLite);
  const findRows = () => findTable().findAll('tbody tr');
  const findCells = (row) => row.findAll('td').wrappers.map((td) => td.text());
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findRetry = () => findAlert().findComponent(GlButton);
  const findLoadMore = () => wrapper.findComponentByTestId('load-more');
  const findCount = () => wrapper.findByTestId('crud-count');
  const findEmpty = () => wrapper.findByTestId('crud-empty');

  const createComponent = async ({ wait = true } = {}) => {
    wrapper = mountExtended(DirectMembersCard, {
      propsData: { repositoryId: REPOSITORY_ID },
      apolloProvider: createMockApollo(
        [[getRepositoryRoleAssignmentsQuery, handler]],
        {},
        { typePolicies: { ...globalTypePolicies, ...artifactRegistryTypePolicies } },
      ),
    });

    if (wait) await waitForPromises();
  };

  const loadMore = async () => {
    findLoadMore().vm.$emit('click');
    await waitForPromises();
  };

  beforeEach(() => {
    window.gon = { current_user_id: Number(getIdFromGraphQLId(currentUserAssignment.assignee.id)) };
    handler = jest.fn().mockResolvedValue(pageResponse(firstPage));
  });

  it('is titled Direct members, one level below the panel heading', async () => {
    await createComponent();

    expect(findCrud().props()).toMatchObject({ title: 'Direct members', titleTag: 'h3' });
  });

  it('shows a skeleton while the first page loads', async () => {
    await createComponent({ wait: false });

    expect(findCrud().props('isLoading')).toBe(true);
    expect(findTable().exists()).toBe(false);
  });

  it('reads the first page of direct assignments on the repository', async () => {
    await createComponent();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler).toHaveBeenCalledWith({ resourceId: REPOSITORY_ID, first: 100 });
  });

  describe('with assignments', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('has Member and Role columns, and an actions column named for screen readers', () => {
      const headers = findTable().findAll('thead th');

      expect(headers.wrappers.map((th) => th.text())).toEqual(['Member', 'Role', 'Actions']);
      expect(headers.at(2).classes()).toContain('gl-sr-only');
    });

    it('lists each member with name, username, and role', () => {
      expect(findCells(findRows().at(0))).toEqual([
        expect.stringContaining('Avery Admin'),
        'Artifact Admin',
        '',
      ]);
      expect(findCells(findRows().at(0))[0]).toContain('@avery-admin');
      expect(findCells(findRows().at(1))).toEqual([
        expect.stringContaining('@vic-viewer'),
        'Artifact Viewer',
        '',
      ]);
    });

    it('links each member to their profile', () => {
      const avatar = findRows().at(1).findComponent(GlAvatarLabeled);

      expect(avatar.props()).toMatchObject({
        label: 'Vic Viewer',
        labelLink: '/vic-viewer',
        subLabel: '@vic-viewer',
      });
    });

    it("marks only the viewer's own row", () => {
      const badges = wrapper.findAllByTestId('current-user-badge');

      expect(badges).toHaveLength(1);
      expect(findRows().at(0).find('[data-testid="current-user-badge"]').text()).toBe("It's you");
    });

    it('hides an assignment whose assignee is unavailable', () => {
      expect(firstPage.nodes).toHaveLength(4);
      expect(findRows()).toHaveLength(3);
      expect(findTable().text()).not.toContain('Artifact Contributor');
    });

    it('renders a role the enum does not declare as a placeholder role', () => {
      expect(findCells(findRows().at(2))).toEqual([
        expect.stringContaining('Oli Other'),
        'Unavailable role',
        '',
      ]);
    });

    it('counts the loaded rows, with a plus while more pages exist', () => {
      expect(findCount().text()).toBe('3+');
    });

    it('renders no alert', () => {
      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('Load more', () => {
    beforeEach(async () => {
      handler.mockResolvedValueOnce(pageResponse(firstPage));
      await createComponent();
    });

    it('requests the next page with the previous end cursor', async () => {
      handler.mockResolvedValueOnce(pageResponse(mockRoleAssignmentsLastPage));

      await loadMore();

      expect(handler).toHaveBeenLastCalledWith({
        resourceId: REPOSITORY_ID,
        first: 100,
        after: firstPage.pageInfo.endCursor,
      });
    });

    it('appends the next page and drops the plus on the last page', async () => {
      handler.mockResolvedValueOnce(pageResponse(mockRoleAssignmentsLastPage));

      await loadMore();

      expect(findRows()).toHaveLength(4);
      expect(findCells(findRows().at(3))).toEqual([
        expect.stringContaining('Morgan Manager'),
        'Artifact Manager',
        '',
      ]);
      expect(findCount().text()).toBe('4');
      expect(findLoadMore().exists()).toBe(false);
    });

    describe('when it is denied', () => {
      beforeEach(async () => {
        handler.mockResolvedValueOnce(mockRoleAssignmentsErrorResponse('denied'));
        await loadMore();
      });

      it('shows the denied alert with no retry', () => {
        expect(findAlert().text()).toBe(
          "You don't have permission to view access for this repository.",
        );
        expect(findRetry().exists()).toBe(false);
      });

      it('keeps the loaded rows and removes Load more', () => {
        expect(findRows()).toHaveLength(3);
        expect(findLoadMore().exists()).toBe(false);
      });
    });

    describe.each(['unavailable', 'unknown', undefined])('when it fails with code %s', (code) => {
      beforeEach(async () => {
        handler.mockResolvedValueOnce(mockRoleAssignmentsErrorResponse(code));
        await loadMore();
      });

      it('shows the failure alert with no retry, leaving Load more to try again', () => {
        expect(findAlert().text()).toBe('Direct members could not be loaded.');
        expect(findRetry().exists()).toBe(false);
        expect(findLoadMore().exists()).toBe(true);
      });

      it('keeps the loaded rows', () => {
        expect(findRows()).toHaveLength(3);
      });

      it('clears the alert once Load more succeeds', async () => {
        handler.mockResolvedValueOnce(pageResponse(mockRoleAssignmentsLastPage));

        await loadMore();

        expect(findAlert().exists()).toBe(false);
        expect(findRows()).toHaveLength(4);
      });
    });

    describe('when the cursor no longer matches', () => {
      const reloadedPage = { ...firstPage, nodes: firstPage.nodes.slice(0, 2) };

      beforeEach(() => {
        handler.mockResolvedValueOnce(mockRoleAssignmentsErrorResponse('invalid_request'));
      });

      it('discards the loaded rows and reloads from the first page', async () => {
        handler.mockResolvedValueOnce(pageResponse(reloadedPage));

        await loadMore();

        expect(handler).toHaveBeenLastCalledWith({ resourceId: REPOSITORY_ID, first: 100 });
        expect(findRows()).toHaveLength(2);
        expect(findAlert().exists()).toBe(false);
      });

      it('shows the alert with retry when the reload fails', async () => {
        handler.mockResolvedValueOnce(mockRoleAssignmentsErrorResponse('unavailable'));

        await loadMore();

        expect(findAlert().text()).toContain('Direct members could not be loaded.');
        expect(findRetry().text()).toBe('Retry');
        expect(findTable().exists()).toBe(false);
      });

      it('reloads only once, then shows the alert with retry', async () => {
        handler.mockResolvedValueOnce(pageResponse(firstPage));
        await loadMore();

        handler.mockResolvedValueOnce(mockRoleAssignmentsErrorResponse('invalid_request'));
        await loadMore();

        expect(handler).toHaveBeenCalledTimes(4);
        expect(findAlert().text()).toContain('Direct members could not be loaded.');
        expect(findRetry().text()).toBe('Retry');
        expect(findRows()).toHaveLength(3);
      });

      it('reloads again for a later stale cursor once a Retry succeeds in between', async () => {
        handler.mockResolvedValueOnce(pageResponse(firstPage));
        await loadMore();

        handler.mockResolvedValueOnce(mockRoleAssignmentsErrorResponse('invalid_request'));
        await loadMore();

        handler.mockResolvedValueOnce(pageResponse(firstPage));
        findRetry().vm.$emit('click');
        await waitForPromises();

        handler.mockResolvedValueOnce(mockRoleAssignmentsErrorResponse('invalid_request'));
        handler.mockResolvedValueOnce(pageResponse(reloadedPage));
        await loadMore();

        expect(handler).toHaveBeenCalledTimes(7);
        expect(handler).toHaveBeenLastCalledWith({ resourceId: REPOSITORY_ID, first: 100 });
        expect(findRows()).toHaveLength(2);
        expect(findAlert().exists()).toBe(false);
      });

      it('reloads again for a later stale cursor once a Load more succeeds in between', async () => {
        const nextPage = {
          ...mockRoleAssignmentsLastPage,
          pageInfo: { ...firstPage.pageInfo, endCursor: 'page-3' },
        };

        handler.mockResolvedValueOnce(pageResponse(firstPage));
        await loadMore();

        handler.mockResolvedValueOnce(pageResponse(nextPage));
        await loadMore();

        handler.mockResolvedValueOnce(mockRoleAssignmentsErrorResponse('invalid_request'));
        handler.mockResolvedValueOnce(pageResponse(reloadedPage));
        await loadMore();

        expect(handler).toHaveBeenCalledTimes(6);
        expect(handler).toHaveBeenLastCalledWith({ resourceId: REPOSITORY_ID, first: 100 });
        expect(findRows()).toHaveLength(2);
        expect(findAlert().exists()).toBe(false);
      });
    });
  });

  describe('with no assignments', () => {
    beforeEach(async () => {
      handler.mockResolvedValue(
        pageResponse({
          ...firstPage,
          nodes: [],
          pageInfo: { ...firstPage.pageInfo, hasNextPage: false, endCursor: null },
        }),
      );
      await createComponent();
    });

    it('says the repository has no direct members', () => {
      expect(findEmpty().text()).toBe('There are no direct members for this repository.');
      expect(findTable().exists()).toBe(false);
    });

    it('counts zero', () => {
      expect(findCount().text()).toBe('0');
    });

    it('offers no Load more', () => {
      expect(findLoadMore().exists()).toBe(false);
    });
  });

  describe('when the first page is denied', () => {
    beforeEach(async () => {
      handler.mockResolvedValue(mockRoleAssignmentsErrorResponse('denied'));
      await createComponent();
    });

    it('shows the denied alert with no retry', () => {
      expect(findAlert().text()).toBe(
        "You don't have permission to view access for this repository.",
      );
      expect(findRetry().exists()).toBe(false);
    });

    it('announces the alert', () => {
      expect(findAlert().attributes('role')).toBe('alert');
    });

    it('renders no rows, count, or empty state', () => {
      expect(findTable().exists()).toBe(false);
      expect(findCount().exists()).toBe(false);
      expect(findEmpty().exists()).toBe(false);
    });
  });

  describe.each(['unavailable', 'invalid_request', 'unknown', 'unrecognized', undefined])(
    'when the first page fails with code %s',
    (code) => {
      beforeEach(async () => {
        handler.mockResolvedValueOnce(mockRoleAssignmentsErrorResponse(code));
        await createComponent();
      });

      it('shows the failure alert with retry', () => {
        expect(findAlert().text()).toContain('Direct members could not be loaded.');
        expect(findAlert().attributes('role')).toBe('alert');
        expect(findRetry().text()).toBe('Retry');
      });

      it('renders no rows', () => {
        expect(findTable().exists()).toBe(false);
      });

      it('reads the first page again on retry', async () => {
        findRetry().vm.$emit('click');
        await waitForPromises();

        expect(handler).toHaveBeenCalledTimes(2);
        expect(findAlert().exists()).toBe(false);
        expect(findRows()).toHaveLength(3);
      });
    },
  );

  it('chooses the alert by code, not by message', async () => {
    handler.mockResolvedValue({
      errors: [
        {
          message: "You don't have permission to view access for this repository.",
          extensions: { code: 'unavailable' },
        },
      ],
    });
    await createComponent();

    expect(findAlert().text()).toContain('Direct members could not be loaded.');
    expect(findRetry().exists()).toBe(true);
  });
});
