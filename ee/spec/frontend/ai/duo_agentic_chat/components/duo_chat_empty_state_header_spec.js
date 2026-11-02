import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoChatEmptyStateHeader from 'ee/ai/duo_agentic_chat/components/duo_chat_empty_state_header.vue';

describe('DuoChatEmptyStateHeader', () => {
  let wrapper;

  const createComponent = ({ slots = {} } = {}) => {
    wrapper = shallowMountExtended(DuoChatEmptyStateHeader, { slots });
  };

  it('renders the default Duo Agent Platform copy', () => {
    createComponent();

    expect(wrapper.findByRole('heading').text()).toBe('GitLab Duo Agent Platform');
    expect(wrapper.find('p').text()).toBe(
      'Collaborate with AI agents to accomplish tasks and answer questions, or use a multi-agent flow to solve a complex problem.',
    );
  });

  it('renders slot content instead of the default copy', () => {
    createComponent({ slots: { default: '<h2>Custom heading</h2>' } });

    expect(wrapper.findByRole('heading').text()).toBe('Custom heading');
    expect(wrapper.find('p').exists()).toBe(false);
  });
});
