import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import SchemaGraphViewport from 'ee/orbit/dashboard/schema/schema_graph_viewport.vue';

describe('SchemaGraphViewport', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(SchemaGraphViewport, {
      propsData: { width: 1300, height: 820 },
      directives: { GlResizeObserver: createMockDirective('gl-resize-observer') },
      scopedSlots: {
        default(props) {
          return this.$createElement('button', {
            attrs: { 'data-testid': 'graph', 'data-scale': props.scale },
          });
        },
      },
    });
  };

  const findViewport = () => wrapper.findByTestId('schema-graph-viewport');
  const findSizer = () => wrapper.findByTestId('schema-graph-sizer');
  const findCanvas = () => findSizer().element.firstElementChild;
  const sizerWidth = () => parseFloat(findSizer().element.style.width);
  const graphScale = () => parseFloat(wrapper.findByTestId('graph').attributes('data-scale'));
  const findZoomIn = () => wrapper.findComponentByTestId('schema-zoom-in');
  const findZoomOut = () => wrapper.findComponentByTestId('schema-zoom-out');
  const clickTimes = async (button, times) => {
    for (let click = 0; click < times; click += 1) {
      button.vm.$emit('click');
    }
    await nextTick();
  };
  const resizeTo = async (width, height) => {
    getBinding(findViewport().element, 'gl-resize-observer').value({
      contentRect: { width, height },
    });
    await nextTick();
  };

  describe('when the graph has room', () => {
    beforeEach(async () => {
      createComponent();
      await resizeTo(1600, 900);
    });

    it('fits the graph in the space and draws it at that scale', () => {
      expect(sizerWidth()).toBeCloseTo(1350.73, 2);
      expect(graphScale()).toBeCloseTo(1.039, 3);
      expect(findCanvas().style.transform).toBe('scale(1)');
    });

    describe('and the user zooms in', () => {
      beforeEach(async () => {
        await clickTimes(findZoomIn(), 1);
      });

      it('makes the graph larger', () => {
        expect(sizerWidth()).toBeCloseTo(1553.34, 2);
      });

      describe('and resets the view', () => {
        beforeEach(async () => {
          await wrapper.findComponentByTestId('schema-zoom-reset').vm.$emit('click');
        });

        it('fits the graph in the space again', () => {
          expect(sizerWidth()).toBeCloseTo(1350.73, 2);
        });
      });
    });

    describe('and the user zooms in more times than the largest scale allows', () => {
      beforeEach(async () => {
        await clickTimes(findZoomIn(), 10);
      });

      it('stops at the largest scale and turns off Zoom in', () => {
        expect(sizerWidth()).toBeCloseTo(1820, 2);
        expect(findZoomIn().props('disabled')).toBe(true);
      });

      describe('and zooms out', () => {
        beforeEach(async () => {
          await clickTimes(findZoomOut(), 1);
        });

        it('makes the graph smaller at the first click', () => {
          expect(sizerWidth()).toBeLessThan(1820);
          expect(findZoomIn().props('disabled')).toBe(false);
        });
      });
    });

    describe('and the user zooms out to the smallest zoom', () => {
      beforeEach(async () => {
        await clickTimes(findZoomOut(), 6);
      });

      it('turns off Zoom out', () => {
        expect(findZoomOut().props('disabled')).toBe(true);
      });
    });
  });

  describe('when the space is smaller than the graph at its minimum scale', () => {
    beforeEach(async () => {
      createComponent();
      await resizeTo(800, 500);
    });

    it('shrinks the whole graph to fit, so the panel does not scroll', () => {
      expect(sizerWidth()).toBeCloseTo(716.59, 2);
      expect(parseFloat(findCanvas().style.width)).toBeCloseTo(910, 2);
      expect(findCanvas().style.transform).toMatch(/^scale\(0\.78/);
    });
  });

  describe('when the space is smaller than the padding', () => {
    beforeEach(async () => {
      createComponent();
      await resizeTo(30, 30);
    });

    it('draws the graph at zero size', () => {
      expect(sizerWidth()).toBe(0);
      expect(findCanvas().style.transform).toBe('scale(0)');
    });
  });

  describe('when the user drags the graph', () => {
    const drag = async (target, { x, y }) => {
      findViewport().element.setPointerCapture = jest.fn();
      await target.trigger('pointerdown', { button: 0, clientX: 100, clientY: 100, pointerId: 1 });
      await findViewport().trigger('pointermove', { clientX: 100 + x, clientY: 100 + y });
      await findViewport().trigger('pointerup');
    };

    beforeEach(() => {
      createComponent();
    });

    describe('from an empty part of the graph', () => {
      beforeEach(async () => {
        await drag(findViewport(), { x: 60, y: 30 });
      });

      it('moves the graph with the pointer', () => {
        expect(findSizer().element.style.transform).toBe('translate(60px, 30px)');
      });

      describe('and resets the view', () => {
        beforeEach(async () => {
          await wrapper.findComponentByTestId('schema-zoom-reset').vm.$emit('click');
        });

        it('moves the graph back', () => {
          expect(findSizer().element.style.transform).toBe('translate(0px, 0px)');
        });
      });
    });

    describe('from a button in the graph', () => {
      beforeEach(async () => {
        await drag(wrapper.findByTestId('graph'), { x: 60, y: 30 });
      });

      it('leaves the graph where it is', () => {
        expect(findSizer().element.style.transform).toBe('translate(0px, 0px)');
      });
    });
  });
});
