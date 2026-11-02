import { languages } from 'monaco-editor';
import {
  gqlCompletions,
  registerOrbitGqlLanguage,
} from 'ee/orbit/dashboard/query_editor/gql_language';
import { normalizeSchema } from 'ee/orbit/dashboard/schema/schema_graph';
import { mockExpandedSchema } from '../../mock_data';

describe('Orbit GQL language', () => {
  const schema = normalizeSchema(mockExpandedSchema);

  const completionsAfter = (textBeforeCursor, fullText = textBeforeCursor) =>
    gqlCompletions({ textBeforeCursor, fullText, schema });

  describe('gqlCompletions', () => {
    describe('after a node label colon', () => {
      it('suggests the entities with their domain and description', () => {
        expect(completionsAfter('MATCH (u:')).toEqual([
          { label: 'Job', kind: 'entity', detail: 'Pipelines', documentation: 'A CI/CD job' },
          {
            label: 'Pipeline',
            kind: 'entity',
            detail: 'Pipelines',
            documentation: 'A CI/CD pipeline',
          },
          {
            label: 'Stage',
            kind: 'entity',
            detail: 'Pipelines',
            documentation: 'A pipeline stage',
          },
          { label: 'User', kind: 'entity', detail: 'Core', documentation: 'A GitLab user' },
          {
            label: 'Project',
            kind: 'entity',
            detail: 'Core',
            documentation: 'A GitLab project',
          },
        ]);
      });
    });

    describe('after a relationship colon', () => {
      const authored = {
        label: 'AUTHORED',
        kind: 'relationship',
        detail: 'Authorship relationship',
      };
      const contains = {
        label: 'CONTAINS',
        kind: 'relationship',
        detail: 'Containment relationship',
      };

      it.each([
        ['the labeled node on the left', 'MATCH (u:User)-[:AUTH', [authored]],
        ['the labeled node on the right of an incoming arrow', 'MATCH (s:Stage)<-[:', [contains]],
        ['the node that an earlier pattern binds', 'MATCH (p:Pipeline) MATCH (p)-[:', [contains]],
        ['every entity when the node has no label', 'MATCH (x)-[:', [authored, contains]],
        ['every entity when no entity has the label', 'MATCH (x:Pipe)-[:', [authored, contains]],
      ])('suggests the relationships of %s', (_, textBeforeCursor, suggestions) => {
        expect(completionsAfter(textBeforeCursor)).toEqual(suggestions);
      });
    });

    describe('after a property name colon in a node', () => {
      it('does not suggest the entities', () => {
        expect(completionsAfter('MATCH (g:Group {state:')).not.toContainEqual(
          expect.objectContaining({ kind: 'entity' }),
        );
      });
    });

    describe('after a variable and a dot', () => {
      it('suggests the properties of the entity bound to the variable', () => {
        const fullText = 'MATCH (u:User) RETURN u.';

        expect(completionsAfter(fullText)).toEqual([
          { label: 'id', kind: 'property', detail: 'int64' },
          { label: 'username', kind: 'property', detail: 'string' },
        ]);
      });
    });

    describe('after a variable that no node binds', () => {
      it('suggests nothing', () => {
        expect(completionsAfter('MATCH (u:User) RETURN x.')).toEqual([]);
      });
    });

    describe('anywhere else', () => {
      it('suggests the keywords', () => {
        expect(completionsAfter('MA')).toContainEqual({ label: 'MATCH', kind: 'keyword' });
        expect(completionsAfter('MA')).not.toContainEqual(
          expect.objectContaining({ kind: 'entity' }),
        );
      });

      it('suggests only the keywords that Orbit GQL supports', () => {
        const labels = completionsAfter('MA').map(({ label }) => label);

        expect(labels).toEqual(
          expect.arrayContaining(['IS NOT NULL', 'STARTS WITH', 'SKIP', 'OFFSET']),
        );
        expect(labels).not.toEqual(
          expect.arrayContaining([expect.stringMatching(/^(OPTIONAL|WITH|DISTINCT|OR|NOT)$/)]),
        );
      });
    });
  });

  describe('registerOrbitGqlLanguage', () => {
    const orbitLanguages = () => languages.getLanguages().filter(({ id }) => id === 'orbit-gql');

    describe('when it runs twice', () => {
      beforeEach(() => {
        registerOrbitGqlLanguage();
        registerOrbitGqlLanguage();
      });

      it('keeps one registration', () => {
        expect(orbitLanguages()).toHaveLength(1);
      });
    });
  });
});
