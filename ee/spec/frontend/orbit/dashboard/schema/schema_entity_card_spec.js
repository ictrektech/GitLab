import { mountExtended } from 'helpers/vue_test_utils_helper';
import SchemaEntityCard from 'ee/orbit/dashboard/schema/schema_entity_card.vue';
import SchemaQuerySnippet from 'ee/orbit/dashboard/schema/schema_query_snippet.vue';
import { entityRelationships, schemaDomains } from 'ee/orbit/dashboard/schema/schema_graph';
import { mockScopedSchema } from '../../mock_data';

describe('SchemaEntityCard', () => {
  let wrapper;

  const entitiesByName = Object.fromEntries(
    schemaDomains(mockScopedSchema)
      .flatMap((domain) => domain.entities)
      .map((entity) => [entity.name, entity]),
  );
  const nodeNamed = (name) => mockScopedSchema.nodes.find((node) => node.name === name);
  const query = 'MATCH (p:Pipeline)\nWHERE p.id IS NOT NULL\nRETURN p.id, p.status\nLIMIT 25';

  const createComponent = ({ name = 'Pipeline', ...props } = {}) => {
    wrapper = mountExtended(SchemaEntityCard, {
      propsData: {
        entity: entitiesByName[name],
        node: nodeNamed(name),
        domainLabel: 'Pipelines',
        relationships: entityRelationships(mockScopedSchema, name),
        entitiesByName,
        itemCount: 1200,
        query,
        ...props,
      },
    });
  };

  const findConnectedRows = () =>
    wrapper.findAllByTestId('schema-connected-entity').wrappers.map((row) => row.text());
  const findButtonByText = (text) =>
    wrapper.findAll('button').wrappers.find((button) => button.text() === text);
  const findQuerySnippet = () => wrapper.findComponent(SchemaQuerySnippet);
  const findSectionToggle = (name) => wrapper.findByRole('button', { name });

  describe('when it shows an entity', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows its name, area, relationship count, description, and count in the graph', () => {
      expect(wrapper.findByTestId('schema-entity-name').text()).toBe('Pipeline');
      expect(wrapper.text()).toContain('Pipelines · 5 relationships');
      expect(wrapper.text()).toContain('A CI/CD pipeline.');
      expect(wrapper.text()).toContain('1,200 in your graph');
    });

    it('lists each connected entity with its direction and relationship names', () => {
      expect(findConnectedRows()).toEqual([
        expect.stringMatching(/Project\s+IN_PROJECT/),
        expect.stringMatching(/Job\s+HAS_JOB/),
        expect.stringMatching(/Pipeline\s+AUTO_CANCELED_BY/),
        expect.stringMatching(/User\s+TRIGGERED/),
        expect.stringMatching(/Job\s+AUTO_CANCELED_BY/),
      ]);
      expect(wrapper.text()).toContain('Connected entities (5)');
    });

    it('opens with the properties closed and the connected entities open', () => {
      expect(findSectionToggle('Properties (3)').attributes('aria-expanded')).toBe('false');
      expect(findSectionToggle('Connected entities (5)').attributes('aria-expanded')).toBe('true');
    });

    it('lists its properties with their type and values', () => {
      expect(wrapper.text()).toContain('Properties (3)');
      expect(wrapper.findAllByTestId('schema-property').wrappers.map((row) => row.text())).toEqual([
        expect.stringMatching(/id\s+Int/),
        expect.stringMatching(/status\s+Enum\s+created, running, success/),
        expect.stringMatching(/ref\s+String\s+Can be empty/),
      ]);
    });

    it('shows the query', () => {
      expect(findQuerySnippet().props('query')).toBe(query);
    });

    describe.each`
      action                      | trigger                                               | event                    | payload
      ${'selects an entity'}      | ${() => findButtonByText('User')}                     | ${'select-entity'}       | ${'User'}
      ${'selects a relationship'} | ${() => findButtonByText('TRIGGERED')}                | ${'select-relationship'} | ${'TRIGGERED'}
      ${'explores it'}            | ${() => wrapper.findByTestId('schema-explore')}       | ${'show-instances'}      | ${{ entityType: 'Pipeline' }}
      ${'closes the card'}        | ${() => wrapper.findByTestId('schema-details-close')} | ${'close'}               | ${undefined}
    `('when the user $action', ({ trigger, event, payload }) => {
      beforeEach(async () => {
        await trigger().trigger('click');
      });

      it(`emits ${event}`, () => {
        expect(wrapper.emitted(event)).toEqual([payload === undefined ? [] : [payload]]);
      });
    });

    describe('when the user opens the query', () => {
      beforeEach(() => {
        findQuerySnippet().vm.$emit('open-query', query);
      });

      it('emits the query', () => {
        expect(wrapper.emitted('open-query')).toEqual([[query]]);
      });
    });
  });

  describe('when it shows the project', () => {
    beforeEach(() => {
      createComponent({ name: 'Project', domainLabel: 'Core' });
    });

    it('counts the entity types in a project in one row, with the list closed', () => {
      expect(wrapper.findByTestId('schema-scoped-entities-toggle').text()).toBe(
        '3 entity types belong to it',
      );
      expect(
        wrapper.findByTestId('schema-scoped-entities-toggle').attributes('aria-expanded'),
      ).toBe('false');
      expect(wrapper.findByTestId('schema-scoped-entities').exists()).toBe(false);
      expect(findConnectedRows()).toEqual([]);
      expect(wrapper.text()).toContain('Connected entities (1)');
    });

    describe('and the user opens the list', () => {
      beforeEach(async () => {
        await wrapper.findByTestId('schema-scoped-entities-toggle').trigger('click');
      });

      it('lists each entity type in a project', () => {
        expect(wrapper.findByTestId('schema-scoped-entities').text()).toMatch(
          /Pipeline\s+Job\s+Package/,
        );
        expect(
          wrapper.findByTestId('schema-scoped-entities-toggle').attributes('aria-expanded'),
        ).toBe('true');
      });

      describe('and selects one', () => {
        beforeEach(async () => {
          await findButtonByText('Package').trigger('click');
        });

        it('emits the entity', () => {
          expect(wrapper.emitted('select-entity')).toEqual([['Package']]);
        });
      });
    });

    describe('and the user selects the relationship name', () => {
      beforeEach(async () => {
        await wrapper.findByTestId('schema-scope-relationship').trigger('click');
      });

      it('emits the project relationship', () => {
        expect(wrapper.emitted('select-relationship')).toEqual([['IN_PROJECT']]);
      });
    });
  });

  describe('when the graph has none of the entity', () => {
    beforeEach(() => {
      createComponent({ itemCount: 0 });
    });

    it('shows the count and no explore button', () => {
      expect(wrapper.text()).toContain('0 in your graph');
      expect(wrapper.findByTestId('schema-explore').exists()).toBe(false);
    });
  });

  describe('when the count is unknown', () => {
    beforeEach(() => {
      createComponent({ itemCount: null });
    });

    it('shows the explore button and no count', () => {
      expect(wrapper.text()).not.toContain('in your graph');
      expect(wrapper.findByTestId('schema-explore').exists()).toBe(true);
    });
  });

  describe('when queries are off', () => {
    beforeEach(() => {
      createComponent({ query: null });
    });

    it('shows no query', () => {
      expect(findQuerySnippet().exists()).toBe(false);
    });
  });
});
