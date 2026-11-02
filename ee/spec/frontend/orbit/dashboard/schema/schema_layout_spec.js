import {
  CLUSTER_CELL_HEIGHT_PX,
  RING_ASPECT_RATIO,
  GRAPH_MARGIN_X_PX,
  GRAPH_MARGIN_Y_PX,
} from 'ee/orbit/dashboard/schema/constants';
import { entityLayout } from 'ee/orbit/dashboard/schema/schema_layout';
import { entityPairs, schemaDomains } from 'ee/orbit/dashboard/schema/schema_graph';
import { mockScopedSchema } from '../../mock_data';

describe('schema_layout', () => {
  const layoutOf = (schema) => entityLayout(schemaDomains(schema), entityPairs(schema));
  const node = (name, domain) => ({ name, domain, style: { color: '#000000' } });
  const edge = (name, source, target) => ({
    name,
    variants: [{ source_type: source, target_type: target }],
  });
  const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const domainBox = (positions, names) => {
    const points = names.map((name) => positions[name]);
    return {
      left: Math.min(...points.map(({ x }) => x)),
      right: Math.max(...points.map(({ x }) => x)),
      top: Math.min(...points.map(({ y }) => y)),
      bottom: Math.max(...points.map(({ y }) => y)),
    };
  };
  const boxesOverlap = (a, b) =>
    a.left <= b.right && b.left <= a.right && a.top <= b.bottom && b.top <= a.bottom;

  describe('entityLayout', () => {
    describe('with a schema of three domains', () => {
      let layout;

      beforeEach(() => {
        layout = layoutOf(mockScopedSchema);
      });

      it('places every entity inside the graph with a margin', () => {
        expect(Object.keys(layout.positions)).toEqual(
          expect.arrayContaining(['User', 'Project', 'Pipeline', 'Job', 'Package']),
        );
        Object.values(layout.positions).forEach(({ x, y }) => {
          expect(x).toBeGreaterThanOrEqual(GRAPH_MARGIN_X_PX);
          expect(x).toBeLessThanOrEqual(layout.width - GRAPH_MARGIN_X_PX);
          expect(y).toBeGreaterThanOrEqual(GRAPH_MARGIN_Y_PX);
          expect(y).toBeLessThanOrEqual(layout.height - GRAPH_MARGIN_Y_PX);
        });
      });

      it('puts the other entity of the core beside the project', () => {
        const { Project, User } = layout.positions;

        expect(User.y).toBe(Project.y);
      });

      it('keeps the domains apart', () => {
        const core = domainBox(layout.positions, ['User', 'Project']);
        const ci = domainBox(layout.positions, ['Pipeline', 'Job']);
        const packages = domainBox(layout.positions, ['Package']);

        expect([
          boxesOverlap(core, ci),
          boxesOverlap(core, packages),
          boxesOverlap(ci, packages),
        ]).toEqual([false, false, false]);
      });
    });

    describe('when the schema has no entities', () => {
      it('returns an empty graph', () => {
        expect(layoutOf({ nodes: [], edges: [] })).toEqual({
          positions: {},
          width: GRAPH_MARGIN_X_PX * 2,
          height: GRAPH_MARGIN_Y_PX * 2,
        });
      });
    });

    describe('when the core has five entities', () => {
      let positions;

      beforeEach(() => {
        ({ positions } = layoutOf({
          nodes: ['Project', 'User', 'Group', 'Note', 'Label'].map((name) => node(name, 'core')),
          edges: [],
        }));
      });

      it('leaves the cell under the project free for the scope pill', () => {
        expect(Object.values(positions)).not.toContainEqual({
          x: positions.Project.x,
          y: positions.Project.y + CLUSTER_CELL_HEIGHT_PX,
        });
      });
    });

    describe('when one entity of a domain links to the core', () => {
      let positions;

      beforeEach(() => {
        ({ positions } = layoutOf({
          nodes: [
            node('Project', 'core'),
            node('Alpha', 'a'),
            node('Bravo', 'a'),
            node('Charlie', 'a'),
            node('Delta', 'a'),
          ],
          edges: [edge('LINKS', 'Delta', 'Project')],
        }));
      });

      it('puts that entity nearest the core', () => {
        const distances = ['Alpha', 'Bravo', 'Charlie', 'Delta'].map((name) =>
          distance(positions[name], positions.Project),
        );

        expect(distances[3]).toBe(Math.min(...distances));
        expect(Math.max(...distances)).toBeGreaterThan(distances[3]);
      });
    });

    describe('when the schema has a domain the UI does not list', () => {
      let layout;

      beforeEach(() => {
        layout = layoutOf({
          ...mockScopedSchema,
          nodes: [...mockScopedSchema.nodes, node('Widget', 'brand_new')],
        });
      });

      it('places its entities in a cluster of their own', () => {
        const widget = domainBox(layout.positions, ['Widget']);

        expect(
          [['User', 'Project'], ['Pipeline', 'Job'], ['Package']].map((names) =>
            boxesOverlap(widget, domainBox(layout.positions, names)),
          ),
        ).toEqual([false, false, false]);
      });
    });

    describe('when the other domains have one entity each', () => {
      const ringNames = ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo'];
      let positions;

      const turnsFromTop = (name) => {
        const angle = Math.atan2(
          (positions[name].y - positions.Project.y) / RING_ASPECT_RATIO,
          positions[name].x - positions.Project.x,
        );
        return ((angle + Math.PI / 2) / (2 * Math.PI) + 1) % 1;
      };
      const ringSlots = () => [...ringNames].sort((a, b) => turnsFromTop(a) - turnsFromTop(b));
      const ringGap = (a, b) => {
        const slots = ringSlots();
        const steps = Math.abs(slots.indexOf(a) - slots.indexOf(b));
        return Math.min(steps, slots.length - steps);
      };

      beforeEach(() => {
        ({ positions } = layoutOf({
          nodes: [
            node('Project', 'core'),
            ...ringNames.map((name) => node(name, name.toLowerCase())),
          ],
          edges: [edge('LINKS', 'Alpha', 'Charlie'), edge('LINKS', 'Charlie', 'Delta')],
        }));
      });

      it('places them at evenly spaced angles around the core', () => {
        const ringSteps = ringNames.map((name) => turnsFromTop(name) * ringNames.length);

        ringSteps.forEach((ringStep) => {
          expect(ringStep).toBeCloseTo(Math.round(ringStep), 6);
        });
        expect(new Set(ringSteps.map(Math.round)).size).toBe(ringNames.length);
      });

      it('puts linked domains next to each other on the ring', () => {
        expect([ringGap('Alpha', 'Charlie'), ringGap('Charlie', 'Delta')]).toEqual([1, 1]);
      });
    });
  });
});
