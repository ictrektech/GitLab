import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { createAlert } from '~/alert';
import GraphExplorer from 'ee/orbit/components/graph_explorer.vue';
import GraphCanvas from 'ee/orbit/components/graph_canvas.vue';
import ExplorerNodeSidebar from 'ee/orbit/components/explorer_node_sidebar.vue';
import * as orbitApi from 'ee/orbit/api/orbit_api';
import { mockNeighborResponse, mockQueryResponse } from '../mock_data';

jest.mock('~/alert');
jest.mock('ee/orbit/api/orbit_api');

describe('GraphExplorer', () => {
  let wrapper;

  const mockGroupNode = {
    id: 'Group_1',
    label: 'frontend',
    type: 'group',
    properties: { id: 1, full_path: 'gitlab-org/frontend' },
  };

  const GraphCanvasStub = {
    name: 'GraphCanvas',
    props: ['nodes', 'edges', 'selectedNodeId', 'nodeStyleMap', 'darkMode'],
    template: '<div data-testid="graph-canvas-stub"></div>',
    methods: {
      setFullData: jest.fn(),
      addData: jest.fn(),
      setNodeLoading: jest.fn(),
    },
  };

  const createWrapper = (props = {}, slots = {}) => {
    wrapper = shallowMount(GraphExplorer, {
      propsData: {
        initialNodes: [mockGroupNode],
        initialEdges: [],
        ...props,
      },
      slots,
      stubs: { GraphCanvas: GraphCanvasStub },
    });
  };

  beforeEach(() => {
    jest.clearAllMocks();
    localStorage.clear();
    orbitApi.executeOrbitNamedQuery.mockResolvedValue({
      data: { result: { nodes: [], edges: [] } },
    });
  });

  describe('rendering', () => {
    it('renders the explorer container', () => {
      createWrapper();

      expect(wrapper.find('[data-testid="graph-explorer"]').exists()).toBe(true);
    });

    it('renders the graph canvas', () => {
      createWrapper();

      expect(wrapper.findComponent(GraphCanvas).exists()).toBe(true);
    });
  });

  describe('initial neighbor expansion', () => {
    it('fetches neighbors of the initial group nodes on mount', async () => {
      createWrapper();
      await waitForPromises();

      expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledWith('expand_neighbors', {
        parameters: { entity: 'Group', node_ids: [1], limit: 500 },
      });
    });

    it('fetches neighbors when initial group nodes arrive after mount', async () => {
      createWrapper({ initialNodes: [] });
      await waitForPromises();

      expect(orbitApi.executeOrbitNamedQuery).not.toHaveBeenCalled();

      await wrapper.setProps({ initialNodes: [mockGroupNode] });
      await waitForPromises();

      expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledWith('expand_neighbors', {
        parameters: { entity: 'Group', node_ids: [1], limit: 500 },
      });
    });

    describe('when the same neighborsVersion mounts again', () => {
      beforeEach(async () => {
        orbitApi.executeOrbitNamedQuery.mockResolvedValue({
          data: { result: { nodes: [{ type: 'User', id: 7, name: 'root' }], edges: [] } },
        });
        createWrapper({ neighborsVersion: 'a:SYNCING' });
        await waitForPromises();
        createWrapper({ neighborsVersion: 'a:SYNCING' });
        await waitForPromises();
      });

      it('reads the neighbors from the cache', () => {
        expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledTimes(1);
      });

      describe('and neighborsVersion changes', () => {
        beforeEach(async () => {
          await wrapper.setProps({ neighborsVersion: 'a:READY' });
          await waitForPromises();
        });

        it('refetches the neighbors past the cache', () => {
          expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledTimes(2);
        });
      });
    });

    describe('when expandNeighbors is false', () => {
      beforeEach(async () => {
        createWrapper({ expandNeighbors: false });
        await waitForPromises();
      });

      it('does not fetch the neighbors', () => {
        expect(orbitApi.executeOrbitNamedQuery).not.toHaveBeenCalled();
      });
    });

    describe('when an instance map request is supplied', () => {
      beforeEach(async () => {
        createWrapper({
          instanceMapRequest: { entityType: 'Project' },
          neighborsVersion: 'a:SYNCING',
        });
        await waitForPromises();
      });

      describe('and neighborsVersion changes', () => {
        beforeEach(async () => {
          await wrapper.setProps({ neighborsVersion: 'a:READY' });
          await waitForPromises();
        });

        it('does not fetch the group neighbors', () => {
          expect(orbitApi.executeOrbitNamedQuery).not.toHaveBeenCalledWith(
            'expand_neighbors',
            expect.anything(),
          );
        });
      });
    });

    describe('when an instance map request lists the nodes of an entity', () => {
      beforeEach(async () => {
        orbitApi.executeOrbitNamedQuery.mockResolvedValue(mockQueryResponse);
        createWrapper({ initialNodes: [], instanceMapRequest: { entityType: 'User' } });
        await waitForPromises();
      });

      it('runs the list_nodes named query instead of the initial expansion', () => {
        expect(orbitApi.executeOrbitNamedQuery).not.toHaveBeenCalledWith(
          'expand_neighbors',
          expect.anything(),
        );
        expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledWith('list_nodes', {
          parameters: { entity: 'User' },
        });
      });

      it('draws the listed nodes on the canvas', () => {
        const canvasNodeIds = wrapper
          .findComponent(GraphCanvas)
          .props('nodes')
          .map((node) => node.id);

        expect(canvasNodeIds).toEqual(['User_1', 'User_2']);
        expect(GraphCanvasStub.methods.setFullData).toHaveBeenCalledTimes(1);
      });
    });

    describe('when the neighbor fetch fails', () => {
      beforeEach(async () => {
        orbitApi.executeOrbitNamedQuery.mockRejectedValueOnce(new Error('Request failed with 503'));
        createWrapper();
        await waitForPromises();
      });

      it('alerts with the neighbors message', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Could not load the map. Try again.',
          error: expect.any(Error),
          captureError: true,
        });
      });
    });

    describe('when the neighbor fetch is forbidden', () => {
      beforeEach(async () => {
        orbitApi.executeOrbitNamedQuery.mockRejectedValueOnce({ response: { status: 403 } });
        createWrapper();
        await waitForPromises();
      });

      it('does not alert', () => {
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('when the neighbor fetch is rate limited', () => {
      const error = {
        response: { status: 429, data: { message: { error: 'Too many requests' } } },
      };

      beforeEach(async () => {
        orbitApi.executeOrbitNamedQuery.mockRejectedValueOnce(error);
        createWrapper();
        await waitForPromises();
      });

      it('alerts with the API message and does not report to Sentry', () => {
        expect(createAlert).toHaveBeenCalledWith({
          message: 'Too many requests',
          error,
          captureError: false,
        });
      });
    });

    describe('when the instance map query fails', () => {
      beforeEach(async () => {
        orbitApi.executeOrbitNamedQuery.mockRejectedValueOnce(new Error('list failed'));
        createWrapper({ instanceMapRequest: { entityType: 'MergeRequest' } });
        await waitForPromises();
      });

      it('shows the error in an alert', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'list failed' });
      });
    });

    describe('when the API rejects the instance map query with a message', () => {
      beforeEach(async () => {
        orbitApi.executeOrbitNamedQuery.mockRejectedValueOnce({
          message: 'Request failed with status code 400',
          response: { status: 400, data: { message: 'Unknown entity: MergeReq' } },
        });
        createWrapper({ instanceMapRequest: { entityType: 'MergeRequest' } });
        await waitForPromises();
      });

      it('shows the message of the API', () => {
        expect(createAlert).toHaveBeenCalledWith({ message: 'Unknown entity: MergeReq' });
      });
    });
  });

  describe('when the browser cannot show the map', () => {
    beforeEach(async () => {
      createWrapper();
      wrapper.findComponent(GraphCanvas).vm.$emit('init-error', new Error('no WebGL'));
      await waitForPromises();
    });

    it('shows a message with no canvas and tells the parent', () => {
      expect(wrapper.find('[data-testid="graph-explorer-map-unavailable"]').text()).toBe(
        'Your browser cannot show the map. Turn on WebGL or hardware acceleration, then reload the page.',
      );
      expect(wrapper.findComponent(GraphCanvas).exists()).toBe(false);
    });

    it('does not draw on the canvas or fetch the group neighbors', () => {
      expect(GraphCanvasStub.methods.setFullData).not.toHaveBeenCalled();
      expect(orbitApi.executeOrbitNamedQuery).not.toHaveBeenCalled();
    });
  });

  describe('when a node is selected and the top-right slot has content', () => {
    beforeEach(async () => {
      createWrapper({}, { 'top-right': '<div data-testid="top-right-content"></div>' });
      wrapper.findComponent(GraphCanvas).vm.$emit('node-select', { id: 'Group_1' });
      await nextTick();
    });

    it('shows the sidebar below the slot content', () => {
      const column = wrapper.find('[data-testid="top-right-content"]').element.parentElement;

      expect(column.lastElementChild).toBe(wrapper.findComponent(ExplorerNodeSidebar).element);
    });
  });

  describe('node interaction', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('records the selected node and shows the sidebar', async () => {
      const canvas = wrapper.findComponent(GraphCanvas);
      canvas.vm.$emit('node-select', { id: 'Group_1', label: 'frontend', type: 'group' });
      await nextTick();

      expect(wrapper.findComponent(ExplorerNodeSidebar).exists()).toBe(true);
    });

    it('hides the sidebar when the selection is cleared', async () => {
      const canvas = wrapper.findComponent(GraphCanvas);
      canvas.vm.$emit('node-select', { id: 'Group_1' });
      await nextTick();

      wrapper.findComponent(ExplorerNodeSidebar).vm.$emit('close');
      await nextTick();

      expect(wrapper.findComponent(ExplorerNodeSidebar).exists()).toBe(false);
    });

    it('expands a node by fetching its neighbors with the per-node limit', async () => {
      // Wait for the mount-time auto-expand to complete first so we can
      // observe the per-node expansion in isolation.
      await waitForPromises();
      orbitApi.executeOrbitNamedQuery.mockClear();
      orbitApi.executeOrbitNamedQuery.mockResolvedValue(mockNeighborResponse);

      const canvas = wrapper.findComponent(GraphCanvas);
      canvas.vm.$emit('node-expand', {
        id: 'Project_2',
        type: 'project',
        properties: { id: 2 },
      });
      await waitForPromises();

      expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledWith('expand_neighbors', {
        parameters: { entity: 'Project', node_ids: [2], limit: 50 },
      });
    });

    it('does not re-expand a node that was already expanded', async () => {
      await waitForPromises();
      orbitApi.executeOrbitNamedQuery.mockClear();
      orbitApi.executeOrbitNamedQuery.mockResolvedValue(mockNeighborResponse);

      const canvas = wrapper.findComponent(GraphCanvas);
      const node = { id: 'Project_2', type: 'project', properties: { id: 2 } };

      canvas.vm.$emit('node-expand', node);
      await waitForPromises();
      const firstCallCount = orbitApi.executeOrbitNamedQuery.mock.calls.length;

      canvas.vm.$emit('node-expand', node);
      await waitForPromises();

      expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledTimes(firstCallCount);
    });

    it('marks the node as loading on the canvas while the request is in flight', async () => {
      await waitForPromises();
      orbitApi.executeOrbitNamedQuery.mockClear();
      orbitApi.executeOrbitNamedQuery.mockResolvedValue(mockNeighborResponse);
      GraphCanvasStub.methods.setNodeLoading.mockClear();

      const canvas = wrapper.findComponent(GraphCanvas);
      const node = { id: 'Project_2', type: 'project', index: 4, properties: { id: 2 } };
      expect(GraphCanvasStub.methods.setNodeLoading).not.toHaveBeenCalled();
      canvas.vm.$emit('node-expand', node);
      await waitForPromises();

      expect(GraphCanvasStub.methods.setNodeLoading).toHaveBeenNthCalledWith(1, 4, true);
      expect(GraphCanvasStub.methods.setNodeLoading).toHaveBeenNthCalledWith(2, 4, false);
    });

    it('clears the loading flag even when the expand request fails', async () => {
      await waitForPromises();
      orbitApi.executeOrbitNamedQuery.mockClear();
      orbitApi.executeOrbitNamedQuery.mockRejectedValueOnce(new Error('boom'));
      GraphCanvasStub.methods.setNodeLoading.mockClear();

      const canvas = wrapper.findComponent(GraphCanvas);
      const node = { id: 'Project_3', type: 'project', index: 7, properties: { id: 3 } };
      expect(GraphCanvasStub.methods.setNodeLoading).not.toHaveBeenCalled();
      canvas.vm.$emit('node-expand', node);
      await waitForPromises();

      expect(GraphCanvasStub.methods.setNodeLoading).toHaveBeenNthCalledWith(1, 7, true);
      expect(GraphCanvasStub.methods.setNodeLoading).toHaveBeenLastCalledWith(7, false);
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks click_orbit_map_node when a node is selected', () => {
      createWrapper();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      wrapper.findComponent(GraphCanvas).vm.$emit('node-select', { id: 'Project_1' });

      expect(trackEventSpy).toHaveBeenCalledWith('click_orbit_map_node', {}, undefined);
    });

    it('tracks click_orbit_expand_map_node when a node is double-clicked', () => {
      createWrapper();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      wrapper.findComponent(GraphCanvas).vm.$emit('node-expand', {
        id: 'Project_1',
        type: 'project',
        properties: { id: 1 },
      });

      expect(trackEventSpy).toHaveBeenCalledWith('click_orbit_expand_map_node', {}, undefined);
    });
  });
});
