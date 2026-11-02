import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import SchemaDataTab from 'ee/orbit/dashboard/schema/schema_data_tab.vue';
import SchemaEntityCard from 'ee/orbit/dashboard/schema/schema_entity_card.vue';
import SchemaGraphCanvas from 'ee/orbit/dashboard/schema/schema_graph_canvas.vue';
import SchemaGraphViewport from 'ee/orbit/dashboard/schema/schema_graph_viewport.vue';
import SchemaRelationshipCard from 'ee/orbit/dashboard/schema/schema_relationship_card.vue';
import {
  entityPairs,
  entityQuery,
  entityRelationships,
  normalizeSchema,
  relationshipQuery,
  schemaDomains,
} from 'ee/orbit/dashboard/schema/schema_graph';
import { entityLayout } from 'ee/orbit/dashboard/schema/schema_layout';
import { mockScopedSchema } from '../../mock_data';

describe('SchemaDataTab', () => {
  let wrapper;
  let trackEventSpy;
  const focusNode = jest.fn();
  const focusName = jest.fn();
  const { bindInternalEventDocument } = useMockInternalEventsTracking();
  const schema = normalizeSchema(mockScopedSchema);
  const nodesByName = Object.fromEntries(schema.nodes.map((node) => [node.name, node]));

  const createComponent = async (props = {}) => {
    wrapper = shallowMountExtended(SchemaDataTab, {
      propsData: {
        schema,
        graphStats: { pipeline: 1200 },
        initialEntity: null,
        ...props,
      },
      attachTo: document.body,
      stubs: {
        SchemaGraphViewport: stubComponent(SchemaGraphViewport, {
          template: '<div><slot :scale="0.8"></slot></div>',
        }),
        SchemaGraphCanvas: stubComponent(SchemaGraphCanvas, { methods: { focusNode } }),
        SchemaEntityCard: stubComponent(SchemaEntityCard, { methods: { focusName } }),
        SchemaRelationshipCard: stubComponent(SchemaRelationshipCard, { methods: { focusName } }),
      },
    });
    await nextTick();
    ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
  };

  const findViewport = () => wrapper.findComponent(SchemaGraphViewport);
  const findCanvas = () => wrapper.findComponent(SchemaGraphCanvas);
  const findPanel = () => wrapper.findByTestId('schema-graph-panel');
  const findEntityCard = () => wrapper.findComponent(SchemaEntityCard);
  const findRelationshipCard = () => wrapper.findComponent(SchemaRelationshipCard);
  const findArea = (label) =>
    wrapper.findAllByTestId('schema-area').wrappers.find((area) => area.text().startsWith(label));
  const findHint = () =>
    wrapper.findByText('Hover over or select an entity to see its relationships.');
  const emitFromCanvas = async (event, payload) => {
    findCanvas().vm.$emit(event, payload);
    await nextTick();
  };
  const expectTracked = (label) =>
    expect(trackEventSpy).toHaveBeenCalledWith('click_orbit_schema_item', { label }, undefined);

  describe('when nothing is selected', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('shows the title and how to start', () => {
      expect(wrapper.find('h2').text()).toBe('How your data connects');
      expect(wrapper.text()).toContain(
        'Select an entity to see its properties, its relationships, and a query to start from.',
      );
      expect(findHint().exists()).toBe(true);
    });

    it('lists the areas with their entity counts', () => {
      expect(wrapper.findAllByTestId('schema-area').wrappers.map((area) => area.text())).toEqual([
        expect.stringMatching(/Core\s+2/),
        expect.stringMatching(/Pipelines\s+2/),
        expect.stringMatching(/Packages\s+1/),
      ]);
    });

    it('sizes the viewport to the layout and draws the graph at its scale', () => {
      const layout = entityLayout(schemaDomains(schema), entityPairs(schema));

      expect(findViewport().props()).toEqual({ width: layout.width, height: layout.height });
      expect(findCanvas().props()).toMatchObject({ positions: layout.positions, scale: 0.8 });
    });

    it('draws the graph with nothing in focus and no card', () => {
      expect(findCanvas().props()).toMatchObject({
        pairs: entityPairs(schema),
        focusedEntity: null,
        selectedEntity: null,
        selectedRelationship: null,
        highlightedDomain: null,
      });
      expect(
        findCanvas()
          .props('entities')
          .map(({ name }) => name),
      ).toEqual(['User', 'Project', 'Pipeline', 'Job', 'Package']);
      expect([...findCanvas().props('restingPairKeys')]).toEqual([
        'Pipeline|User',
        'Job|Pipeline',
        'Pipeline|Pipeline',
        'Package|Project',
      ]);
      expect(findEntityCard().exists()).toBe(false);
      expect(findRelationshipCard().exists()).toBe(false);
    });

    describe('and the user highlights an area', () => {
      beforeEach(async () => {
        await findArea('Pipelines').trigger('click');
      });

      it('highlights it in the graph and marks it as pressed', () => {
        expect(findCanvas().props('highlightedDomain')).toBe('ci');
        expect(findArea('Pipelines').attributes('aria-pressed')).toBe('true');
      });

      describe('and selects it again', () => {
        beforeEach(async () => {
          await findArea('Pipelines').trigger('click');
        });

        it('removes the highlight', () => {
          expect(findCanvas().props('highlightedDomain')).toBe(null);
          expect(findArea('Pipelines').attributes('aria-pressed')).toBe('false');
        });
      });
    });

    describe('and the user points at an entity', () => {
      beforeEach(async () => {
        await emitFromCanvas('hover-entity', 'Pipeline');
      });

      it('puts it in focus and opens no card', () => {
        expect(findCanvas().props('focusedEntity')).toBe('Pipeline');
        expect(findEntityCard().exists()).toBe(false);
      });

      describe('and moves away', () => {
        beforeEach(async () => {
          await emitFromCanvas('hover-entity', null);
        });

        it('clears the focus', () => {
          expect(findCanvas().props('focusedEntity')).toBe(null);
        });
      });
    });

    describe('and the user selects an entity in the graph', () => {
      beforeEach(async () => {
        await emitFromCanvas('select-entity', 'Pipeline');
      });

      it('opens its card with its details, count in the graph, and query', () => {
        expect(findEntityCard().props()).toMatchObject({
          entity: { name: 'Pipeline', domain: 'ci' },
          node: nodesByName.Pipeline,
          domainLabel: 'Pipelines',
          relationships: entityRelationships(schema, 'Pipeline'),
          itemCount: 1200,
          query: entityQuery(nodesByName.Pipeline),
        });
        expect(findHint().exists()).toBe(false);
      });

      it('keeps it in focus and leaves the keyboard focus in the graph', () => {
        expect(focusName).not.toHaveBeenCalled();
        expect(findCanvas().props()).toMatchObject({
          focusedEntity: 'Pipeline',
          selectedEntity: 'Pipeline',
        });
      });

      it('tracks the selection from the graph', () => {
        expectTracked('graph');
      });

      describe('and points at another entity', () => {
        beforeEach(async () => {
          await emitFromCanvas('hover-entity', 'Package');
        });

        it('keeps the selected entity in focus', () => {
          expect(findCanvas().props('focusedEntity')).toBe('Pipeline');
        });
      });

      describe('and selects it again', () => {
        beforeEach(async () => {
          await emitFromCanvas('select-entity', 'Pipeline');
        });

        it('does not track it again', () => {
          expect(trackEventSpy).toHaveBeenCalledTimes(1);
        });
      });

      describe('and selects a connected entity in the card', () => {
        beforeEach(async () => {
          findEntityCard().vm.$emit('select-entity', 'User');
          await nextTick();
        });

        it('opens that entity and moves the focus to its name', () => {
          expect(findEntityCard().props('entity')).toMatchObject({ name: 'User' });
          expect(focusName).toHaveBeenCalledTimes(1);
        });

        it('tracks the selection from the card', () => {
          expectTracked('details');
        });
      });

      describe('and selects a relationship in the card', () => {
        beforeEach(async () => {
          findEntityCard().vm.$emit('select-relationship', 'AUTO_CANCELED_BY');
          await nextTick();
        });

        it('opens the relationship card with every pair it joins and its query', () => {
          expect(findEntityCard().exists()).toBe(false);
          expect(findRelationshipCard().props()).toMatchObject({
            relationship: {
              name: 'AUTO_CANCELED_BY',
              description: 'Canceled by a newer pipeline',
              variants: [
                { source: 'Pipeline', target: 'Pipeline' },
                { source: 'Job', target: 'Pipeline' },
              ],
            },
            query: relationshipQuery(
              { name: 'AUTO_CANCELED_BY', source: 'Pipeline', target: 'Pipeline' },
              nodesByName,
            ),
          });
        });

        it('highlights the relationship in the graph with no entity in focus', () => {
          expect(findCanvas().props()).toMatchObject({
            selectedRelationship: 'AUTO_CANCELED_BY',
            focusedEntity: null,
            selectedEntity: null,
          });
        });

        describe('and the user selects an entity of a pair', () => {
          beforeEach(async () => {
            findRelationshipCard().vm.$emit('select-entity', 'Job');
            await nextTick();
          });

          it('opens that entity and tracks it from the relationship card', () => {
            expect(findEntityCard().props('entity')).toMatchObject({ name: 'Job' });
            expectTracked('relationship_card');
          });
        });

        describe('and closes the relationship card', () => {
          beforeEach(async () => {
            findRelationshipCard().vm.$emit('close');
            await nextTick();
          });

          it('moves the focus back to the entity that opened it', () => {
            expect(findRelationshipCard().exists()).toBe(false);
            expect(focusNode).toHaveBeenCalledWith('Pipeline');
          });
        });
      });

      describe('and closes the card', () => {
        beforeEach(async () => {
          findEntityCard().vm.$emit('close');
          await nextTick();
        });

        it('clears the selection and moves the focus back to the entity in the graph', () => {
          expect(findEntityCard().exists()).toBe(false);
          expect(findCanvas().props('selectedEntity')).toBe(null);
          expect(focusNode).toHaveBeenCalledWith('Pipeline');
        });
      });

      describe.each`
        event               | payload
        ${'show-instances'} | ${{ entityType: 'Pipeline' }}
        ${'open-query'}     | ${'MATCH (p:Pipeline)\nWHERE p.id IS NOT NULL\nRETURN p.id\nLIMIT 25'}
      `('and the card emits $event', ({ event, payload }) => {
        beforeEach(() => {
          findEntityCard().vm.$emit(event, payload);
        });

        it('passes it on', () => {
          expect(wrapper.emitted(event)).toEqual([[payload]]);
        });
      });
    });

    describe('and the user selects a relationship in the graph', () => {
      beforeEach(async () => {
        await emitFromCanvas('select-relationship', 'TRIGGERED');
      });

      it('opens the relationship card', () => {
        expect(findRelationshipCard().props('relationship')).toMatchObject({ name: 'TRIGGERED' });
      });

      describe('and closes it', () => {
        beforeEach(async () => {
          findRelationshipCard().vm.$emit('close');
          await nextTick();
        });

        it('moves the focus to the graph', () => {
          expect(focusNode).not.toHaveBeenCalled();
          expect(document.activeElement).toBe(findPanel().element);
        });
      });
    });
  });

  describe('when the URL names an entity', () => {
    beforeEach(async () => {
      await createComponent({ initialEntity: 'pipeline' });
    });

    it('opens its card', () => {
      expect(findEntityCard().props('entity')).toMatchObject({ name: 'Pipeline' });
    });

    it('does not track the selection from the URL', () => {
      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    describe('and the URL changes to another entity', () => {
      beforeEach(async () => {
        await wrapper.setProps({ initialEntity: 'Job' });
      });

      it('opens the card of that entity', () => {
        expect(findEntityCard().props('entity')).toMatchObject({ name: 'Job' });
      });
    });
  });
});
