import { mountExtended } from 'helpers/vue_test_utils_helper';
import SchemaRelationshipCard from 'ee/orbit/dashboard/schema/schema_relationship_card.vue';
import SchemaQuerySnippet from 'ee/orbit/dashboard/schema/schema_query_snippet.vue';
import { schemaDomains } from 'ee/orbit/dashboard/schema/schema_graph';
import { mockScopedSchema } from '../../mock_data';

describe('SchemaRelationshipCard', () => {
  let wrapper;

  const entitiesByName = Object.fromEntries(
    schemaDomains(mockScopedSchema)
      .flatMap((domain) => domain.entities)
      .map((entity) => [entity.name, entity]),
  );
  const relationship = {
    name: 'AUTO_CANCELED_BY',
    description: 'Canceled by a newer pipeline',
    variants: [
      { source: 'Pipeline', target: 'Pipeline' },
      { source: 'Job', target: 'Pipeline' },
    ],
  };
  const query =
    'MATCH (p:Pipeline)-[:AUTO_CANCELED_BY]->(p2:Pipeline)\nWHERE p.id IS NOT NULL\nRETURN p.id, p2.id\nLIMIT 25';

  const createComponent = (props = {}) => {
    wrapper = mountExtended(SchemaRelationshipCard, {
      propsData: { relationship, entitiesByName, query, ...props },
    });
  };

  const findPairs = () =>
    wrapper.findAllByTestId('schema-relationship-pair').wrappers.map((pair) => pair.text());
  const findQuerySnippet = () => wrapper.findComponent(SchemaQuerySnippet);

  describe('when it shows a relationship', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows its name, description, and every pair it joins', () => {
      expect(wrapper.findByTestId('schema-relationship-name').text()).toBe('AUTO_CANCELED_BY');
      expect(wrapper.text()).toContain('Canceled by a newer pipeline');
      expect(wrapper.text()).toContain('Connects 2 pairs');
      expect(findPairs()).toEqual([
        expect.stringMatching(/Pipeline\s+Pipeline/),
        expect.stringMatching(/Job\s+Pipeline/),
      ]);
    });

    it('shows the query', () => {
      expect(findQuerySnippet().props('query')).toBe(query);
    });

    describe('and the user selects an entity of a pair', () => {
      beforeEach(async () => {
        await wrapper
          .findAllByTestId('schema-relationship-pair')
          .wrappers.find((pair) => pair.text().startsWith('Job'))
          .findAll('button')
          .wrappers.find((button) => button.text() === 'Job')
          .trigger('click');
      });

      it('emits the entity', () => {
        expect(wrapper.emitted('select-entity')).toEqual([['Job']]);
      });
    });

    describe('and the user closes the card', () => {
      beforeEach(async () => {
        await wrapper.findByTestId('schema-details-close').trigger('click');
      });

      it('emits close', () => {
        expect(wrapper.emitted('close')).toEqual([[]]);
      });
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
