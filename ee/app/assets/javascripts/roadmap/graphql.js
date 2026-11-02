import { concatPagination } from '@apollo/client/utilities';
import createDefaultClient from '~/lib/graphql';
import typeDefs from './queries/typedefs.graphql';
import localRoadmapSettingsQuery from './queries/local_roadmap_settings.query.graphql';

const resolvers = {
  Mutation: {
    updateLocalRoadmapSettings: (_, { input }, { cache }) => {
      const existingSettings = cache.readQuery({ query: localRoadmapSettingsQuery });
      const updatedSettings = {
        ...existingSettings.localRoadmapSettings,
        ...input,
      };

      cache.writeQuery({
        query: localRoadmapSettingsQuery,
        data: {
          localRoadmapSettings: {
            ...updatedSettings,
            __typename: 'LocalRoadmapSettings',
          },
        },
      });

      return updatedSettings;
    },
  },
};

export const cacheConfig = {
  typePolicies: {
    Group: {
      fields: {
        epics: {
          keyArgs: [
            'search',
            'sort',
            'labelName',
            'milestoneTitle',
            'state',
            'not',
            'or',
            'authorUsername',
            'iid',
            'myReactionEmoji',
            'confidential',
            'timeframe',
            'includeDescendantGroups',
          ],
        },
        milestones: {
          keyArgs: ['state', 'includeDescendants', 'includeAncestors', 'timeframe', 'searchTitle'],
        },
      },
    },
    EpicConnection: {
      fields: {
        nodes: concatPagination(),
      },
    },
    MilestoneConnection: {
      fields: {
        nodes: {
          merge(existing = [], incoming = [], { readField }) {
            const seen = new Set(existing.map((node) => readField('id', node)));
            const newNodes = incoming.filter((node) => !seen.has(readField('id', node)));
            return [...existing, ...newNodes];
          },
        },
      },
    },
    LocalRoadmapSettings: {
      fields: {
        filterParams: {
          read(value) {
            return JSON.parse(value);
          },
          merge(_, incoming) {
            return JSON.stringify(incoming);
          },
        },
      },
    },
  },
};

export const defaultClient = createDefaultClient(resolvers, {
  typeDefs,
  cacheConfig,
});
