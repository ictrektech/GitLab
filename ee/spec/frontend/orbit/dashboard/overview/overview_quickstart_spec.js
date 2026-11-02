import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { sendDuoChatCommand, setAgenticMode } from 'ee/ai/utils';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import OverviewQuickstart from 'ee/orbit/dashboard/overview/overview_quickstart.vue';

jest.mock('ee/ai/utils', () => ({ sendDuoChatCommand: jest.fn(), setAgenticMode: jest.fn() }));

const VALUE_PROMPT =
  'Show me what you can answer with GitLab Orbit that you cannot answer without it: one real example from my work that spans more than one project, and nothing else. Then suggest three short questions I can ask you next, with real names from my projects.';

describe('OverviewQuickstart', () => {
  let wrapper;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const mountQuickstart = (props = {}) => {
    wrapper = mountExtended(OverviewQuickstart, {
      propsData: { duoAccessible: true, orbitSettingsEnabled: true, indexing: false, ...props },
      provide: { preferencesPath: '/-/profile/preferences' },
    });
  };

  const findOptionTitles = () => wrapper.findAll('h3').wrappers.map((h) => h.text());
  const findPreferences = () => wrapper.findByTestId('orbit-quickstart-preferences');
  const findTurnOn = () => wrapper.findByTestId('orbit-quickstart-turn-on');
  const findAskDuo = () => wrapper.findByTestId('orbit-quickstart-ask-duo');
  const findDuoText = () =>
    wrapper
      .findByTestId('orbit-quickstart-duo')
      .find('[data-testid="quickstart-option-description"]')
      .text();

  describe('when mounted', () => {
    beforeEach(() => mountQuickstart());

    it('shows the GitLab Duo and agents options, the CLI command, and the docs links', () => {
      expect(findOptionTitles()).toEqual([
        'Use GitLab Orbit in GitLab Duo',
        'Use GitLab Orbit with your own agents',
      ]);
      expect(wrapper.findByTestId('orbit-quickstart-subtitle').exists()).toBe(true);
      expect(wrapper.text()).toContain('glab orbit setup');
      expect(wrapper.findByTestId('orbit-quickstart-docs').attributes('href')).toBe(
        'https://docs.gitlab.com/orbit/',
      );
      expect(wrapper.findByTestId('orbit-quickstart-mcp-docs').text()).toBe(
        'Connect an MCP client',
      );
      expect(wrapper.findByTestId('orbit-quickstart-mcp-docs').attributes('href')).toBe(
        'https://docs.gitlab.com/orbit/remote/access/mcp/',
      );
    });
  });

  describe('when Duo is reachable and the opt-in is on', () => {
    beforeEach(() => mountQuickstart({ orbitSettingsEnabled: true }));

    it('offers Ask GitLab Duo and no turn-on hint', () => {
      expect(findAskDuo().exists()).toBe(true);
      expect(findTurnOn().exists()).toBe(false);
    });
  });

  describe('when Duo is reachable and the opt-in is off', () => {
    beforeEach(() => mountQuickstart({ orbitSettingsEnabled: false }));

    it('links to the preferences to turn on Orbit, and offers no Ask GitLab Duo', () => {
      expect(findTurnOn().text()).toBe(
        'To use GitLab Orbit in GitLab Duo, turn it on in your preferences.',
      );
      expect(findPreferences().attributes('href')).toBe('/-/profile/preferences');
      expect(findAskDuo().exists()).toBe(false);
    });
  });

  describe.each`
    indexing | text
    ${false} | ${'Ask GitLab Duo a question that spans projects.'}
    ${true}  | ${'When indexing finishes, ask GitLab Duo a question that spans projects.'}
  `('when indexing is $indexing', ({ indexing, text }) => {
    beforeEach(() => mountQuickstart({ indexing }));

    it('shows the matching GitLab Duo text', () => {
      expect(findDuoText()).toBe(text);
    });
  });

  describe('when GitLab Duo is not available', () => {
    beforeEach(() => mountQuickstart({ duoAccessible: false }));

    it('shows only the agents option, with no subtitle', () => {
      expect(findOptionTitles()).toEqual(['Use GitLab Orbit with your own agents']);
      expect(wrapper.findByTestId('orbit-quickstart-duo').exists()).toBe(false);
      expect(wrapper.findByTestId('orbit-quickstart-subtitle').exists()).toBe(false);
    });
  });

  describe('when the user clicks Ask GitLab Duo', () => {
    let trackEventSpy;

    beforeEach(() => {
      mountQuickstart();
      ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
    });

    it('tracks the click and sends the Orbit value prompt to the GitLab Duo agent in agentic mode', async () => {
      expect(setAgenticMode).not.toHaveBeenCalled();
      expect(sendDuoChatCommand).not.toHaveBeenCalled();
      expect(trackEventSpy).not.toHaveBeenCalled();

      await findAskDuo().trigger('click');
      await waitForPromises();

      expect(trackEventSpy).toHaveBeenCalledWith('click_orbit_open_duo_chat', {}, undefined);
      expect(setAgenticMode).toHaveBeenCalled();
      expect(sendDuoChatCommand).toHaveBeenCalledWith({
        question: VALUE_PROMPT,
        agenticPrompt: VALUE_PROMPT,
        resourceId: 'orbit-quickstart',
        agent: { name: 'GitLab Duo' },
      });
    });
  });

  describe('when the user copies the CLI command', () => {
    let trackEventSpy;

    beforeEach(() => {
      mountQuickstart();
      ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
    });

    it('tracks the copy with the CLI label', () => {
      expect(trackEventSpy).not.toHaveBeenCalled();

      wrapper.findComponent(ClipboardButton).vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_orbit_copy_to_clipboard',
        { label: 'CLI' },
        undefined,
      );
    });
  });
});
