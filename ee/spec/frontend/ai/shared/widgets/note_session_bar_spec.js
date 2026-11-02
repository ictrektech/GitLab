import { GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import NoteSessionBar from 'ee/ai/shared/widgets/note_session_bar.vue';
import { eventHub, SHOW_SESSION } from 'ee/ai/events/panel';

describe('NoteSessionBar component', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(NoteSessionBar, {
      propsData: {
        agentName: 'Code Review',
        sessionId: 'gid://gitlab/DuoWorkflow/42',
        isReply: false,
        ...props,
      },
      stubs: { GlSprintf },
    });
  };

  const findWrapper = () => wrapper.findByTestId('note-session-bar-wrapper');
  const findBar = () => wrapper.findByTestId('note-session-bar');
  const findText = () => wrapper.findByTestId('note-session-bar-text');
  const findSpinner = () => wrapper.findByTestId('note-session-bar-spinner');
  const findStatusIcon = () => wrapper.findComponentByTestId('note-session-bar-status-icon');

  describe.each([null, 'finished'])('when status is %s', (status) => {
    beforeEach(() => createComponent({ status }));

    it('does not render the bar', () => {
      expect(findBar().exists()).toBe(false);
    });
  });

  describe('when the bar is visible', () => {
    beforeEach(() => createComponent({ status: 'created' }));

    it('has a "View session" aria-label including the session id', () => {
      expect(findBar().attributes('aria-label')).toBe('View session #42');
    });

    describe('when the bar is clicked', () => {
      beforeEach(() => {
        jest.spyOn(eventHub, '$emit');
        findBar().trigger('click');
      });

      it('emits SHOW_SESSION with the numeric session id', () => {
        expect(eventHub.$emit).toHaveBeenCalledWith(SHOW_SESSION, { id: 42 });
      });
    });
  });

  describe('when isReply is true', () => {
    beforeEach(() => createComponent({ status: 'running', isReply: true }));

    it('renders the bar as a bordered, rounded button', () => {
      expect(findWrapper().classes()).toContain('gl-mr-3');
      expect(findWrapper().classes()).not.toContain('gl-border-t');
      expect(findBar().classes()).toEqual(
        expect.arrayContaining(['gl-border-1', 'gl-rounded-base']),
      );
    });
  });

  describe('when isReply is false', () => {
    beforeEach(() => createComponent({ status: 'running', isReply: false }));

    it('renders a top border on the wrapper', () => {
      expect(findWrapper().classes()).toEqual(
        expect.arrayContaining(['gl-border-t', 'gl-border-t-solid']),
      );
      expect(findWrapper().classes()).not.toContain('gl-mr-3');
    });
  });

  describe.each(['created', 'running'])('when status is %s', (status) => {
    beforeEach(() => {
      jest.spyOn(Math, 'random').mockReturnValue(0);
      createComponent({ status });
    });

    it('shows a loading spinner instead of a status icon', () => {
      expect(findSpinner().exists()).toBe(true);
      expect(findStatusIcon().exists()).toBe(false);
    });

    it('renders the agent name in bold within the running phrase', () => {
      expect(findText().find('strong').text()).toBe('Code Review');
      expect(findText().text()).toBe('Code Review is investigating...');
    });
  });

  describe.each`
    status                           | icon                  | variant      | phrase
    ${'paused'}                      | ${'status-paused'}    | ${'subtle'}  | ${'Code Review session is paused'}
    ${'input_required'}              | ${'status-alert'}     | ${'warning'} | ${'Code Review needs input'}
    ${'plan_approval_required'}      | ${'status-alert'}     | ${'warning'} | ${'Code Review needs input'}
    ${'tool_call_approval_required'} | ${'status-alert'}     | ${'warning'} | ${'Code Review needs input'}
    ${'failed'}                      | ${'status-failed'}    | ${'danger'}  | ${'Code Review failed to complete this task'}
    ${'stopped'}                     | ${'status-cancelled'} | ${'subtle'}  | ${'Code Review session was canceled'}
  `('when status is $status', ({ status, icon, variant, phrase }) => {
    beforeEach(() => createComponent({ status }));

    it(`shows the ${icon} icon with the ${variant} variant instead of a spinner`, () => {
      expect(findStatusIcon().props()).toMatchObject({ name: icon, variant, size: 12 });
      expect(findSpinner().exists()).toBe(false);
    });

    it('renders the agent name in bold within the status phrase', () => {
      expect(findText().find('strong').text()).toBe('Code Review');
      expect(findText().text()).toBe(phrase);
    });
  });
});
