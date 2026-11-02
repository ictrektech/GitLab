import Vue, { ref } from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlLoadingIcon } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import OrbitSchemaPage from 'ee/orbit/dashboard/schema/orbit_schema_page.vue';
import SchemaDataTab from 'ee/orbit/dashboard/schema/schema_data_tab.vue';
import { fetchOrbitSchema } from 'ee/orbit/api/orbit_api';
import { buildItemCountGroup, mockExpandedSchema } from '../../mock_data';

jest.mock('ee/orbit/api/orbit_api', () => ({
  fetchOrbitSchema: jest.fn(),
}));
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('OrbitSchemaPage', () => {
  let wrapper;
  const routerPush = jest.fn();
  const pipelineCounts = buildItemCountGroup({ domains: { ci: { Pipeline: 1200 } } });

  const createComponent = ({ query = {}, itemCountGroups = [pipelineCounts] } = {}) => {
    wrapper = shallowMountExtended(OrbitSchemaPage, {
      apolloProvider: createMockApollo(),
      provide: { itemCountGroups: ref(itemCountGroups) },
      mocks: { $route: { query }, $router: { push: routerPush } },
      stubs: { GlAlert },
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findError = () => wrapper.findComponent(GlAlert);
  const findTab = () => wrapper.findComponent(SchemaDataTab);

  describe('while the schema loads', () => {
    beforeEach(() => {
      fetchOrbitSchema.mockReturnValue(new Promise(() => {}));
      createComponent();
    });

    it('shows only the loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(true);
      expect(findError().exists()).toBe(false);
      expect(findTab().exists()).toBe(false);
    });
  });

  describe('when the schema loads', () => {
    beforeEach(async () => {
      fetchOrbitSchema.mockResolvedValue(mockExpandedSchema);
      createComponent({ query: { entity: 'pipeline' } });
      await waitForPromises();
    });

    it('passes the schema, the graph counts of the root groups, and the entity from the URL', () => {
      expect(fetchOrbitSchema).toHaveBeenCalledWith(
        expect.objectContaining({ query: expect.any(Function) }),
        {},
      );
      expect(findLoadingIcon().exists()).toBe(false);
      expect(findTab().props()).toEqual({
        schema: mockExpandedSchema,
        graphStats: { pipeline: 1200 },
        initialEntity: 'pipeline',
      });
    });

    it('opens Overview for an entity type from the tab', () => {
      findTab().vm.$emit('show-instances', { entityType: 'Pipeline' });

      expect(routerPush).toHaveBeenCalledWith({
        name: 'overview',
        query: { entity: 'Pipeline' },
      });
    });

    it('opens the Query editor with a query from the tab', () => {
      const query = 'MATCH (p:Pipeline)\nWHERE p.id IS NOT NULL\nRETURN p.id\nLIMIT 25';
      findTab().vm.$emit('open-query', query);

      expect(routerPush).toHaveBeenCalledWith({ name: 'query', query: { query } });
    });
  });

  describe('when the URL has no entity', () => {
    beforeEach(async () => {
      fetchOrbitSchema.mockResolvedValue(mockExpandedSchema);
      createComponent();
      await waitForPromises();
    });

    it('opens no entity', () => {
      expect(findTab().props('initialEntity')).toBe(null);
    });
  });

  it.each`
    case                         | itemCountGroups
    ${'no counts'}               | ${[]}
    ${'null counts for a group'} | ${[pipelineCounts, { ...buildItemCountGroup({ id: 2 }), orbit: { itemCounts: null } }]}
  `(
    'shows no counts with $case, so a partial sum never reads as the real count',
    async ({ itemCountGroups }) => {
      fetchOrbitSchema.mockResolvedValue(mockExpandedSchema);
      createComponent({ itemCountGroups });
      await waitForPromises();

      expect(findTab().props('graphStats')).toBe(null);
    },
  );

  describe('when the URL repeats the entity parameter', () => {
    beforeEach(async () => {
      fetchOrbitSchema.mockResolvedValue(mockExpandedSchema);
      createComponent({ query: { entity: ['job', 'pipeline'] } });
      await waitForPromises();
    });

    it('opens the first entity', () => {
      expect(findTab().props('initialEntity')).toBe('job');
    });
  });

  describe('when there is no schema', () => {
    beforeEach(async () => {
      fetchOrbitSchema.mockResolvedValue(null);
      createComponent();
      await waitForPromises();
    });

    it('shows the error with a retry button and reports nothing', () => {
      expect(findTab().exists()).toBe(false);
      expect(findError().text()).toContain('Could not load the schema. Try again.');
      expect(Sentry.captureException).not.toHaveBeenCalled();
    });
  });

  describe('when the schema fails to load', () => {
    const error = new Error('503');

    beforeEach(async () => {
      fetchOrbitSchema.mockRejectedValueOnce(error);
      createComponent();
      await waitForPromises();
    });

    it('shows an error with a retry button and no loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(false);
      expect(findTab().exists()).toBe(false);
      expect(findError().text()).toContain('Could not load the schema. Try again.');
      expect(findError().props('primaryButtonText')).toBe('Try again');
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });

    describe('and the user retries', () => {
      beforeEach(async () => {
        fetchOrbitSchema.mockResolvedValueOnce(mockExpandedSchema);
        findError().vm.$emit('primary-action');
        await waitForPromises();
      });

      it('loads the schema again and shows the tab', () => {
        expect(fetchOrbitSchema).toHaveBeenCalledTimes(2);
        expect(fetchOrbitSchema).toHaveBeenLastCalledWith(expect.anything(), {
          fetchPolicy: 'network-only',
        });
        expect(findError().exists()).toBe(false);
        expect(findTab().props('schema')).toEqual(mockExpandedSchema);
      });
    });
  });
});
