import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SchemaGraphCanvas from 'ee/orbit/dashboard/schema/schema_graph_canvas.vue';
import {
  entityPairs,
  restingPairKeys,
  schemaDomains,
} from 'ee/orbit/dashboard/schema/schema_graph';
import { entityLayout } from 'ee/orbit/dashboard/schema/schema_layout';
import { mockScopedSchema } from '../../mock_data';

describe('SchemaGraphCanvas', () => {
  let wrapper;

  const domains = schemaDomains(mockScopedSchema);
  const entities = domains.flatMap((domain) => domain.entities);
  const pairs = entityPairs(mockScopedSchema);
  const domainByEntity = Object.fromEntries(
    mockScopedSchema.nodes.map((node) => [node.name, node.domain]),
  );
  const defaultProps = {
    entities,
    positions: entityLayout(domains, pairs).positions,
    scale: 1,
    pairs,
    restingPairKeys: restingPairKeys(pairs, domainByEntity),
    focusedEntity: null,
    selectedEntity: null,
    selectedRelationship: null,
    highlightedDomain: null,
  };

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(SchemaGraphCanvas, {
      propsData: { ...defaultProps, ...props },
      attachTo: document.body,
    });
  };

  const findEdges = () => wrapper.findAllByTestId('schema-edge').wrappers;
  const pairKeys = (edges) => edges.map((edge) => edge.attributes('data-pair'));
  const visiblePairs = () =>
    pairKeys(findEdges().filter((edge) => !edge.classes('orbit-schema-edge-hidden')));
  const highlightedPairs = () =>
    pairKeys(findEdges().filter((edge) => edge.classes('orbit-schema-edge-highlighted')));
  const findNode = (name) =>
    wrapper.findAllByTestId('schema-node').wrappers.find((node) => node.text() === name);
  const dimmedNodes = () =>
    wrapper
      .findAllByTestId('schema-node')
      .wrappers.filter((node) => node.classes('gl-opacity-3'))
      .map((node) => node.text());
  const labelTexts = () =>
    wrapper.findAllByTestId('schema-edge-label').wrappers.map((label) => label.text());
  const findScopePill = () => wrapper.findByTestId('schema-scope-pill');
  const withEdges = (...edges) =>
    entityPairs({ ...mockScopedSchema, edges: [...mockScopedSchema.edges, ...edges] });

  describe('when nothing is in focus', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows every entity, with none dimmed', () => {
      expect(wrapper.findAllByTestId('schema-node')).toHaveLength(entities.length);
      expect(dimmedNodes()).toEqual([]);
    });

    it('draws no line for a relationship from an entity to itself', () => {
      expect(pairKeys(findEdges())).not.toContain('Pipeline|Pipeline');
    });

    it('draws the resting pairs only, with no names', () => {
      expect(visiblePairs()).toEqual(['Package|Project', 'Pipeline|User', 'Job|Pipeline']);
      expect(highlightedPairs()).toEqual([]);
      expect(labelTexts()).toEqual([]);
    });

    describe('and the user points at an entity', () => {
      beforeEach(async () => {
        await findNode('Pipeline').trigger('mouseenter');
      });

      it('asks to focus it', () => {
        expect(wrapper.emitted('hover-entity')).toEqual([['Pipeline']]);
      });

      describe('and moves away', () => {
        beforeEach(async () => {
          await findNode('Pipeline').trigger('mouseleave');
        });

        it('asks to clear the focus', () => {
          expect(wrapper.emitted('hover-entity')).toEqual([['Pipeline'], [null]]);
        });
      });
    });

    describe('and an entity has keyboard focus', () => {
      beforeEach(async () => {
        await findNode('Pipeline').trigger('focus');
      });

      describe('and the pointer passes over another entity', () => {
        beforeEach(async () => {
          await findNode('Job').trigger('mouseenter');
          await findNode('Job').trigger('mouseleave');
        });

        it('asks to focus the entity with keyboard focus again', () => {
          expect(wrapper.emitted('hover-entity')).toEqual([['Pipeline'], ['Job'], ['Pipeline']]);
        });
      });

      describe('and the entity loses keyboard focus', () => {
        beforeEach(async () => {
          await findNode('Pipeline').trigger('blur');
        });

        it('asks to clear the focus', () => {
          expect(wrapper.emitted('hover-entity')).toEqual([['Pipeline'], [null]]);
        });
      });
    });

    describe('and the user selects an entity', () => {
      beforeEach(async () => {
        await findNode('Job').trigger('click');
      });

      it('emits it', () => {
        expect(wrapper.emitted('select-entity')).toEqual([['Job']]);
      });
    });
  });

  describe('when an entity is in focus', () => {
    beforeEach(() => {
      createComponent({ focusedEntity: 'Pipeline' });
    });

    it('draws only its pairs, its project pair too, and names each one', () => {
      expect(visiblePairs()).toEqual(['Pipeline|Project', 'Pipeline|User', 'Job|Pipeline']);
      expect(highlightedPairs()).toEqual(visiblePairs());
      expect(labelTexts()).toHaveLength(3);
      expect(labelTexts()).toEqual(
        expect.arrayContaining(['IN_PROJECT', 'TRIGGERED', 'HAS_JOB +1 more']),
      );
    });

    it('dims the entities it does not connect to', () => {
      expect(dimmedNodes()).toEqual(['Package']);
    });

    describe('and the user selects a relationship name', () => {
      beforeEach(async () => {
        await wrapper
          .findAllByTestId('schema-edge-label')
          .wrappers.find((label) => label.text() === 'TRIGGERED')
          .trigger('click');
      });

      it('emits the relationship', () => {
        expect(wrapper.emitted('select-relationship')).toEqual([['TRIGGERED']]);
      });
    });
  });

  describe('when the project is in focus', () => {
    beforeEach(() => {
      createComponent({ focusedEntity: 'Project' });
    });

    it('draws every pair of the project, with one count and no names', () => {
      expect(highlightedPairs()).toEqual(['Pipeline|Project', 'Job|Project', 'Package|Project']);
      expect(labelTexts()).toEqual([]);
      expect(findScopePill().text()).toBe('IN_PROJECT · 3 entity types');
    });

    describe('and the user selects the count', () => {
      beforeEach(async () => {
        await findScopePill().trigger('click');
      });

      it('emits the project relationship', () => {
        expect(wrapper.emitted('select-relationship')).toEqual([['IN_PROJECT']]);
      });
    });
  });

  describe('when the project is in focus and a pair has another relationship too', () => {
    beforeEach(() => {
      createComponent({
        focusedEntity: 'Project',
        pairs: withEdges({
          name: 'SOURCE_PROJECT',
          variants: [{ source_type: 'Pipeline', target_type: 'Project' }],
        }),
      });
    });

    it('names only the other relationship and counts the pair in the project', () => {
      expect(labelTexts()).toEqual(['SOURCE_PROJECT']);
      expect(findScopePill().text()).toBe('IN_PROJECT · 3 entity types');
    });
  });

  describe('when the project is in focus and a pair has no project relationship', () => {
    beforeEach(() => {
      createComponent({
        focusedEntity: 'Project',
        pairs: withEdges({
          name: 'MEMBER_OF',
          variants: [{ source_type: 'User', target_type: 'Project' }],
        }),
      });
    });

    it('names that relationship and leaves the pair out of the count', () => {
      expect(labelTexts()).toEqual(['MEMBER_OF']);
      expect(findScopePill().text()).toBe('IN_PROJECT · 3 entity types');
    });
  });

  describe('when a relationship from an entity to itself is selected', () => {
    beforeEach(() => {
      createComponent({
        selectedRelationship: 'RETRIED_AS',
        pairs: withEdges({
          name: 'RETRIED_AS',
          variants: [{ source_type: 'Job', target_type: 'Job' }],
        }),
      });
    });

    it('draws no line and keeps the entity in focus', () => {
      expect(visiblePairs()).toEqual([]);
      expect(dimmedNodes()).toEqual(['User', 'Project', 'Pipeline', 'Package']);
    });
  });

  describe('when a relationship is selected', () => {
    beforeEach(() => {
      createComponent({ selectedRelationship: 'HAS_JOB' });
    });

    it('draws only the pairs it joins, with no names', () => {
      expect(visiblePairs()).toEqual(['Job|Pipeline']);
      expect(labelTexts()).toEqual([]);
    });

    it('dims the entities it does not join', () => {
      expect(dimmedNodes()).toEqual(['User', 'Project', 'Package']);
    });
  });

  describe('when an area is highlighted', () => {
    beforeEach(() => {
      createComponent({ highlightedDomain: 'ci' });
    });

    it('dims the entities of the other areas', () => {
      expect(dimmedNodes()).toEqual(['User', 'Project', 'Package']);
    });
  });

  describe('when the selected entity is shown', () => {
    beforeEach(() => {
      createComponent({ focusedEntity: 'Job', selectedEntity: 'Job' });
    });

    it('marks it as pressed', () => {
      expect(findNode('Job').attributes('aria-pressed')).toBe('true');
      expect(findNode('Pipeline').attributes('aria-pressed')).toBe('false');
    });
  });
});
