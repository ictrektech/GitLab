import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlPopover, GlSkeletonLoader, GlAvatar, GlIcon } from '@gitlab/ui';
import { shallowMountExtended, extendedWrapper } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import { stubComponent } from 'helpers/stub_component';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import AgentSessionPopover from 'ee/blob/components/agent_session_popover.vue';
import agentSessionQuery from 'ee/blob/queries/agent_session.query.graphql';
import agentSessionLinksQuery from 'ee/blob/queries/agent_session_links.query.graphql';
import AgentSessionLink from 'ee/blob/components/agent_session_link.vue';
import TimeagoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';

Vue.use(VueApollo);

describe('AgentSessionPopover', () => {
  let wrapper;
  let linksQueryHandler;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const projectPath = 'group/project';
  const sessionUrl = (id) =>
    `${window.location.origin}/${projectPath}/-/automate/agent-sessions/${id}`;

  const sessionNode = {
    id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/4310',
    title: 'Render blame groups as grid cells',
    goal: 'Move blame positioning to a CSS grid.',
    status: 'FINISHED',
    humanStatus: 'finished',
    workflowDefinition: 'software_development',
    updatedAt: '2026-08-05T15:08:00Z',
    user: {
      __typename: 'User',
      id: 'gid://gitlab/User/1',
      name: 'Jacques Erasmus',
      username: 'jerasmus',
      avatarUrl: '/avatar.png',
      webUrl: 'http://test.host/jerasmus',
      webPath: '/jerasmus',
    },
    workItemLinks: {
      nodes: [
        {
          linkType: 'SOURCE',
          workItem: {
            id: 'gid://gitlab/WorkItem/1',
            iid: '603118',
            webPath: '/i/1',
          },
        },
      ],
    },
    mergeRequestLinks: {
      nodes: [
        {
          linkType: 'CREATED',
          mergeRequest: {
            id: 'gid://gitlab/MergeRequest/1',
            iid: '202961',
            webPath: '/mr/1',
          },
        },
      ],
    },
  };
  const linksNode = {
    id: sessionNode.id,
    noteLinks: { nodes: [] },
    pipelineLinks: { nodes: [] },
  };
  const workflowGid = (id) => `gid://gitlab/Ai::DuoWorkflows::Workflow/${id}`;
  const queryResponseWith = (node) => ({
    data: { duoWorkflowWorkflows: { nodes: [node] } },
  });
  // Resolves session 4310; any other session is not readable by the user, which
  // the API reports as an error.
  const handlerFor = (node) =>
    jest.fn(({ workflowId }) =>
      workflowId === workflowGid(4310)
        ? Promise.resolve(queryResponseWith(node))
        : Promise.resolve({ errors: [{ message: 'Workflow not found' }] }),
    );

  const createComponent = ({
    sessionUrls = [sessionUrl(4310)],
    queryHandler = handlerFor(sessionNode),
    linksHandler = handlerFor(linksNode),
  } = {}) => {
    linksQueryHandler = linksHandler;
    wrapper = shallowMountExtended(AgentSessionPopover, {
      apolloProvider: createMockApollo([
        [agentSessionQuery, queryHandler],
        [agentSessionLinksQuery, linksHandler],
      ]),
      propsData: { sessionUrls },
      stubs: { GlPopover: stubComponent(GlPopover, { template: '<div><slot></slot></div>' }) },
    });
    return queryHandler;
  };

  const findTrigger = () => wrapper.findComponentByTestId('agent-session-trigger');
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findSessions = () => wrapper.findAllByTestId('agent-session');
  const findSession = (index) => extendedWrapper(findSessions().at(index));
  const findSessionLinks = () => findPopover().findAllComponents(AgentSessionLink);
  const openPopover = async () => {
    findPopover().vm.$emit('show');
    await waitForPromises();
  };

  describe('before the popover opens', () => {
    let queryHandler;

    beforeEach(() => {
      queryHandler = createComponent();
    });

    it('renders a plain, neutral icon link to the first session', () => {
      expect(findTrigger().props('href')).toBe(sessionUrl(4310));
      expect(findTrigger().attributes('aria-label')).toBe('View session for this change');
      expect(findTrigger().classes()).toContain('!gl-text-subtle');
    });

    it('attaches a hover and focus popover to the session icon', () => {
      expect(findPopover().props()).toMatchObject({ triggers: 'hover focus', placement: 'top' });
      expect(findPopover().props('target')().$el).toBe(findTrigger().element);
    });

    it('does not request session details', () => {
      expect(queryHandler).not.toHaveBeenCalled();
    });

    it('lists the session from the trailer', () => {
      expect(findSessionLinks().at(0).text()).toBe('Agent session 4310');
    });

    it('tracks clicks on the icon and the session title by element', () => {
      expect(findTrigger().props('trackingProperty')).toBe('gutter_icon');
      expect(findSessionLinks().at(0).props('trackingProperty')).toBe('popover_title');
    });
  });

  describe('when the popover opens', () => {
    let queryHandler;

    beforeEach(async () => {
      queryHandler = createComponent();
      findPopover().vm.$emit('show');
      await Vue.nextTick();
    });

    it('tracks that the popover was shown', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith('view_agent_session_popover', {}, undefined);
    });

    it('looks the session up by ID', () => {
      expect(queryHandler).toHaveBeenCalledWith({ workflowId: workflowGid(4310) });
      expect(linksQueryHandler).toHaveBeenCalledWith({ workflowId: workflowGid(4310) });
    });

    describe('when details have loaded', () => {
      beforeEach(() => waitForPromises());

      it('renders the session with its title, goal, author and linked items', () => {
        const session = findSession(0);

        expect(findSessionLinks().at(0).text()).toBe(sessionNode.title);
        expect(findSessionLinks().at(0).props('href')).toBe(sessionUrl(4310));
        expect(session.findByTestId('agent-session-goal').text()).toBe(sessionNode.goal);
        expect(session.findComponent(GlAvatar).props('src')).toBe('/avatar.png');
        expect(session.findByTestId('agent-session-meta').text()).toContain('Jacques Erasmus');

        const links = session.findAllByTestId('agent-session-linked-item');
        expect(links.wrappers.map((link) => link.text())).toEqual([
          'from #603118',
          'created !202961',
        ]);
        expect(links.at(0).attributes('href')).toBe('/i/1');
        expect(links.at(1).attributes('href')).toBe('/mr/1');
      });

      it('shows when the session was last updated', () => {
        expect(findSession(0).findComponent(TimeagoTooltip).props('time')).toBe(
          sessionNode.updatedAt,
        );
      });

      it('names the type of each linked item for screen readers', () => {
        const links = findSession(0).findAllByTestId('agent-session-linked-item');

        expect(links.wrappers.map((link) => link.attributes('aria-label'))).toEqual([
          'from work item #603118',
          'created merge request !202961',
        ]);
      });

      it('does not link to more linked items when all are shown', () => {
        expect(findSession(0).findByTestId('agent-session-more-linked-items').exists()).toBe(false);
      });

      it('does not call out the status of a finished session', () => {
        expect(findSession(0).findByTestId('agent-session-status').exists()).toBe(false);
      });

      it('does not show the session id once details load', () => {
        expect(findSession(0).text()).not.toContain('4310');
      });

      it('queries only once when reopened', async () => {
        await openPopover();

        expect(queryHandler).toHaveBeenCalledTimes(1);
        expect(linksQueryHandler).toHaveBeenCalledTimes(1);
      });

      it('tracks each time the popover is shown', async () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        await openPopover();

        expect(trackEventSpy).toHaveBeenCalledTimes(2);
        expect(trackEventSpy).toHaveBeenCalledWith('view_agent_session_popover', {}, undefined);
      });
    });
  });

  describe('while session details load', () => {
    it('shows a loader', async () => {
      createComponent({ queryHandler: jest.fn().mockReturnValue(new Promise(() => {})) });
      await openPopover();

      expect(wrapper.findComponent(GlSkeletonLoader).exists()).toBe(true);
    });
  });

  describe('when a squashed commit carries several sessions', () => {
    beforeEach(async () => {
      createComponent({ sessionUrls: [sessionUrl(4310), sessionUrl(4402)] });
      await openPopover();
    });

    it('lists one entry per session', () => {
      expect(findSessions()).toHaveLength(2);
    });

    it('still shows the sessions that could be read', () => {
      expect(findSessionLinks().at(0).text()).toBe(sessionNode.title);
    });

    it('links a session it cannot read by its trailer URL, without details', () => {
      expect(findSessionLinks().at(1).text()).toBe('Agent session 4402');
      expect(findSessionLinks().at(1).props('href')).toBe(sessionUrl(4402));
      expect(findSession(1).findByTestId('agent-session-meta').exists()).toBe(false);
    });
  });

  describe('when a session did not finish', () => {
    beforeEach(async () => {
      createComponent({
        queryHandler: jest
          .fn()
          .mockResolvedValue(
            queryResponseWith({ ...sessionNode, status: 'FAILED', humanStatus: 'failed' }),
          ),
      });
      await openPopover();
    });

    it('calls out the status', () => {
      expect(findSession(0).findByTestId('agent-session-status').text()).toBe('Failed');
    });
  });

  describe('linked items', () => {
    const workItemLink = (linkType, iid) => ({
      linkType,
      workItem: {
        id: `gid://gitlab/WorkItem/${iid}`,
        iid,
        webPath: `/i/${iid}`,
      },
    });
    const mergeRequestLink = (linkType, iid) => ({
      linkType,
      mergeRequest: {
        id: `gid://gitlab/MergeRequest/${iid}`,
        iid,
        webPath: `/mr/${iid}`,
      },
    });
    const noteLink = (linkType, id, reference) => ({
      linkType,
      note: {
        id: `gid://gitlab/Note/${id}`,
        url: `/note/${id}`,
        discussion: {
          id: `gid://gitlab/Discussion/${id}`,
          noteable: reference
            ? { __typename: 'MergeRequest', id: 'gid://gitlab/MergeRequest/1', reference }
            : null,
        },
      },
    });
    const pipelineLink = (id) => ({
      linkType: 'SOURCE',
      pipeline: {
        id: `gid://gitlab/Ci::Pipeline/${id}`,
        path: `/pipelines/${id}`,
      },
    });
    const findLinkedItems = () =>
      findSession(0)
        .findAllByTestId('agent-session-linked-item')
        .wrappers.map((link) => link.text());
    const findLinkedItemIcons = () =>
      findSession(0)
        .findAllByTestId('agent-session-linked-item')
        .wrappers.map((link) => link.findComponent(GlIcon).props('name'));
    const findMoreLink = () =>
      findSession(0).findComponentByTestId('agent-session-more-linked-items');

    const openWithLinks = async ({
      workItemLinks = [],
      mergeRequestLinks = [],
      noteLinks = [],
      pipelineLinks = [],
    }) => {
      createComponent({
        queryHandler: jest.fn().mockResolvedValue(
          queryResponseWith({
            ...sessionNode,
            workItemLinks: { nodes: workItemLinks },
            mergeRequestLinks: { nodes: mergeRequestLinks },
          }),
        ),
        linksHandler: jest.fn().mockResolvedValue(
          queryResponseWith({
            ...linksNode,
            noteLinks: { nodes: noteLinks },
            pipelineLinks: { nodes: pipelineLinks },
          }),
        ),
      });
      await openPopover();
    };

    describe('with several sources and several created items', () => {
      beforeEach(() =>
        openWithLinks({
          workItemLinks: [
            workItemLink('CREATED', '9'),
            workItemLink('SOURCE', '5'),
            workItemLink('SOURCE', '8'),
            workItemLink('SOURCE', '7'),
          ],
          mergeRequestLinks: [mergeRequestLink('CREATED', '9'), mergeRequestLink('CREATED', '8')],
        }),
      );

      it('shows the first source and the first created item', () => {
        expect(findLinkedItems()).toEqual(['from #5', 'created #9']);
      });

      it('links the rest to the session', () => {
        expect(findMoreLink().text()).toBe('+4 more');
        expect(findMoreLink().props('href')).toBe(sessionUrl(4310));
      });

      it('tracks clicks on the rest as the more link', () => {
        expect(findMoreLink().props('trackingProperty')).toBe('popover_more');
      });

      it('says what the rest are for screen readers', () => {
        expect(findMoreLink().attributes('aria-label')).toBe('+4 more linked items');
      });
    });

    describe('with notes the session was triggered by and created', () => {
      beforeEach(() =>
        openWithLinks({
          noteLinks: [noteLink('TRIGGERED', 1, '!7'), noteLink('CREATED', 2, '!7')],
        }),
      );

      it('shows the triggering note as the source', () => {
        expect(findLinkedItems()).toEqual(['from !7', 'created !7']);
      });

      it('marks them with the note icon', () => {
        expect(findLinkedItemIcons()).toEqual(['comment', 'comment']);
      });

      it('links to the notes', () => {
        const links = findSession(0).findAllByTestId('agent-session-linked-item');

        expect(links.at(0).attributes('href')).toBe('/note/1');
        expect(links.at(1).attributes('href')).toBe('/note/2');
      });

      it('names them as notes for screen readers', () => {
        const links = findSession(0).findAllByTestId('agent-session-linked-item');

        expect(links.wrappers.map((link) => link.attributes('aria-label'))).toEqual([
          'from a note on !7',
          'created a note on !7',
        ]);
      });
    });

    describe('with a note on an item without a reference', () => {
      beforeEach(() => openWithLinks({ noteLinks: [noteLink('TRIGGERED', 1, null)] }));

      it('labels it as a note', () => {
        expect(findLinkedItems()).toEqual(['from a note']);
      });

      it('relies on the visible label for screen readers', () => {
        expect(
          findSession(0).findByTestId('agent-session-linked-item').attributes('aria-label'),
        ).toBeUndefined();
      });
    });

    describe('with a pipeline source', () => {
      beforeEach(() =>
        openWithLinks({
          mergeRequestLinks: [mergeRequestLink('SOURCE', '7')],
          pipelineLinks: [pipelineLink(2881727694)],
        }),
      );

      it('shows the pipeline', () => {
        expect(findLinkedItems()).toEqual(['from !7', 'from #2881727694']);
      });

      it('marks it with the pipeline icon', () => {
        expect(findLinkedItemIcons()).toEqual(['merge-request', 'pipeline']);
      });

      it('links to the pipeline', () => {
        const pipeline = findSession(0).findAllByTestId('agent-session-linked-item').at(1);

        expect(pipeline.attributes('href')).toBe('/pipelines/2881727694');
        expect(pipeline.attributes('aria-label')).toBe('from pipeline #2881727694');
      });
    });

    describe('with notes and pipelines beyond the shown items', () => {
      beforeEach(() =>
        openWithLinks({
          mergeRequestLinks: [mergeRequestLink('SOURCE', '7'), mergeRequestLink('CREATED', '9')],
          noteLinks: [noteLink('CREATED', 2, '!9')],
          pipelineLinks: [pipelineLink(2881727694)],
        }),
      );

      it('counts them in the rest', () => {
        expect(findLinkedItems()).toEqual(['from !7', 'created !9']);
        expect(findMoreLink().text()).toBe('+2 more');
      });
    });

    describe('with several sources and nothing created', () => {
      beforeEach(() =>
        openWithLinks({
          workItemLinks: [workItemLink('SOURCE', '5'), workItemLink('SOURCE', '8')],
          mergeRequestLinks: [mergeRequestLink('SOURCE', '7')],
        }),
      );

      it('shows the first two sources', () => {
        expect(findLinkedItems()).toEqual(['from #5', 'from #8']);
      });

      it('links the rest to the session', () => {
        expect(findMoreLink().text()).toBe('+1 more');
        expect(findMoreLink().attributes('aria-label')).toBe('+1 more linked item');
      });
    });
  });

  describe('without a valid session URL', () => {
    it('renders nothing', () => {
      createComponent({ sessionUrls: ['https://example.com/not-a-session'] });

      expect(findTrigger().exists()).toBe(false);
      expect(findPopover().exists()).toBe(false);
    });
  });

  describe('when the details query fails', () => {
    let queryHandler;

    beforeEach(async () => {
      queryHandler = createComponent({
        queryHandler: jest
          .fn()
          .mockRejectedValueOnce(new Error('boom'))
          .mockResolvedValue(queryResponseWith(sessionNode)),
      });
      await openPopover();
    });

    it('still lists the session from the trailer', () => {
      expect(wrapper.findComponent(GlSkeletonLoader).exists()).toBe(false);
      expect(findSessions()).toHaveLength(1);
      expect(findSessionLinks().at(0).props('href')).toBe(sessionUrl(4310));
    });

    it('queries again when reopened', async () => {
      await openPopover();

      expect(queryHandler).toHaveBeenCalledTimes(2);
      expect(findSessionLinks().at(0).text()).toBe(sessionNode.title);
    });
  });

  describe('when the note and pipeline links query fails', () => {
    beforeEach(async () => {
      createComponent({ linksHandler: jest.fn().mockRejectedValue(new Error('boom')) });
      await openPopover();
    });

    it('still shows the session details and its other linked items', () => {
      expect(findSessionLinks().at(0).text()).toBe(sessionNode.title);
      expect(
        findSession(0)
          .findAllByTestId('agent-session-linked-item')
          .wrappers.map((link) => link.text()),
      ).toEqual(['from #603118', 'created !202961']);
    });
  });
});
