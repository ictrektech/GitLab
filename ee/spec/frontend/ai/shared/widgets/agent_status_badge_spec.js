import { GlBadge } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentStatusBadge from 'ee/ai/shared/widgets/agent_status_badge.vue';

describe('AgentStatusBadge', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AgentStatusBadge, {
      propsData: {
        status: 'RUNNING',
        humanStatus: 'Running',
        ...props,
      },
    });
  };

  const findBadge = () => wrapper.findComponent(GlBadge);

  describe('when rendered with a human-readable status', () => {
    beforeEach(() => {
      createComponent({ status: 'FINISHED', humanStatus: 'Finished' });
    });

    it('renders it as the badge text', () => {
      expect(findBadge().text()).toBe('Finished');
    });

    it('renders a small icon', () => {
      expect(findBadge().props('iconSize')).toBe('sm');
    });
  });

  describe.each`
    status                           | expectedIcon          | expectedVariant
    ${'CREATED'}                     | ${'status-waiting'}   | ${'neutral'}
    ${'RUNNING'}                     | ${'status-running'}   | ${'info'}
    ${'FINISHED'}                    | ${'status-success'}   | ${'success'}
    ${'PAUSED'}                      | ${'status-paused'}    | ${'neutral'}
    ${'STOPPED'}                     | ${'status-cancelled'} | ${'neutral'}
    ${'INPUT_REQUIRED'}              | ${'status-alert'}     | ${'warning'}
    ${'PLAN_APPROVAL_REQUIRED'}      | ${'status-alert'}     | ${'warning'}
    ${'TOOL_CALL_APPROVAL_REQUIRED'} | ${'status-alert'}     | ${'warning'}
    ${'FAILED'}                      | ${'status-failed'}    | ${'danger'}
  `('when status is $status', ({ status, expectedIcon, expectedVariant }) => {
    beforeEach(() => {
      createComponent({ status });
    });

    it(`renders the ${expectedIcon} icon`, () => {
      expect(findBadge().props('icon')).toBe(expectedIcon);
    });

    it(`renders the ${expectedVariant} variant`, () => {
      expect(findBadge().props('variant')).toBe(expectedVariant);
    });
  });

  describe('when status is unknown', () => {
    beforeEach(() => {
      createComponent({ status: 'SOMETHING_NEW' });
    });

    it('falls back to the unknown icon', () => {
      expect(findBadge().props('icon')).toBe('status-neutral');
    });

    it('falls back to the neutral variant', () => {
      expect(findBadge().props('variant')).toBe('neutral');
    });
  });
});
