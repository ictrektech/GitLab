import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { initAiSettings } from 'ee/ai/settings/index';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';

Vue.use(VueApollo);

const MockComponent = {
  name: 'MockComponent',
  props: ['redirectPath', 'updateId', 'duoProVisible'],
  render(h) {
    return h('div');
  },
};

describe('initAiSettings', () => {
  afterEach(() => {
    resetHTMLFixture();
  });

  it('returns false when element does not exist', () => {
    setHTMLFixture('');
    const result = initAiSettings('js-ai-settings', MockComponent);
    expect(result).toBe(false);
  });

  it('returns a Vue instance when element exists with minimal data', () => {
    setHTMLFixture('<div id="js-ai-settings"></div>');

    const vueInstance = initAiSettings('js-ai-settings', MockComponent);

    expect(vueInstance).toHaveProperty('$options');
    expect(vueInstance.$el).toBeDefined();
  });

  it('provides duoAvailabilityAdminLocked as a parsed boolean', () => {
    setHTMLFixture('<div id="js-ai-settings" data-duo-availability-admin-locked="true"></div>');

    const vueInstance = initAiSettings('js-ai-settings', MockComponent);

    expect(vueInstance.$options.provide.duoAvailabilityAdminLocked).toBe(true);
  });

  it('defaults duoAvailabilityAdminLocked to false when not provided', () => {
    setHTMLFixture('<div id="js-ai-settings"></div>');

    const vueInstance = initAiSettings('js-ai-settings', MockComponent);

    expect(vueInstance.$options.provide.duoAvailabilityAdminLocked).toBe(false);
  });

  it('provides duoTokenUsageTrackingEnabled as a parsed boolean', () => {
    setHTMLFixture('<div id="js-ai-settings" data-duo-token-usage-tracking-enabled="false"></div>');

    const vueInstance = initAiSettings('js-ai-settings', MockComponent);

    expect(vueInstance.$options.provide.duoTokenUsageTrackingEnabled).toBe(false);
  });

  describe('JSON parsing', () => {
    it('successfully parses namespace access rules despite empty cascading settings', () => {
      const namespaceRules = [
        { id: '1', accessible_entity: 'duo_classic', target_id: '123' },
        { id: '2', accessible_entity: 'duo_agent_platform', target_id: '456' },
      ];

      setHTMLFixture(`
        <div id="js-ai-settings"
          data-namespace-access-rules='${JSON.stringify(namespaceRules)}'
          data-duo-availability-cascading-settings=""
          data-duo-remote-flows-cascading-settings=""
          data-duo-foundational-flows-cascading-settings="">
        </div>
      `);

      const vueInstance = initAiSettings('js-ai-settings', MockComponent);

      expect(vueInstance).toHaveProperty('$options');

      expect(vueInstance.$options.provide.initialNamespaceAccessRules).toEqual([
        { id: '1', accessibleEntity: 'duo_classic', targetId: '123' },
        { id: '2', accessibleEntity: 'duo_agent_platform', targetId: '456' },
      ]);

      expect(vueInstance.$options.provide.duoAvailabilityCascadingSettings).toBeNull();
      expect(vueInstance.$options.provide.duoRemoteFlowsCascadingSettings).toBeNull();
      expect(vueInstance.$options.provide.duoFoundationalFlowsCascadingSettings).toBeNull();
    });
  });

  it('handles invalid JSON in namespace_access_rules gracefully', () => {
    setHTMLFixture(`
      <div id="js-ai-settings"
        data-namespace-access-rules="{invalid json}">
      </div>
    `);

    const vueInstance = initAiSettings('js-ai-settings', MockComponent);

    expect(vueInstance).toHaveProperty('$options');
    expect(vueInstance.$options.provide.initialNamespaceAccessRules).toBeNull();
  });

  it('handles empty tool approval cascading settings gracefully', () => {
    setHTMLFixture(`
      <div id="js-ai-settings"
        data-tool-approval-for-session-cascading-settings="">
      </div>
    `);

    const vueInstance = initAiSettings('js-ai-settings', MockComponent);

    expect(vueInstance).toHaveProperty('$options');
    expect(vueInstance.$options.provide.toolApprovalForSessionCascadingSettings).toBeNull();
  });

  it('successfully parses valid cascading settings', () => {
    const cascadingSettings = { value: 'enabled', locked: false };

    setHTMLFixture(`
      <div id="js-ai-settings"
        data-duo-availability-cascading-settings='${JSON.stringify(cascadingSettings)}'>
      </div>
    `);

    const vueInstance = initAiSettings('js-ai-settings', MockComponent);

    expect(vueInstance.$options.provide.duoAvailabilityCascadingSettings).toEqual({
      value: 'enabled',
      locked: false,
    });
  });

  describe('showDuoTemplateProject', () => {
    it('parses showDuoTemplateProject as true when data attribute is "true"', () => {
      setHTMLFixture(`
        <div id="js-ai-settings"
          data-show-duo-template-project="true">
        </div>
      `);

      const vueInstance = initAiSettings('js-ai-settings', MockComponent);

      expect(vueInstance.$options.provide.showDuoTemplateProject).toBe(true);
    });

    it('parses showDuoTemplateProject as false when data attribute is absent', () => {
      setHTMLFixture('<div id="js-ai-settings"></div>');

      const vueInstance = initAiSettings('js-ai-settings', MockComponent);

      expect(vueInstance.$options.provide.showDuoTemplateProject).toBe(false);
    });
  });

  describe('web search', () => {
    it('parses the web search data attributes as booleans', () => {
      setHTMLFixture(`
        <div id="js-ai-settings"
          data-web-search-enabled="true"
          data-web-search-available="true">
        </div>
      `);

      const vueInstance = initAiSettings('js-ai-settings', MockComponent);

      expect(vueInstance.$options.provide.initialWebSearchEnabled).toBe(true);
      expect(vueInstance.$options.provide.webSearchAvailable).toBe(true);
    });

    it('defaults to false when the data attributes are absent', () => {
      setHTMLFixture('<div id="js-ai-settings"></div>');

      const vueInstance = initAiSettings('js-ai-settings', MockComponent);

      expect(vueInstance.$options.provide.initialWebSearchEnabled).toBe(false);
      expect(vueInstance.$options.provide.webSearchAvailable).toBe(false);
    });
  });

  describe('readiness card', () => {
    let vueInstance;

    describe('when the backend turns it on', () => {
      beforeEach(() => {
        setHTMLFixture('<div id="js-ai-settings" data-readiness-card-enabled="true"></div>');
        vueInstance = initAiSettings('js-ai-settings', MockComponent);
      });

      it('provides it as on', () => {
        expect(vueInstance.$options.provide.readinessCardEnabled).toBe(true);
      });
    });

    describe('when the attribute is absent', () => {
      beforeEach(() => {
        setHTMLFixture('<div id="js-ai-settings"></div>');
        vueInstance = initAiSettings('js-ai-settings', MockComponent);
      });

      it('provides it as off', () => {
        expect(vueInstance.$options.provide.readinessCardEnabled).toBe(false);
      });
    });
  });

  describe('group readiness data', () => {
    it('parses the owner and inherited values', () => {
      setHTMLFixture(`
        <div id="js-ai-settings"
          data-duo-agent-platform-owner-enabled="true"
          data-duo-agent-platform-owner-settings-path="/groups/my-group/-/settings/gitlab_duo/configuration"
          data-foundational-agents-owner-enabled="false"
          data-duo-availability-inherited-value="default_on"
          data-duo-availability-inherited-source="group"
          data-root-ancestor-name="my-group"
          data-duo-orbit='{"enabled":false,"can_enable":false,"root_group_path":"my-group","graph_path":"/-/dashboard/orbit","cascading_settings":{"locked_by_ancestor":true,"ancestor_namespace":{"full_name":"My group","path":"/groups/my-group/-/edit"}}}'></div>
      `);

      const vueInstance = initAiSettings('js-ai-settings', MockComponent);

      expect(vueInstance.$options.provide).toMatchObject({
        duoAgentPlatformOwnerEnabled: true,
        duoAgentPlatformOwnerSettingsPath: '/groups/my-group/-/settings/gitlab_duo/configuration',
        foundationalAgentsOwnerEnabled: false,
        rootAncestorName: 'my-group',
        duoOrbit: {
          enabled: false,
          canEnable: false,
          rootGroupPath: 'my-group',
          graphPath: '/-/dashboard/orbit',
          cascadingSettings: {
            lockedByAncestor: true,
            ancestorNamespace: { fullName: 'My group', path: '/groups/my-group/-/edit' },
          },
        },
      });
    });

    it('defaults to off and empty when the data attributes are absent', () => {
      setHTMLFixture('<div id="js-ai-settings"></div>');

      const vueInstance = initAiSettings('js-ai-settings', MockComponent);

      expect(vueInstance.$options.provide).toMatchObject({
        duoAgentPlatformOwnerEnabled: false,
        duoAgentPlatformOwnerSettingsPath: null,
        foundationalAgentsOwnerEnabled: false,
        rootAncestorName: '',
        duoOrbit: {},
      });
    });
  });
});
