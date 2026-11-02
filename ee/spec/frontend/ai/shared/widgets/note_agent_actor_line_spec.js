import { shallowMount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import NoteAgentActorLine from 'ee/ai/shared/widgets/note_agent_actor_line.vue';
import AgentActorLine from 'ee/ai/shared/widgets/agent_actor_line.vue';
import { mockAgentPresence } from './mock_data';

const FITS_WHOLE_LINE = 60;
const FITS_SESSION_ONLY = 20;
const FITS_NOTHING = 5;

const LEGACY_HEADER = { info: 'note-header-info', meta: 'note-headline-meta' };
const RAPID_DIFFS_HEADER = { info: 'js-note-header-info', meta: 'js-note-headline-meta' };

// GlResizeObserverDirective shares one ResizeObserver for the whole app, built on
// first bind, so the stub has to outlive any single test.
const observed = new Set();
let notifyResize;

global.ResizeObserver = jest.fn((callback) => {
  notifyResize = callback;

  return {
    observe(element) {
      observed.add(element);
      notifyResize([{ target: element, contentRect: { width: element.offsetWidth } }]);
    },
    unobserve: (element) => observed.delete(element),
    disconnect: () => observed.clear(),
  };
});

describe('NoteAgentActorLine', () => {
  let wrapper;
  let row;
  let resizesWith;

  const ActorLineStub = {
    name: 'AgentActorLine',
    props: {
      agentCatalogPath: { type: String, default: null },
      sessionId: { type: String, default: '' },
      user: { type: Object, default: null },
      triggerSource: { type: String, default: '' },
      canViewSession: { type: Boolean, default: false },
      withInitiator: { type: Boolean, default: true },
    },
    template: `<span>Session{{ withInitiator && user ? ' on behalf of @' + user.username : '' }}</span>`,
  };

  const setRoom = (room) => {
    Object.defineProperty(row, 'offsetWidth', { value: room, configurable: true });
  };

  const createComponent = async ({
    room = FITS_WHOLE_LINE,
    inNoteHeader = true,
    headerClasses = LEGACY_HEADER,
    presence = mockAgentPresence,
  } = {}) => {
    const header = document.createElement('div');
    row = document.createElement('span');

    if (inNoteHeader) {
      header.className = headerClasses.info;
      row.className = headerClasses.meta;
    }

    const host = document.createElement('span');
    row.appendChild(host);
    header.appendChild(row);
    document.body.appendChild(header);
    resizesWith = header;

    Object.defineProperty(row, 'scrollWidth', {
      get: () => row.textContent.length,
      configurable: true,
    });
    setRoom(room);

    wrapper = shallowMount(NoteAgentActorLine, {
      propsData: { presence },
      stubs: { AgentActorLine: ActorLineStub },
      attachTo: host,
    });

    await waitForPromises();
  };

  const resizeTo = async (room) => {
    setRoom(room);
    notifyResize([{ target: resizesWith, contentRect: { width: room } }]);
    jest.runOnlyPendingTimers();
    await waitForPromises();
  };

  const findActorLine = () => wrapper.findComponent(AgentActorLine);
  const findSeparator = () => wrapper.find('[data-testid="actor-line-separator"]');
  const lastOverflow = () => wrapper.emitted('overflow').at(-1);

  afterEach(() => {
    observed.clear();
    document.body.innerHTML = '';
  });

  describe('when the viewer cannot read the session', () => {
    beforeEach(() =>
      createComponent({
        presence: { ...mockAgentPresence, userPermissions: { readDuoWorkflow: false } },
      }),
    );

    it('tells the shared component the session cannot be opened', () => {
      expect(findActorLine().props('canViewSession')).toBe(false);
    });
  });

  describe('when the presence has no user permissions', () => {
    beforeEach(() =>
      createComponent({ presence: { ...mockAgentPresence, userPermissions: null } }),
    );

    it('treats the session as not openable', () => {
      expect(findActorLine().props('canViewSession')).toBe(false);
    });
  });

  describe('when a trigger started the session', () => {
    beforeEach(() =>
      createComponent({
        presence: { ...mockAgentPresence, triggerSource: 'SCHEDULED' },
      }),
    );

    it('passes the trigger source on, so the shared component can word it', () => {
      expect(findActorLine().props('triggerSource')).toBe('SCHEDULED');
    });
  });

  describe('when the row has room for the whole line', () => {
    beforeEach(() => createComponent({ room: FITS_WHOLE_LINE }));

    it('maps the presence onto the shared component', () => {
      expect(findActorLine().props()).toMatchObject({
        agentCatalogPath: '/-/ai/catalog/agents/3',
        sessionId: 'gid://gitlab/Ai::DuoWorkflows::Workflow/42',
        triggerSource: 'HUMAN',
        user: mockAgentPresence.user,
        canViewSession: true,
      });
    });

    it('asks for every part of the line', () => {
      expect(findActorLine().props('withInitiator')).toBe(true);
    });

    it('reports no overflow', () => {
      expect(lastOverflow()).toEqual([false]);
    });

    it('separates the line from the text before it', () => {
      expect(findSeparator().exists()).toBe(true);
      expect(findSeparator().attributes('aria-hidden')).toBe('true');
    });
  });

  describe('when the row cannot fit the initiator either', () => {
    beforeEach(() => createComponent({ room: FITS_SESSION_ONLY }));

    it('drops the initiator as well', () => {
      expect(findActorLine().props('withInitiator')).toBe(false);
    });
  });

  describe('when even the session label does not fit', () => {
    beforeEach(() => createComponent({ room: FITS_NOTHING }));

    it('reports the overflow so the surface can let the header wrap', () => {
      expect(lastOverflow()).toEqual([true]);
    });

    it('drops the separator, since the line wraps onto its own row', () => {
      expect(findSeparator().exists()).toBe(false);
    });
  });

  describe('when the row grows back', () => {
    beforeEach(async () => {
      await createComponent({ room: FITS_SESSION_ONLY });
      await resizeTo(FITS_WHOLE_LINE);
    });

    it('restores every part of the line', () => {
      expect(findActorLine().props('withInitiator')).toBe(true);
    });

    it('withdraws the overflow report', () => {
      expect(lastOverflow()).toEqual([false]);
    });
  });

  describe('the element it watches', () => {
    beforeEach(() => createComponent());

    it('is the note header row, not its own inline wrapper', () => {
      expect([...observed]).toEqual([resizesWith]);
    });

    it('ignores the observation the browser delivers on observe, which mount already handled', () => {
      expect(wrapper.emitted('overflow')).toHaveLength(1);
    });

    it('stops watching once the line is torn down', () => {
      wrapper.destroy();

      expect(observed.has(resizesWith)).toBe(false);
    });
  });

  describe('when a notification carries the same width as the last one', () => {
    beforeEach(() => createComponent({ room: FITS_NOTHING }));

    it('does not measure again, so letting the header wrap cannot bounce back', async () => {
      await resizeTo(FITS_SESSION_ONLY);
      const before = wrapper.emitted('overflow').length;

      await resizeTo(FITS_SESSION_ONLY);

      expect(wrapper.emitted('overflow')).toHaveLength(before);
    });
  });

  describe('when the line is rendered in the rapid diffs note header', () => {
    beforeEach(() =>
      createComponent({ room: FITS_SESSION_ONLY, headerClasses: RAPID_DIFFS_HEADER }),
    );

    it('watches the header row', () => {
      expect([...observed]).toEqual([resizesWith]);
    });

    it('shrinks the line to fit the row', () => {
      expect(findActorLine().props('withInitiator')).toBe(false);
    });

    describe('when the row grows back', () => {
      beforeEach(() => resizeTo(FITS_WHOLE_LINE));

      it('restores the line', () => {
        expect(findActorLine().props('withInitiator')).toBe(true);
      });
    });
  });

  describe('when the line is rendered outside a note header', () => {
    beforeEach(() => createComponent({ inNoteHeader: false }));

    it('watches nothing rather than measuring an unrelated element', () => {
      expect([...observed]).toEqual([]);
    });

    it('leaves the whole line in place', () => {
      expect(findActorLine().props('withInitiator')).toBe(true);
    });
  });
});
