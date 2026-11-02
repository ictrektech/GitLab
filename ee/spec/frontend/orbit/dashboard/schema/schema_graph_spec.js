import { DEFAULT_NODE_COLOR } from 'ee/orbit/constants';
import {
  RELATIONSHIP_DIRECTION,
  connectedEntities,
  edgeArrowheads,
  edgeSegment,
  entityPairs,
  entityQuery,
  entityRelationships,
  filterDomains,
  groupByEntity,
  itemCount,
  normalizeSchema,
  placeEdgeLabels,
  relationshipQuery,
  restingPairKeys,
  schemaDomains,
} from 'ee/orbit/dashboard/schema/schema_graph';
import { mockExpandedSchema, mockScopedSchema } from '../../mock_data';

describe('schema_graph', () => {
  const nodesByName = Object.fromEntries(mockScopedSchema.nodes.map((node) => [node.name, node]));
  const domainByEntity = Object.fromEntries(
    mockScopedSchema.nodes.map((node) => [node.name, node.domain]),
  );

  describe('filterDomains', () => {
    const domains = schemaDomains(mockExpandedSchema);
    const names = (filtered) => filtered.map((d) => [d.key, d.entities.map((e) => e.name)]);

    it('keeps every domain for an empty or blank search', () => {
      expect(filterDomains(domains, '  ')).toBe(domains);
    });

    it('keeps matching entities, ignores case, and drops empty domains', () => {
      expect(names(filterDomains(domains, ' JOB '))).toEqual([['ci', ['Job']]]);
    });

    it('keeps every entity of a domain whose label matches', () => {
      expect(names(filterDomains(domains, 'pipelines'))).toEqual([
        ['ci', ['Job', 'Pipeline', 'Stage']],
      ]);
    });
  });

  describe('itemCount', () => {
    it.each`
      itemCounts            | expected
      ${{ pipeline: 1200 }} | ${1200}
      ${{ pipeline: 0 }}    | ${0}
      ${{}}                 | ${null}
      ${null}               | ${null}
    `('finds Pipeline in $itemCounts as $expected', ({ itemCounts, expected }) => {
      expect(itemCount(itemCounts, 'Pipeline')).toBe(expected);
    });
  });

  describe('schemaDomains', () => {
    it('orders the domains and names them with the domain labels', () => {
      expect(schemaDomains(mockExpandedSchema).map((domain) => [domain.key, domain.label])).toEqual(
        [
          ['core', 'Core'],
          ['ci', 'Pipelines'],
        ],
      );
    });

    it('opens each domain on its main entity, with its color', () => {
      expect(schemaDomains(mockExpandedSchema)).toMatchObject([
        { entryEntity: 'Project', color: '#06b6d4', icon: 'project' },
        { entryEntity: 'Pipeline', color: '#f59e0b', icon: 'pipeline' },
      ]);
    });

    it('puts unknown domains last, sorted, named by their key', () => {
      const schema = {
        nodes: [
          { name: 'Zeta', domain: 'zeta' },
          { name: 'Alpha', domain: 'alpha' },
          { name: 'AgentSession', domain: 'agents' },
        ],
      };

      expect(schemaDomains(schema).map((domain) => [domain.label, domain.entryEntity])).toEqual([
        ['AI agents', 'AgentSession'],
        ['alpha', 'Alpha'],
        ['zeta', 'Zeta'],
      ]);
    });

    it('returns no domains for a schema without nodes', () => {
      expect(schemaDomains(normalizeSchema({}))).toEqual([]);
    });

    it('gives an entity without a style or a known icon the default color and no icon', () => {
      const [domain] = schemaDomains({ nodes: [{ name: 'Mystery', domain: 'other' }] });

      expect(domain.entities).toEqual([
        { name: 'Mystery', domain: 'other', icon: null, color: DEFAULT_NODE_COLOR },
      ]);
    });
  });

  describe('entityRelationships', () => {
    it('splits relationships by direction', () => {
      expect(entityRelationships(mockExpandedSchema, 'Pipeline')).toEqual({
        outgoing: [{ edge: 'CONTAINS', description: 'Containment relationship', entity: 'Stage' }],
        incoming: [{ edge: 'AUTHORED', description: 'Authorship relationship', entity: 'User' }],
      });
    });

    it('counts a self relationship as outgoing only', () => {
      const schema = {
        nodes: [{ name: 'Issue' }],
        edges: [{ name: 'MENTIONS', variants: [{ source_type: 'Issue', target_type: 'Issue' }] }],
      };

      expect(entityRelationships(schema, 'Issue')).toEqual({
        outgoing: [{ edge: 'MENTIONS', description: undefined, entity: 'Issue' }],
        incoming: [],
      });
    });

    it('drops relationships to entities that are not schema nodes', () => {
      const schema = {
        ...mockExpandedSchema,
        edges: [
          ...mockExpandedSchema.edges,
          { name: 'USES', variants: [{ source_type: 'Pipeline', target_type: 'Unknown' }] },
          { name: 'OWNS', variants: [{ source_type: 'Ghost', target_type: 'Pipeline' }] },
        ],
      };

      expect(entityRelationships(schema, 'Pipeline')).toEqual(
        entityRelationships(mockExpandedSchema, 'Pipeline'),
      );
    });
  });

  it('groups relationships by the other entity and drops repeated names', () => {
    const groups = groupByEntity([
      { entity: 'User', edge: 'AUTHORED', description: 'a' },
      { entity: 'User', edge: 'MERGED', description: 'm' },
      { entity: 'User', edge: 'AUTHORED', description: 'a' },
    ]);

    expect(groups).toEqual([
      {
        entity: 'User',
        edges: [
          { name: 'AUTHORED', description: 'a' },
          { name: 'MERGED', description: 'm' },
        ],
      },
    ]);
  });

  describe('connectedEntities', () => {
    describe('for an entity in a project', () => {
      it('lists the entities it points to, then the entities that point to it', () => {
        const relationships = entityRelationships(mockScopedSchema, 'Pipeline');

        expect(connectedEntities(relationships, 'Pipeline')).toEqual({
          rows: [
            {
              entity: 'Project',
              direction: RELATIONSHIP_DIRECTION.OUTGOING,
              edges: [{ name: 'IN_PROJECT', description: 'Project association for entities' }],
            },
            {
              entity: 'Job',
              direction: RELATIONSHIP_DIRECTION.OUTGOING,
              edges: [{ name: 'HAS_JOB', description: 'Pipeline contains a job' }],
            },
            {
              entity: 'Pipeline',
              direction: RELATIONSHIP_DIRECTION.OUTGOING,
              edges: [{ name: 'AUTO_CANCELED_BY', description: 'Canceled by a newer pipeline' }],
            },
            {
              entity: 'User',
              direction: RELATIONSHIP_DIRECTION.INCOMING,
              edges: [{ name: 'TRIGGERED', description: 'User who triggered a pipeline' }],
            },
            {
              entity: 'Job',
              direction: RELATIONSHIP_DIRECTION.INCOMING,
              edges: [{ name: 'AUTO_CANCELED_BY', description: 'Canceled by a newer pipeline' }],
            },
          ],
          scopedEntities: [],
        });
      });
    });

    describe('for the project', () => {
      it('counts the entities in it and lists no rows', () => {
        const relationships = entityRelationships(mockScopedSchema, 'Project');

        expect(connectedEntities(relationships, 'Project')).toEqual({
          rows: [],
          scopedEntities: ['Pipeline', 'Job', 'Package'],
        });
      });
    });
  });

  describe('entityPairs', () => {
    it('joins both directions of two entities in one pair and keeps self relationships', () => {
      expect(entityPairs(mockScopedSchema)).toEqual([
        {
          key: 'Pipeline|Project',
          first: 'Pipeline',
          second: 'Project',
          relationships: [{ name: 'IN_PROJECT', source: 'Pipeline', target: 'Project' }],
        },
        {
          key: 'Job|Project',
          first: 'Job',
          second: 'Project',
          relationships: [{ name: 'IN_PROJECT', source: 'Job', target: 'Project' }],
        },
        {
          key: 'Package|Project',
          first: 'Package',
          second: 'Project',
          relationships: [{ name: 'IN_PROJECT', source: 'Package', target: 'Project' }],
        },
        {
          key: 'Pipeline|User',
          first: 'Pipeline',
          second: 'User',
          relationships: [{ name: 'TRIGGERED', source: 'User', target: 'Pipeline' }],
        },
        {
          key: 'Job|Pipeline',
          first: 'Job',
          second: 'Pipeline',
          relationships: [
            { name: 'HAS_JOB', source: 'Pipeline', target: 'Job' },
            { name: 'AUTO_CANCELED_BY', source: 'Job', target: 'Pipeline' },
          ],
        },
        {
          key: 'Pipeline|Pipeline',
          first: 'Pipeline',
          second: 'Pipeline',
          relationships: [{ name: 'AUTO_CANCELED_BY', source: 'Pipeline', target: 'Pipeline' }],
        },
      ]);
    });
  });

  describe('restingPairKeys', () => {
    it('keeps every pair, and one project pair only for areas with no other line to the core area', () => {
      expect([...restingPairKeys(entityPairs(mockScopedSchema), domainByEntity)]).toEqual([
        'Pipeline|User',
        'Job|Pipeline',
        'Pipeline|Pipeline',
        'Package|Project',
      ]);
    });
  });

  describe('placeEdgeLabels', () => {
    const label = (key) => ({
      key,
      segment: { x1: 0, y1: 0, x2: 100, y2: 0 },
      width: 20,
      height: 10,
    });
    const centers = (placed) => placed.map(({ key, box }) => [key, box.x, box.y]);

    describe('when the middle of the line is free', () => {
      it('puts the label in the middle', () => {
        expect(centers(placeEdgeLabels([label('a')], []))).toEqual([['a', 50, 0]]);
      });
    });

    describe('when a node or an earlier label covers the middle', () => {
      it('moves the label along the line to the next free spot', () => {
        const node = { left: 45, right: 55, top: -5, bottom: 5 };

        expect(centers(placeEdgeLabels([label('a'), label('b')], [node]))).toEqual([
          ['a', 30, 0],
          ['b', 70, 0],
        ]);
      });
    });

    describe('when no spot on the line is free', () => {
      it('leaves the label out', () => {
        const wall = { left: -50, right: 150, top: -5, bottom: 5 };

        expect(placeEdgeLabels([label('a')], [wall])).toEqual([]);
      });
    });
  });

  describe('edgeSegment', () => {
    it('starts and ends the line at the given distance from each center', () => {
      expect(edgeSegment({ x: 0, y: 0 }, { x: 100, y: 0 }, { fromGap: 10, toGap: 30 })).toEqual({
        x1: 10,
        y1: 0,
        x2: 70,
        y2: 0,
        length: 60,
      });
    });
  });

  describe('edgeArrowheads', () => {
    const segment = { x1: 0, y1: 0, x2: 70, y2: 0 };
    const tips = (relationships) =>
      edgeArrowheads(segment, relationships, { start: 'Pipeline', end: 'Job', size: 7 }).map(
        (points) => points.split(' ')[0],
      );

    describe('when the relationships point to the end', () => {
      it('gives one arrowhead at the end', () => {
        expect(tips([{ target: 'Job' }])).toEqual(['70,0']);
      });
    });

    describe('when the relationships point both ways', () => {
      it('gives one arrowhead at each end', () => {
        expect(tips([{ target: 'Job' }, { target: 'Pipeline' }])).toEqual(['70,0', '0,0']);
      });
    });
  });

  describe('entityQuery', () => {
    it.each`
      entity        | expected
      ${'Pipeline'} | ${'MATCH (p:Pipeline)\nWHERE p.id IS NOT NULL\nRETURN p.id, p.status\nLIMIT 25'}
      ${'User'}     | ${'MATCH (u:User)\nWHERE u.id IS NOT NULL\nRETURN u.username\nLIMIT 25'}
      ${'Package'}  | ${'MATCH (p:Package)\nWHERE p.id IS NOT NULL\nRETURN p.id\nLIMIT 25'}
    `('lists $entity entities', ({ entity, expected }) => {
      expect(entityQuery(nodesByName[entity])).toBe(expected);
    });

    describe('when the initials of the entity are a GQL keyword', () => {
      it('adds a number to the alias', () => {
        const importedSymbol = {
          name: 'ImportedSymbol',
          primary_key: 'id',
          label_field: 'identifier_name',
          properties: [],
        };

        expect(entityQuery(importedSymbol)).toBe(
          'MATCH (is2:ImportedSymbol)\nWHERE is2.id IS NOT NULL\nRETURN is2.identifier_name\nLIMIT 25',
        );
      });
    });
  });

  describe('relationshipQuery', () => {
    it.each`
      relationship                                                            | expected
      ${{ name: 'TRIGGERED', source: 'User', target: 'Pipeline' }}            | ${'MATCH (u:User)-[:TRIGGERED]->(p:Pipeline)\nWHERE u.id IS NOT NULL\nRETURN u.username, p.id\nLIMIT 25'}
      ${{ name: 'AUTO_CANCELED_BY', source: 'Pipeline', target: 'Pipeline' }} | ${'MATCH (p:Pipeline)-[:AUTO_CANCELED_BY]->(p2:Pipeline)\nWHERE p.id IS NOT NULL\nRETURN p.id, p2.id\nLIMIT 25'}
    `('lists the pairs of $relationship.name', ({ relationship, expected }) => {
      expect(relationshipQuery(relationship, nodesByName)).toBe(expected);
    });
  });

  it('gives a schema without nodes or edges empty lists', () => {
    expect(normalizeSchema({ schema_version: 'v1' })).toEqual({
      schema_version: 'v1',
      nodes: [],
      edges: [],
    });
  });
});
