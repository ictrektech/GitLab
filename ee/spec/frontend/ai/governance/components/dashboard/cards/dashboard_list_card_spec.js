import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import DashboardListCard from 'ee/ai/governance/components/dashboard/cards/dashboard_list_card.vue';

const CARD_LINK_EVENT = 'click_card_link_on_ai_governance_dashboard';

describe('DashboardListCard', () => {
  let wrapper;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const createComponent = (props = {}) => {
    wrapper = mountExtended(DashboardListCard, {
      propsData: {
        title: 'Most recent sessions',
        viewAllText: 'View all audit logs',
        viewAllHref: '?tab=agent-artifacts',
        ...props,
      },
      slots: {
        default: '<li data-testid="row">A row</li>',
      },
    });
  };

  const findViewAllLink = () => wrapper.findByTestId('view-all-link');

  it('renders the title, the rows and the view-all link', () => {
    createComponent();

    expect(wrapper.find('h2').text()).toBe('Most recent sessions');
    expect(wrapper.findByTestId('row').exists()).toBe(true);
    expect(findViewAllLink().attributes('aria-label')).toBe('View all audit logs');
    expect(findViewAllLink().text()).toBe('View all');
    expect(findViewAllLink().attributes('href')).toBe('?tab=agent-artifacts');
  });

  it('renders no view-all link without an href', () => {
    createComponent({ viewAllHref: null });

    expect(findViewAllLink().exists()).toBe(false);
  });

  describe('with a tracking label', () => {
    beforeEach(() => {
      createComponent({ trackingLabel: 'audit_trail' });
    });

    it('marks the view-all link as a card link click for that card', () => {
      expect(findViewAllLink().attributes()).toMatchObject({
        'data-event-tracking': CARD_LINK_EVENT,
        'data-event-label': 'audit_trail',
        'data-event-property': 'view_all',
      });
    });

    it('tracks a click on the view-all link with the card label', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent('[data-testid="view-all-link"]');

      expect(trackEventSpy).toHaveBeenCalledWith(CARD_LINK_EVENT, {
        label: 'audit_trail',
        property: 'view_all',
      });
    });
  });

  describe('without a tracking label', () => {
    beforeEach(() => {
      createComponent();
    });

    it('leaves the view-all link untracked', () => {
      const attributes = findViewAllLink().attributes();

      expect(attributes).not.toHaveProperty('data-event-tracking');
      expect(attributes).not.toHaveProperty('data-event-label');
      expect(attributes).not.toHaveProperty('data-event-property');
    });

    it('does not track a click on the view-all link', () => {
      const { triggerEvent, trackEventSpy } = bindInternalEventDocument(wrapper.element);

      triggerEvent('[data-testid="view-all-link"]');

      expect(trackEventSpy).not.toHaveBeenCalled();
    });
  });
});
