import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentSessionInboxItem from 'ee/ai/duo_agents_platform/panel/agent_session_inbox_item.vue';
import InboxRow from 'ee/ai/duo_agents_platform/panel/inbox_row.vue';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import { buildInboxRowItem } from '../../mocks';

describe('AgentSessionInboxItem', () => {
  let wrapper;

  const createWrapper = (item = buildInboxRowItem()) => {
    wrapper = shallowMountExtended(AgentSessionInboxItem, {
      propsData: { item },
      stubs: { InboxRow },
      mocks: { $router: { push: jest.fn() } },
    });
  };

  const findRow = () => wrapper.findComponent(InboxRow);
  const findStatusIcon = () => wrapper.findComponent(AgentStatusIcon);
  const findStatusLabel = () => wrapper.findByTestId('item-status-label');
  const findIconColumn = () => wrapper.findByTestId('item-icon');
  const findStatusContainer = () => wrapper.findByTestId('item-status');

  describe('row', () => {
    const item = buildInboxRowItem();

    beforeEach(() => {
      createWrapper(item);
    });

    it('hands the item to the row', () => {
      expect(findRow().props('item')).toBe(item);
    });

    it('renders the status icon in the icon column', () => {
      expect(findIconColumn().findComponent(AgentStatusIcon).exists()).toBe(true);
    });

    it('renders the status icon without a label', () => {
      expect(findStatusIcon().props('humanStatus')).toBeNull();
    });

    it('renders only the label in the status line', () => {
      expect(findStatusContainer().findComponent(AgentStatusIcon).exists()).toBe(false);
      expect(findStatusContainer().text()).toBe(findStatusLabel().text());
    });
  });

  describe('status label overrides', () => {
    describe.each([
      ['INPUT_REQUIRED', 'Waiting for input'],
      ['IDLE', 'Idle'],
      ['PLAN_APPROVAL_REQUIRED', 'Approval gate'],
      ['TOOL_CALL_APPROVAL_REQUIRED', 'Confirm action'],
      ['STOPPED', 'Canceled'],
    ])('when status is %s', (status, expectedLabel) => {
      beforeEach(() => {
        createWrapper(buildInboxRowItem({ status }));
      });

      it(`renders the "${expectedLabel}" label`, () => {
        expect(findStatusLabel().text()).toBe(expectedLabel);
      });
    });

    describe('when status is unmapped', () => {
      beforeEach(() => {
        createWrapper(buildInboxRowItem({ status: 'RUNNING', humanStatus: 'running' }));
      });

      it('renders the formatted humanStatus', () => {
        expect(findStatusLabel().text()).toBe('Running');
      });
    });

    describe('when status is unmapped and humanStatus is null', () => {
      beforeEach(() => {
        createWrapper(buildInboxRowItem({ status: 'RUNNING', humanStatus: null }));
      });

      it('renders "Unknown"', () => {
        expect(findStatusLabel().text()).toBe('Unknown');
      });
    });
  });

  describe('status colour (semantic token)', () => {
    describe.each([
      ['CREATED', 'gl-text-status-neutral'],
      ['RUNNING', 'gl-text-status-info'],
      ['FINISHED', 'gl-text-status-success'],
      ['PAUSED', 'gl-text-status-neutral'],
      ['STOPPED', 'gl-text-status-neutral'],
      ['INPUT_REQUIRED', 'gl-text-status-warning'],
      ['PLAN_APPROVAL_REQUIRED', 'gl-text-status-warning'],
      ['TOOL_CALL_APPROVAL_REQUIRED', 'gl-text-status-warning'],
      ['FAILED', 'gl-text-status-danger'],
      ['UNKNOWN_FUTURE_STATUS', 'gl-text-status-neutral'],
    ])('when status is %s', (status, expectedClass) => {
      beforeEach(() => {
        createWrapper(buildInboxRowItem({ status }));
      });

      it(`applies ${expectedClass}`, () => {
        expect(findStatusLabel().classes()).toContain(expectedClass);
      });
    });
  });
});
