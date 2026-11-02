import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GraphCanvas from 'ee/orbit/components/graph_canvas.vue';

const mockGraphInstance = {
  init: jest.fn(),
  setData: jest.fn(),
  addData: jest.fn(),
  dispose: jest.fn(),
  selectNode: jest.fn(),
  deselectNode: jest.fn(),
  resize: jest.fn(),
  relayout: jest.fn(),
  onNodeHover: jest.fn(),
  onNodeSelect: jest.fn(),
  onNodeExpand: jest.fn(),
  setNodeLoading: jest.fn(),
};

jest.mock('ee/orbit/utils/three_graph_3d', () => ({
  __esModule: true,
  default: jest.fn(),
}));

// eslint-disable-next-line import-x/first
import ThreeGraph3D from 'ee/orbit/utils/three_graph_3d';

const mockThreeGraph3D = ThreeGraph3D;

describe('GraphCanvas', () => {
  let wrapper;
  let mockResizeObserverDisconnect;

  const mockNodes = [
    { id: 'User_1', label: 'Admin', type: 'user' },
    { id: 'User_2', label: 'Dev', type: 'user' },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockThreeGraph3D.mockImplementation(() => mockGraphInstance);
    mockResizeObserverDisconnect = jest.fn();
    global.ResizeObserver = jest.fn().mockImplementation((cb) => ({
      observe: jest.fn(() => cb([{ contentRect: { width: 800, height: 600 } }])),
      disconnect: mockResizeObserverDisconnect,
    }));
  });

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(GraphCanvas, {
      propsData: {
        nodes: mockNodes,
        edges: [],
        ...props,
      },
      attachTo: document.body,
    });
  };

  const findMap = () => wrapper.findByRole('application', { name: 'GitLab Orbit map' });

  // Vue 3 + VTU 2.x has unmount(). Vue 2 + VTU 1.x has destroy().
  const unmountWrapper = () => {
    if (typeof wrapper.unmount === 'function') {
      wrapper.unmount();
    } else {
      wrapper.destroy();
    }
  };

  describe('rendering', () => {
    it('renders the canvas container', () => {
      createWrapper();

      expect(wrapper.find('[data-testid="graph-canvas"]').exists()).toBe(true);
    });
  });

  describe('initialization', () => {
    it('starts a ThreeGraph3D', () => {
      createWrapper();

      expect(mockThreeGraph3D).toHaveBeenCalled();
      expect(mockGraphInstance.init).toHaveBeenCalled();
    });

    it('passes nodeStyleMap and darkMode through to the constructor', () => {
      const styleMap = { user: { color: 0x00ff00 } };
      createWrapper({ nodeStyleMap: styleMap, darkMode: false });

      expect(mockThreeGraph3D).toHaveBeenCalledWith(expect.anything(), {
        nodeStyleMap: styleMap,
        darkMode: false,
      });
    });

    it('sets initial data when nodes are provided', () => {
      createWrapper();

      expect(mockGraphInstance.setData).toHaveBeenCalledWith(mockNodes, []);
    });

    it('does not call setData when there are no nodes', () => {
      createWrapper({ nodes: [] });

      expect(mockGraphInstance.setData).not.toHaveBeenCalled();
    });

    it('emits init-error if graph construction throws', () => {
      const error = new Error('boom');
      mockThreeGraph3D.mockImplementationOnce(() => {
        throw error;
      });
      createWrapper({ nodes: [] });

      expect(wrapper.emitted('init-error')).toEqual([[error]]);
      expect(wrapper.emitted('node-select')).toBeUndefined();
    });
  });

  describe('event wiring', () => {
    it('emits node-hover, node-select, and node-expand from the graph callbacks', () => {
      createWrapper();

      const hoverCb = mockGraphInstance.onNodeHover.mock.calls[0][0];
      const selectCb = mockGraphInstance.onNodeSelect.mock.calls[0][0];
      const expandCb = mockGraphInstance.onNodeExpand.mock.calls[0][0];

      hoverCb({ id: 'a' }, { x: 1, y: 2 });
      selectCb({ id: 'a' });
      expandCb({ id: 'a' });

      expect(wrapper.emitted('node-hover')).toEqual([[{ id: 'a' }, { x: 1, y: 2 }]]);
      expect(wrapper.emitted('node-select')).toEqual([[{ id: 'a' }]]);
      expect(wrapper.emitted('node-expand')).toEqual([[{ id: 'a' }]]);
    });
  });

  describe('keyboard', () => {
    const pressKey = (key) => findMap().trigger('keydown', { key });

    beforeEach(() => {
      mockGraphInstance.selectedNode = null;
      createWrapper();
    });

    it('is a focusable map with instructions', () => {
      expect(findMap().attributes('tabindex')).toBe('0');
      expect(
        document.getElementById(findMap().attributes('aria-describedby')).textContent,
      ).toContain('Use the arrow keys to select a node');
    });

    describe.each`
      key             | selectedIndex | expected
      ${'ArrowRight'} | ${null}       | ${0}
      ${'ArrowLeft'}  | ${null}       | ${1}
      ${'ArrowDown'}  | ${0}          | ${1}
      ${'ArrowRight'} | ${1}          | ${0}
      ${'ArrowUp'}    | ${0}          | ${1}
    `('on $key with node $selectedIndex selected', ({ key, selectedIndex, expected }) => {
      beforeEach(() => {
        mockGraphInstance.selectedNode = selectedIndex === null ? null : { index: selectedIndex };
      });

      it(`selects node ${expected}`, () => {
        expect(mockGraphInstance.selectNode).not.toHaveBeenCalled();

        pressKey(key);

        expect(mockGraphInstance.selectNode).toHaveBeenCalledWith(expected);
      });
    });

    describe('on Enter', () => {
      describe('with a selected node', () => {
        beforeEach(() => {
          mockGraphInstance.selectedNode = { id: 'User_2', index: 1 };
          pressKey('Enter');
        });

        it('loads the connections of the selected node', () => {
          expect(wrapper.emitted('node-expand')).toEqual([[{ id: 'User_2', index: 1 }]]);
        });
      });

      describe('with no selected node', () => {
        beforeEach(() => {
          pressKey('Enter');
        });

        it('does nothing', () => {
          expect(wrapper.emitted('node-expand')).toBeUndefined();
        });
      });
    });

    it('announces nothing before a selection', () => {
      expect(wrapper.findByTestId('graph-canvas-selection').text()).toBe('');
    });

    describe('when a node is selected', () => {
      beforeEach(async () => {
        await wrapper.setProps({ selectedNodeId: 'User_2' });
      });

      it('announces the node', () => {
        expect(wrapper.findByTestId('graph-canvas-selection').text()).toBe('Dev is selected.');
      });
    });
  });

  describe('selectedNodeId watcher', () => {
    it('selects the node by index when the prop becomes set', async () => {
      createWrapper();

      await wrapper.setProps({ selectedNodeId: 'User_2' });

      expect(mockGraphInstance.selectNode).toHaveBeenCalledWith(1);
    });

    it('deselects when the prop becomes null', async () => {
      createWrapper({ selectedNodeId: 'User_1' });
      mockGraphInstance.deselectNode.mockClear();

      await wrapper.setProps({ selectedNodeId: null });

      expect(mockGraphInstance.deselectNode).toHaveBeenCalled();
    });

    it('is a no-op for an unknown id', async () => {
      createWrapper();
      mockGraphInstance.selectNode.mockClear();

      await wrapper.setProps({ selectedNodeId: 'does-not-exist' });

      expect(mockGraphInstance.selectNode).not.toHaveBeenCalled();
    });
  });

  describe('exposed methods', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('setFullData calls graph.setData with current props', () => {
      mockGraphInstance.setData.mockClear();
      wrapper.vm.setFullData();

      expect(mockGraphInstance.setData).toHaveBeenCalledWith(mockNodes, []);
    });

    it('addData forwards new nodes and edges to the graph and lays it out again', () => {
      const newNodes = [{ id: 'new' }];
      const newEdges = [{ source: 0, target: 1 }];
      wrapper.vm.addData(newNodes, newEdges);

      expect(mockGraphInstance.addData).toHaveBeenCalledWith(newNodes, newEdges);
      expect(mockGraphInstance.relayout).toHaveBeenCalled();
    });

    it('setNodeLoading proxies the node index and loading flag', () => {
      wrapper.vm.setNodeLoading(3, true);
      wrapper.vm.setNodeLoading(3, false);

      expect(mockGraphInstance.setNodeLoading).toHaveBeenNthCalledWith(1, 3, true);
      expect(mockGraphInstance.setNodeLoading).toHaveBeenNthCalledWith(2, 3, false);
    });
  });

  describe('resize handling', () => {
    it('observes the canvas with a ResizeObserver and forwards size changes', () => {
      createWrapper();

      expect(global.ResizeObserver).toHaveBeenCalled();
      expect(mockGraphInstance.resize).toHaveBeenCalledWith(800, 600);
    });
  });

  describe('when the graph fails to start after it was built', () => {
    const error = new Error('no WebGL');

    beforeEach(() => {
      mockGraphInstance.init.mockImplementationOnce(() => {
        throw error;
      });
      createWrapper();
    });

    it('emits init-error', () => {
      expect(wrapper.emitted('init-error')).toEqual([[error]]);
    });

    describe('and the canvas unmounts', () => {
      beforeEach(() => unmountWrapper());

      it('does not dispose the half-built graph', () => {
        expect(mockGraphInstance.dispose).not.toHaveBeenCalled();
      });
    });
  });

  describe('cleanup on unmount', () => {
    it('disconnects the ResizeObserver and disposes the graph', () => {
      createWrapper();
      expect(mockGraphInstance.dispose).not.toHaveBeenCalled();

      unmountWrapper();

      expect(mockResizeObserverDisconnect).toHaveBeenCalled();
      expect(mockGraphInstance.dispose).toHaveBeenCalled();
    });
  });
});
