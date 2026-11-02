import createEventHub from '~/helpers/event_hub_factory';

import Diff from '~/diff';

describe('Diff', () => {
  describe('elementsForRenderedDiff', () => {
    it('merges elements by file hash and toggle entity', () => {
      const diff = new Diff();
      const container = document.createElement('div');
      const elements = ['rawButton', 'renderedButton', 'rawButton'].map((name, index) => {
        const element = document.createElement('button');
        element.dataset.fileHash = index === 2 ? 'second' : 'first';
        element.dataset.diffToggleEntity = name;
        container.appendChild(element);
        return element;
      });
      document.body.appendChild(container);

      try {
        expect(diff.elementsForRenderedDiff()).toEqual({
          first: { rawButton: elements[0], renderedButton: elements[1] },
          second: { rawButton: elements[2] },
        });
      } finally {
        container.remove();
      }
    });
  });

  describe('diff <-> tabs interactions', () => {
    let hub;

    beforeEach(() => {
      hub = createEventHub();
    });

    describe('constructor', () => {
      it("takes in the `mergeRequestEventHub` when it's provided", () => {
        const diff = new Diff({ mergeRequestEventHub: hub });

        expect(diff.mrHub).toBe(hub);
      });

      it('does not fatal if no event hub is provided', () => {
        expect(() => {
          new Diff(); /* eslint-disable-line no-new */
        }).not.toThrow();
      });

      it("doesn't set the mrHub property if none is provided by the construction arguments", () => {
        const diff = new Diff();

        expect(diff.mrHub).toBe(undefined);
      });
    });

    describe('viewTypeSwitch', () => {
      const clickPath = '/path/somewhere?params=exist';
      const jsonPath = 'http://test.host/path/somewhere.json?params=exist';
      const simulatejQueryClick = {
        originalEvent: {
          preventDefault: jest.fn(),
          stopPropagation: jest.fn(),
        },
        currentTarget: {
          getAttribute() {
            return clickPath;
          },
        },
      };

      it('emits the correct switch view event when called and there is an `mrHub`', async () => {
        const diff = new Diff({ mergeRequestEventHub: hub });
        const hubEmit = new Promise((resolve) => {
          hub.$on('diff:switch-view-type', resolve);
        });

        diff.viewTypeSwitch(simulatejQueryClick);
        const { source } = await hubEmit;

        expect(simulatejQueryClick.originalEvent.preventDefault).toHaveBeenCalled();
        expect(simulatejQueryClick.originalEvent.stopPropagation).toHaveBeenCalled();
        expect(source).toBe(jsonPath);
      });

      it('is effectively a noop when there is no `mrHub`', () => {
        const diff = new Diff();

        expect(diff.mrHub).toBe(undefined);
        expect(() => {
          diff.viewTypeSwitch(simulatejQueryClick);
        }).not.toThrow();
      });
    });
  });
});
