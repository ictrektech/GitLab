import { GlPopover, GlButton, GlSkeletonLoader } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import BoardCardSessionBadgePopover from 'ee/boards/components/board_card_session_badge_popover.vue';
import BoardCardSessionBadgeRow from 'ee/boards/components/board_card_session_badge_row.vue';
import {
  buildSession,
  FINISHED_SESSION,
  RUNNING_SESSION,
} from './board_card_session_badge_mock_data';

describe('BoardCardSessionBadgePopover', () => {
  let wrapper;

  const defaultProps = {
    target: 'session-badge-1',
    sessions: [FINISHED_SESSION, RUNNING_SESSION],
    isLoading: false,
    queryError: false,
    hasNextPage: false,
    displayCount: '2',
  };

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(BoardCardSessionBadgePopover, {
      attachTo: document.body,
      propsData: { ...defaultProps, ...props },
    });
  };

  const findPopover = () => wrapper.findComponent(GlPopover);
  const findPopoverBody = () => wrapper.findByTestId('popover-body');
  const findSessionRows = () => wrapper.findAllComponents(BoardCardSessionBadgeRow);
  const findViewAllLink = () => wrapper.findComponentByTestId('popover-view-all-link');

  describe('popover wiring', () => {
    beforeEach(() => {
      createComponent();
    });

    it('targets the provided ID with click trigger', () => {
      expect(findPopover().props('target')).toBe('session-badge-1');
      expect(findPopover().props('triggers')).toBe('click blur');
    });
  });

  describe('with sessions loaded', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a row per session', () => {
      expect(findSessionRows()).toHaveLength(2);
      expect(findSessionRows().at(0).props('session')).toEqual(FINISHED_SESSION);
      expect(findSessionRows().at(1).props('session')).toEqual(RUNNING_SESSION);
    });

    it('re-emits show-session from a row', () => {
      findSessionRows().at(1).vm.$emit('show-session', RUNNING_SESSION);

      expect(wrapper.emitted('show-session')).toEqual([[RUNNING_SESSION]]);
    });

    it('emits view-all when "View all sessions" is clicked', () => {
      const event = { preventDefault: jest.fn() };
      findViewAllLink().vm.$emit('click', event);

      expect(event.preventDefault).toHaveBeenCalled();
      expect(wrapper.emitted('view-all')).toHaveLength(1);
    });

    it('renders the "View all sessions" footer link', () => {
      expect(findViewAllLink().text()).toBe('View all sessions');
    });
  });

  describe('when hasNextPage is true', () => {
    beforeEach(() => {
      const nodes = Array.from({ length: 5 }, (_, i) =>
        buildSession({ id: `gid://gitlab/Ai::DuoWorkflows::Workflow/${i + 1}` }),
      );
      createComponent({ sessions: nodes, hasNextPage: true, displayCount: '5+' });
    });

    it('shows "Showing most recent 5" in the footer', () => {
      expect(wrapper.findByTestId('popover-showing-first').text()).toContain(
        'Showing most recent 5',
      );
    });
  });

  describe('when hasNextPage is false', () => {
    beforeEach(() => {
      createComponent();
    });

    it('does not show "Showing first" text', () => {
      expect(wrapper.findByTestId('popover-showing-first').exists()).toBe(false);
    });
  });

  describe('when loading', () => {
    beforeEach(() => {
      createComponent({ isLoading: true, sessions: [] });
    });

    it('shows a skeleton loader', () => {
      expect(wrapper.findComponent(GlSkeletonLoader).exists()).toBe(true);
    });

    it('does not show session rows', () => {
      expect(findSessionRows()).toHaveLength(0);
    });
  });

  describe('when query errored', () => {
    beforeEach(() => {
      createComponent({ queryError: true, sessions: [] });
    });

    it('shows error message', () => {
      expect(wrapper.findByTestId('popover-error').text()).toContain("Couldn't load sessions.");
    });

    it('shows a retry button that emits retry', async () => {
      const retryButton = wrapper.findComponent(GlButton);

      expect(retryButton.text()).toBe('Retry');

      await retryButton.vm.$emit('click');

      expect(wrapper.emitted('retry')).toHaveLength(1);
    });
  });

  describe('keyboard handling', () => {
    let tip;

    const buildTip = ({ show = true, html = '' } = {}) => {
      tip = document.createElement('div');
      tip.className = show ? 'popover show' : 'popover';
      tip.innerHTML = html;
      document.body.appendChild(tip);
      return tip;
    };

    afterEach(() => {
      tip?.remove();
    });

    const emitShown = (event) => findPopover().vm.$emit('shown', event);

    beforeEach(() => {
      createComponent();
    });

    describe('when Escape is pressed inside the popover body', () => {
      beforeEach(async () => {
        await findPopoverBody().trigger('keydown.esc');
      });

      it('emits close', () => {
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('when the popover is shown', () => {
      describe('with a focusable element in the tip', () => {
        beforeEach(() => {
          buildTip({
            html: '<a id="first" href="/one">One</a><a id="second" href="/two">Two</a>',
          });
          emitShown({ relatedTarget: tip });
        });

        it('moves focus to the first link', () => {
          expect(document.activeElement).toBe(tip.querySelector('#first'));
        });
      });

      describe('with nothing focusable in the tip', () => {
        beforeEach(() => {
          buildTip();
          emitShown({ relatedTarget: tip });
        });

        it('focuses the popover body', () => {
          expect(document.activeElement).toBe(findPopoverBody().element);
        });
      });

      describe('when the tip is no longer shown', () => {
        let previous;

        beforeEach(() => {
          buildTip({ show: false, html: '<a id="first" href="/one">One</a>' });
          previous = document.activeElement;
          emitShown({ relatedTarget: tip });
        });

        it('does not move focus', () => {
          expect(document.activeElement).toBe(previous);
        });
      });

      describe('without a tip', () => {
        it('does not throw', () => {
          expect(() => emitShown({})).not.toThrow();
        });
      });
    });
  });
});
