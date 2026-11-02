import { GlLink } from '@gitlab/ui';
import { nextTick } from 'vue';
import {
  shallowMountExtended,
  mountExtended,
  extendedWrapper,
} from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { hideGlTooltip, showGlTooltip } from '~/vue_shared/utils/tooltips';
import InboxRow from 'ee/ai/duo_agents_platform/panel/inbox_row.vue';
import { AGENTS_PLATFORM_SHOW_ROUTE } from 'ee/ai/duo_agents_platform/router/constants';
import { buildInboxRowItem } from '../../mocks';

jest.mock('~/vue_shared/utils/tooltips');

describe('InboxRow', () => {
  let wrapper;
  let mockRouter;

  beforeEach(() => {
    mockRouter = { push: jest.fn() };
  });

  const createWrapper = ({
    item = buildInboxRowItem(),
    slots = { status: '<span data-testid="slotted-status">Status</span>' },
    mountFn = shallowMountExtended,
    attachTo,
  } = {}) => {
    wrapper = mountFn(InboxRow, {
      attachTo,
      propsData: { item },
      slots,
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      mocks: { $router: mockRouter },
    });
  };

  const findLink = () => wrapper.findComponent(GlLink);
  const findTitle = () => wrapper.findByTestId('item-title');
  const findUpdatedDate = () => wrapper.findComponentByTestId('item-updated-date');
  const findMetadata = () => wrapper.findByTestId('item-metadata');
  const findIconColumn = () => wrapper.findByTestId('item-icon');

  describe('link', () => {
    beforeEach(() => createWrapper());

    it('points at the session page in the project', () => {
      expect(findLink().attributes('href')).toBe(
        '/gitlab-org/test-project/-/automate/agent-sessions/42',
      );
    });

    it('has no href when the project is null', () => {
      createWrapper({ item: buildInboxRowItem({ project: null }) });

      expect(findLink().attributes('href')).toBeUndefined();
    });
  });

  describe('default content', () => {
    beforeEach(() => createWrapper());

    it('renders the status slot in the header line', () => {
      expect(wrapper.findByTestId('slotted-status').text()).toBe('Status');
    });

    it('renders no icon column', () => {
      expect(findIconColumn().exists()).toBe(false);
    });

    it('renders the session title', () => {
      expect(findTitle().text()).toBe('Fix the login bug');
    });

    it('tooltips the title with the title and session ID, so the tooltip sits over the title', () => {
      expect(getBinding(findTitle().element, 'gl-tooltip')).toBeDefined();
      expect(findTitle().attributes('title')).toBe('Fix the login bug 42');
      expect(findTitle().attributes('id')).toMatch(/^agent-session-title-\d+$/);
      expect(findLink().attributes('title')).toBeUndefined();
    });

    it('shows the title tooltip when the link gains focus', async () => {
      await findLink().vm.$emit('focus');

      expect(showGlTooltip).toHaveBeenCalledWith(expect.anything(), findTitle().attributes('id'));
    });

    it('hides the title tooltip when the link loses focus', async () => {
      await findLink().vm.$emit('blur');

      expect(hideGlTooltip).toHaveBeenCalledWith(expect.anything(), findTitle().attributes('id'));
    });

    it('renders the age as a TimeAgoTooltip', () => {
      expect(findUpdatedDate().props('time')).toBe('2024-01-01T00:00:00Z');
    });

    it('renders the metadata line with session ID, flow name, and project name', () => {
      expect(findMetadata().text()).toMatchInterpolatedText(
        'Session 42 · Software development · Test Project',
      );
    });

    it('hides the "Session" label visually but keeps it for screen readers', () => {
      expect(wrapper.findByTestId('item-session-label').classes()).toContain('gl-sr-only');
    });
  });

  describe('keyboard focus inside the row', () => {
    beforeEach(() => createWrapper({ mountFn: mountExtended, attachTo: document.body }));

    it('shows the title tooltip when the link itself is focused', async () => {
      findLink().element.focus();
      await nextTick();

      expect(showGlTooltip).toHaveBeenCalledWith(expect.anything(), findTitle().attributes('id'));
    });

    it('leaves the title tooltip hidden when the timestamp is focused, since it has its own', async () => {
      findUpdatedDate().find('time').element.focus();
      await nextTick();

      expect(showGlTooltip).not.toHaveBeenCalled();
    });
  });

  describe('when the status slot is empty', () => {
    beforeEach(() => createWrapper({ slots: {} }));

    it('renders no status container', () => {
      expect(wrapper.findByTestId('item-status').exists()).toBe(false);
    });
  });

  describe('when an icon slot is provided', () => {
    beforeEach(() => createWrapper({ slots: { icon: '<i data-testid="slotted-icon"></i>' } }));

    it('renders the icon slot in its own column', () => {
      expect(extendedWrapper(findIconColumn()).findByTestId('slotted-icon').exists()).toBe(true);
    });
  });

  describe('when project is null', () => {
    beforeEach(() => createWrapper({ item: buildInboxRowItem({ project: null }) }));

    it('renders the metadata line without the project name, and does not throw', () => {
      expect(findMetadata().exists()).toBe(true);
      expect(findMetadata().text()).not.toContain('Test Project');
    });
  });

  describe('when the session ran a catalog item', () => {
    beforeEach(() =>
      createWrapper({
        item: buildInboxRowItem({
          workflowDefinition: 'ai_catalog_agent',
          aiCatalogItem: { id: 'gid://gitlab/Ai::Catalog::Item/69', name: 'Issue Smoke Test' },
        }),
      }),
    );

    it('renders the catalog item name as the flow name', () => {
      expect(findMetadata().text()).toContain('Issue Smoke Test');
    });
  });

  describe('when the session has no catalog item', () => {
    beforeEach(() =>
      createWrapper({
        item: buildInboxRowItem({ workflowDefinition: 'ai_catalog_agent', aiCatalogItem: null }),
      }),
    );

    it('falls back to the humanized workflow definition', () => {
      expect(findMetadata().text()).toContain('Ai catalog agent');
    });
  });

  describe.each([null, ''])('when the title is %p', (title) => {
    beforeEach(() => createWrapper({ item: buildInboxRowItem({ title }) }));

    it('falls back to the humanized workflow definition', () => {
      expect(findTitle().text()).toBe('Software development');
    });

    it('tooltips the title with the fallback title and session ID', () => {
      expect(findTitle().attributes('title')).toBe('Software development 42');
    });
  });

  describe('slot overrides', () => {
    it.each`
      slot          | replaces
      ${'title'}    | ${'item-title'}
      ${'trailing'} | ${'item-updated-date'}
      ${'metadata'} | ${'item-metadata'}
    `('the $slot slot replaces the default $replaces content', ({ slot, replaces }) => {
      createWrapper({ slots: { [slot]: `<b data-testid="slotted-${slot}">x</b>` } });

      expect(wrapper.findByTestId(`slotted-${slot}`).exists()).toBe(true);
      expect(wrapper.findByTestId(replaces).exists()).toBe(false);
    });
  });

  describe('when a default slot is provided', () => {
    beforeEach(() =>
      createWrapper({ slots: { default: '<p data-testid="slotted-body">note</p>' } }),
    );

    it('renders the default slot between the title and the metadata line', () => {
      const { children } = findTitle().element.parentElement;
      const indexOf = (testid) =>
        Array.from(children).findIndex((el) => el.dataset.testid === testid);

      expect(indexOf('slotted-body')).toBeGreaterThan(indexOf('item-title'));
      expect(indexOf('slotted-body')).toBeLessThan(indexOf('item-metadata'));
    });
  });

  describe('navigation', () => {
    beforeEach(() => createWrapper());

    it('calls preventDefault and router.push on a plain click', async () => {
      const event = { metaKey: false, ctrlKey: false, shiftKey: false, preventDefault: jest.fn() };
      await findLink().vm.$emit('click', event);

      expect(event.preventDefault).toHaveBeenCalledTimes(1);
      expect(mockRouter.push).toHaveBeenCalledWith({
        name: AGENTS_PLATFORM_SHOW_ROUTE,
        params: { id: 42 },
      });
    });

    describe.each(['metaKey', 'ctrlKey', 'shiftKey'])('when %s is pressed', (modifier) => {
      let event;

      beforeEach(async () => {
        event = {
          metaKey: false,
          ctrlKey: false,
          shiftKey: false,
          [modifier]: true,
          preventDefault: jest.fn(),
        };
        await findLink().vm.$emit('click', event);
      });

      it('leaves the default alone, so the browser opens the href in a new tab', () => {
        expect(event.preventDefault).not.toHaveBeenCalled();
      });

      it('does not navigate inside the panel', () => {
        expect(mockRouter.push).not.toHaveBeenCalled();
      });
    });
  });
});
