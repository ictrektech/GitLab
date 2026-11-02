import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentSessionRetentionNotice from 'ee/ai/duo_agents_platform/components/common/agent_session_retention_notice.vue';

describe('AgentSessionRetentionNotice', () => {
  let wrapper;

  const findNotice = () => wrapper.findByTestId('retention-notice');

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(AgentSessionRetentionNotice, {
      propsData: props,
    });
  };

  it('renders the retention notice copy', () => {
    createWrapper();

    expect(findNotice().text()).toBe('Inactive sessions are archived after 30 days.');
  });

  describe('when sidePanel is false', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('applies the full page styling', () => {
      expect(findNotice().classes()).toContain('gl-mb-5');
      expect(findNotice().classes()).not.toContain('gl-sticky');
    });
  });

  describe('when sidePanel is true', () => {
    beforeEach(() => {
      createWrapper({ sidePanel: true });
    });

    it('applies the sticky side panel styling', () => {
      expect(findNotice().classes()).toContain('gl-sticky');
      expect(findNotice().classes()).not.toContain('gl-mb-5');
    });
  });
});
