import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlAvatar, GlAvatarLink, GlLink, GlSprintf, GlTruncate } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { getBinding, createMockDirective } from 'helpers/vue_mock_directive';
import { stubComponent } from 'helpers/stub_component';
import { assertProps } from 'helpers/assert_props';
import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import AgentFlowTriggeredUser from 'ee/ai/duo_agents_platform/components/common/agent_flow_triggered_user.vue';
import getAgentFlow from 'ee/ai/duo_agents_platform/graphql/queries/get_agent_flow.query.graphql';
import { mockUser1 } from 'ee_jest/ai/mocks';
import { buildAgentFlowResponse } from './mock';

Vue.use(VueApollo);

describe('AgentFlowTriggeredUser', () => {
  let wrapper;
  let apolloProvider;

  const workflowId = '1';
  const graphqlWorkflowId = convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, workflowId);

  const defaultRoute = { params: { id: workflowId } };

  const writeAgentFlow = (source) =>
    apolloProvider.clients.defaultClient.writeQuery({
      query: getAgentFlow,
      variables: { workflowId: graphqlWorkflowId },
      data: buildAgentFlowResponse(source),
    });

  const createWrapper = ({ props = {}, source, withApollo = true, $route = defaultRoute } = {}) => {
    if (withApollo) {
      apolloProvider = createMockApollo();
      if (source) writeAgentFlow(source);
    }

    wrapper = shallowMount(AgentFlowTriggeredUser, {
      apolloProvider: withApollo ? apolloProvider : undefined,
      propsData: {
        user: mockUser1,
        ...props,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      mocks: { $route },
      stubs: {
        GlSprintf,
        GlTruncate: stubComponent(GlTruncate, { template: '<span>{{ text }}</span>' }),
      },
    });

    return waitForPromises();
  };

  const findAvatarLink = () => wrapper.findComponent(GlAvatarLink);
  const findAvatar = () => wrapper.findComponent(GlAvatar);
  const findSourceLink = () => wrapper.findComponent(GlLink);
  const findSourceTruncate = () => wrapper.findComponent(GlTruncate);

  describe('with a user', () => {
    beforeEach(() => createWrapper());

    it('renders avatar link with correct attributes', () => {
      expect(findAvatarLink().attributes()).toEqual(
        expect.objectContaining({
          href: mockUser1.webUrl,
          'data-username': mockUser1.username,
        }),
      );
    });

    it('renders a truncatable username with @ symbol', () => {
      const username = wrapper.find('[data-testid="triggered-user-username"]');

      expect(username.text()).toBe(`@${mockUser1.username}`);
      expect(username.classes()).toEqual(expect.arrayContaining(['gl-min-w-0', 'gl-truncate']));
    });

    it('renders avatar link with tooltip', () => {
      const avatarLink = findAvatarLink();
      const tooltip = getBinding(avatarLink.element, 'gl-tooltip');

      expect(tooltip).toBeDefined();
      expect(tooltip.modifiers.bottom).toBe(true);
      expect(avatarLink.attributes('title')).toBe(mockUser1.name);
    });
  });

  it('requires the user prop', () => {
    expect(() => assertProps(AgentFlowTriggeredUser, {})).toThrow('Missing required prop');
  });

  describe('when user is an empty object, as while the page query is still loading', () => {
    beforeEach(() => createWrapper({ props: { user: {} } }));

    it('renders avatar link with empty attributes', () => {
      expect(findAvatarLink().attributes()).toEqual(
        expect.objectContaining({
          href: '',
          'data-username': '',
        }),
      );
    });
  });

  describe('when avatarClass is set', () => {
    beforeEach(() => createWrapper({ props: { avatarClass: 'gl-mt-1' } }));

    it('applies it to the avatar', () => {
      expect(findAvatar().classes()).toContain('gl-mt-1');
    });
  });

  describe('without a route and without an Apollo provider', () => {
    beforeEach(() => createWrapper({ withApollo: false, $route: null }));

    it('renders only the user, with no source link', () => {
      expect(wrapper.text()).toBe(`@${mockUser1.username}`);
      expect(findSourceLink().exists()).toBe(false);
    });
  });

  describe('with a workflow id in the route', () => {
    describe('when the page document is not in the cache', () => {
      beforeEach(() => createWrapper());

      it('renders only the user, with no source link', () => {
        expect(wrapper.text()).toBe(`@${mockUser1.username}`);
        expect(findSourceLink().exists()).toBe(false);
      });
    });

    describe('with a SLACK source and an https link', () => {
      beforeEach(() =>
        createWrapper({
          source: {
            sourceType: 'SLACK',
            sourceLink: 'https://example.slack.com/archives/C123/p123',
          },
        }),
      );

      it('renders the user and source text', () => {
        expect(wrapper.text()).toMatchInterpolatedText(`@${mockUser1.username} via Slack`);
      });

      it('links the source through GlLink', () => {
        expect(findSourceLink().attributes('href')).toBe(
          'https://example.slack.com/archives/C123/p123',
        );
      });

      it('styles the source link like the avatar link', () => {
        expect(findSourceLink().classes()).toEqual(
          expect.arrayContaining([
            'gl-text-inherit',
            'gl-no-underline',
            'hover:gl-text-link',
            'hover:gl-underline',
          ]),
        );
      });

      it('truncates the Slack label inside the link and underlines it on hover', () => {
        const truncate = findSourceLink().findComponent(GlTruncate);

        expect(truncate.props('text')).toBe('Slack');
        expect(truncate.classes()).toContain('hover:gl-underline');
      });
    });

    describe('when the page document lands in the cache after mounting', () => {
      beforeEach(async () => {
        await createWrapper();

        writeAgentFlow({
          sourceType: 'SLACK',
          sourceLink: 'https://example.slack.com/archives/C123/p123',
        });
        await waitForPromises();
      });

      it('re-renders with the source link', () => {
        expect(findSourceLink().attributes('href')).toBe(
          'https://example.slack.com/archives/C123/p123',
        );
      });
    });

    describe('when a poll rewrites the cached page document with a source', () => {
      beforeEach(async () => {
        await createWrapper({ source: { sourceType: null, sourceLink: null } });

        writeAgentFlow({
          sourceType: 'SLACK',
          sourceLink: 'https://example.slack.com/archives/C123/p123',
        });
        await waitForPromises();
      });

      it('re-renders with the source link', () => {
        expect(findSourceLink().attributes('href')).toBe(
          'https://example.slack.com/archives/C123/p123',
        );
      });
    });

    describe.each([
      ['SLACK', 'Slack'],
      ['MCP', 'MCP'],
    ])('with a %s source and no link', (sourceType, label) => {
      beforeEach(() => createWrapper({ source: { sourceType, sourceLink: '' } }));

      it(`renders the ${label} label as plain text`, () => {
        expect(findSourceTruncate().props('text')).toBe(label);
      });

      it('does not render a GlLink', () => {
        expect(findSourceLink().exists()).toBe(false);
      });
    });

    describe('with an unknown source type and an https link', () => {
      beforeEach(() =>
        createWrapper({
          source: { sourceType: 'JIRA', sourceLink: 'https://example.com/issue/1' },
        }),
      );

      it('renders the bare URL linked', () => {
        expect(findSourceLink().attributes('href')).toBe('https://example.com/issue/1');
        expect(findSourceLink().findComponent(GlTruncate).props('text')).toBe(
          'https://example.com/issue/1',
        );
      });
    });

    describe('with an unknown source type and a javascript: link', () => {
      beforeEach(() =>
        createWrapper({
          source: {
            sourceType: 'JIRA',
            // A deliberately unsafe scheme, to verify hasValidSourceLink rejects it.
            // eslint-disable-next-line no-script-url
            sourceLink: 'javascript:alert(1)',
          },
        }),
      );

      it('renders the link text unlinked', () => {
        expect(findSourceLink().exists()).toBe(false);
        // eslint-disable-next-line no-script-url
        expect(findSourceTruncate().props('text')).toBe('javascript:alert(1)');
      });
    });

    describe.each([
      ['an unknown source type and no link', { sourceType: 'JIRA', sourceLink: '' }],
      [
        'no source type but a link, because the type is the gate',
        { sourceType: null, sourceLink: 'https://example.com/issue/1' },
      ],
    ])('with %s', (_, source) => {
      beforeEach(() => createWrapper({ source }));

      it('renders only the user, with no source link', () => {
        expect(wrapper.text()).toBe(`@${mockUser1.username}`);
        expect(findSourceLink().exists()).toBe(false);
      });
    });

    describe('compact mode', () => {
      describe('with a SLACK source and a link', () => {
        beforeEach(() =>
          createWrapper({
            props: { compact: true },
            source: {
              sourceType: 'SLACK',
              sourceLink: 'https://example.slack.com/archives/C123/p123',
            },
          }),
        );

        it("renders 'via Slack' without the @username", () => {
          expect(wrapper.text()).toContain('via Slack');
          expect(findSourceLink().findComponent(GlTruncate).props('text')).toBe('Slack');
          expect(wrapper.text()).not.toContain(`@${mockUser1.username}`);
        });

        it('renders avatar link and tooltip', () => {
          const avatarLink = findAvatarLink();
          const tooltip = getBinding(avatarLink.element, 'gl-tooltip');

          expect(avatarLink.classes()).toContain('js-user-link');
          expect(avatarLink.attributes()).toEqual(
            expect.objectContaining({
              'data-user-id': expect.any(String),
              'data-username': mockUser1.username,
              title: mockUser1.name,
            }),
          );
          expect(tooltip).toBeDefined();
        });

        it('keeps the avatar from shrinking, so it does not overlap "via"', () => {
          expect(findAvatarLink().classes()).toContain('gl-min-w-0');
          expect(findAvatar().classes()).toContain('gl-shrink-0');
        });
      });

      describe('with no source type', () => {
        beforeEach(() =>
          createWrapper({
            props: { compact: true },
            source: { sourceType: null, sourceLink: null },
          }),
        );

        it('still renders the @username in a truncatable element', () => {
          const username = wrapper.find('[data-testid="triggered-user-username"]');

          expect(username.text()).toBe(`@${mockUser1.username}`);
          expect(username.classes()).toEqual(expect.arrayContaining(['gl-min-w-0', 'gl-truncate']));
          expect(findAvatarLink().classes()).toContain('gl-min-w-0');
          expect(findAvatar().classes()).toContain('gl-shrink-0');
        });
      });
    });
  });
});
