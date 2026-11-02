import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { initOAuthApplicationGranularScopes } from '~/oauth_application/init_granular_scopes_picker';
import GranularScopesPicker from '~/oauth_application/components/granular_scopes_picker.vue';

jest.mock('~/lib/utils/vue3compat/init_vue_app');

describe('initOAuthApplicationGranularScopes', () => {
  afterEach(() => {
    resetHTMLFixture();
  });

  describe('without the mount element', () => {
    it('returns null and mounts nothing', () => {
      expect(initOAuthApplicationGranularScopes()).toBeNull();
      expect(initVueApp).not.toHaveBeenCalled();
    });
  });

  describe('with the mount element', () => {
    const initialScopes = [{ access: 'USER', permissions: ['execute_mcp_tool'], namespaces: [] }];

    beforeEach(() => {
      setHTMLFixture(`
        <div
          id="js-oauth-application-granular-scopes"
          data-allowed-access-levels='["USER","SELECTED_MEMBERSHIPS"]'
          data-group-full-path="acme"
          data-group-name="Acme"
          data-initial-scopes='${JSON.stringify(initialScopes)}'
        ></div>
      `);
    });

    it('mounts the picker with the props parsed from the element', () => {
      initOAuthApplicationGranularScopes();

      expect(initVueApp).toHaveBeenCalledWith(
        expect.objectContaining({
          el: document.querySelector('#js-oauth-application-granular-scopes'),
          component: GranularScopesPicker,
          props: {
            allowedAccessLevels: ['USER', 'SELECTED_MEMBERSHIPS'],
            groupFullPath: 'acme',
            groupName: 'Acme',
            initialScopes,
          },
        }),
      );
    });
  });
});
