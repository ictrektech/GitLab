import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import StatusChecksPage from 'ee/merge_requests/reports/status_checks/status_checks_page.vue';
import StatusChecksProvider from 'ee/merge_requests/reports/status_checks/status_checks_provider.vue';
import StatusChecksContent from 'ee/merge_requests/reports/status_checks/status_checks_content.vue';

describe('StatusChecksPage', () => {
  let wrapper;

  const DEFAULT_MR_PROP = { id: 1 };

  const findProvider = () => wrapper.findComponent(StatusChecksProvider);
  const findContent = () => wrapper.findComponent(StatusChecksContent);

  const createComponent = () => {
    wrapper = shallowMountExtended(StatusChecksPage, {
      propsData: {
        mr: DEFAULT_MR_PROP,
      },
    });
  };

  beforeEach(() => {
    createComponent();
  });

  it('renders StatusChecksProvider with mr prop and StatusChecksContent inside it', () => {
    expect(findProvider().props('mr')).toBe(DEFAULT_MR_PROP);
    expect(findContent().exists()).toBe(true);
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks view_merge_request_report on mount', () => {
      createComponent();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_merge_request_report',
        { label: 'status_checks' },
        undefined,
      );
    });
  });
});
