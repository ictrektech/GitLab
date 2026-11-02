import localRoadmapSettingsQuery from 'ee/roadmap/queries/local_roadmap_settings.query.graphql';
import { mockLocalRoadmapSettings } from 'ee_jest/roadmap/mock_data';

const writeLocalSettings = (target, settings) => {
  target.writeQuery({
    query: localRoadmapSettingsQuery,
    data: {
      localRoadmapSettings: {
        __typename: 'LocalRoadmapSettings',
        ...mockLocalRoadmapSettings,
        ...settings,
      },
    },
  });
};

export const setLocalSettingsInCache = (apolloProvider, settings = {}) => {
  writeLocalSettings(apolloProvider.clients.defaultClient.cache, settings);
};

export const updateLocalSettingsInCache = (apolloProvider, settings) => {
  const { defaultClient } = apolloProvider.clients;
  const { localRoadmapSettings } = defaultClient.readQuery({ query: localRoadmapSettingsQuery });

  writeLocalSettings(defaultClient, { ...localRoadmapSettings, ...settings });
};

export const expectPayload = (payload) => [
  expect.any(Object),
  { input: payload },
  expect.any(Object),
  expect.any(Object),
];
