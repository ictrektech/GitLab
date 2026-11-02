import {
  getNamespaceIndexComponent,
  getMcpServersIndexComponent,
  getPreviousRoute,
  setPreviousRoute,
} from 'ee/ai/duo_agents_platform/router/utils';

import ProjectAgentsPlatformIndex from 'ee/ai/duo_agents_platform/namespace/project/project_agents_platform_index.vue';
import UserAgentsPlatformIndex from 'ee/ai/duo_agents_platform/namespace/user/user_agents_platform_index.vue';
import ProjectMcpServersIndex from 'ee/ai/duo_agents_platform/namespace/project/project_mcp_servers_index.vue';
import GroupMcpServersIndex from 'ee/ai/duo_agents_platform/namespace/group/group_mcp_servers_index.vue';
import AgentSessionInbox from 'ee/ai/duo_agents_platform/panel/agent_session_inbox.vue';

describe('getNamespaceIndexComponent', () => {
  describe('when namespace is not provided', () => {
    it('throws an error', () => {
      expect(() => getNamespaceIndexComponent()).toThrow(
        'The namespace argument must be passed to the Vue Router',
      );
    });
  });

  it.each`
    namespace    | expectedComponent             | expectedComponentName
    ${'project'} | ${ProjectAgentsPlatformIndex} | ${'ProjectAgentsPlatformIndex'}
    ${'user'}    | ${UserAgentsPlatformIndex}    | ${'UserAgentsPlatformIndex'}
    ${'group'}   | ${undefined}                  | ${'undefined'}
    ${'unknown'} | ${undefined}                  | ${'undefined'}
  `(
    'returns $expectedComponentName when namespace is $namespace',
    ({ namespace, expectedComponent }) => {
      expect(getNamespaceIndexComponent(namespace)).toBe(expectedComponent);
    },
  );
});

describe('getNamespaceIndexComponent for the side panel namespace', () => {
  it.each`
    duoPanelSessionInbox | experimentFeaturesEnabled | expectedComponent
    ${true}              | ${true}                   | ${AgentSessionInbox}
    ${true}              | ${false}                  | ${UserAgentsPlatformIndex}
    ${false}             | ${true}                   | ${UserAgentsPlatformIndex}
    ${false}             | ${false}                  | ${UserAgentsPlatformIndex}
  `(
    'returns the expected component when duoPanelSessionInbox is $duoPanelSessionInbox and experimentFeaturesEnabled is $experimentFeaturesEnabled',
    ({ duoPanelSessionInbox, experimentFeaturesEnabled, expectedComponent }) => {
      window.gon = { features: { duoPanelSessionInbox } };

      expect(getNamespaceIndexComponent('side_panel', { experimentFeaturesEnabled })).toBe(
        expectedComponent,
      );
    },
  );

  describe('when duo_panel_session_inbox is enabled', () => {
    beforeEach(() => {
      window.gon = { features: { duoPanelSessionInbox: true } };
    });

    it('returns the user sessions list when no options are passed', () => {
      expect(getNamespaceIndexComponent('side_panel')).toBe(UserAgentsPlatformIndex);
    });

    it('leaves the user namespace on the full-page component', () => {
      expect(getNamespaceIndexComponent('user', { experimentFeaturesEnabled: true })).toBe(
        UserAgentsPlatformIndex,
      );
    });
  });

  describe('when window.gon is empty', () => {
    beforeEach(() => {
      window.gon = {};
    });

    it('returns the user sessions list', () => {
      expect(getNamespaceIndexComponent('side_panel', { experimentFeaturesEnabled: true })).toBe(
        UserAgentsPlatformIndex,
      );
    });
  });
});

describe('getMcpServersIndexComponent', () => {
  describe('when namespace is not provided', () => {
    it('throws an error', () => {
      expect(() => getMcpServersIndexComponent()).toThrow(
        'The namespace argument must be passed to the Vue Router',
      );
    });
  });

  it.each`
    namespace    | expectedComponent         | expectedComponentName
    ${'project'} | ${ProjectMcpServersIndex} | ${'ProjectMcpServersIndex'}
    ${'group'}   | ${GroupMcpServersIndex}   | ${'GroupMcpServersIndex'}
    ${'user'}    | ${undefined}              | ${'undefined'}
    ${'unknown'} | ${undefined}              | ${'undefined'}
  `(
    'returns $expectedComponentName when namespace is $namespace',
    ({ namespace, expectedComponent }) => {
      expect(getMcpServersIndexComponent(namespace)).toBe(expectedComponent);
    },
  );
});

describe('Previous route', () => {
  beforeEach(() => {
    setPreviousRoute(null);
  });

  it('sets and gets a route', () => {
    const route = { name: 'test_route', params: { id: '123' } };
    setPreviousRoute(route);
    expect(getPreviousRoute()).toBe(route);
  });

  it('returns null when not set', () => {
    expect(getPreviousRoute()).toBeNull();
  });
});
