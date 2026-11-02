import { GlIcon } from '@gitlab/ui';
import { mount } from '@vue/test-utils';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';

describe('AgentStatusIcon', () => {
  let wrapper;

  const createWrapper = (props = {}) => {
    wrapper = mount(AgentStatusIcon, {
      propsData: {
        ...props,
      },
      stubs: {
        GlIcon,
      },
    });
  };

  const findStatusIcon = () => wrapper.findComponent(GlIcon);

  describe('accessible name', () => {
    it('labels the icon with humanStatus when provided', () => {
      createWrapper({ status: 'RUNNING', humanStatus: 'Running' });

      expect(findStatusIcon().attributes('aria-label')).toBe('Running');
      expect(findStatusIcon().attributes('aria-hidden')).toBeUndefined();
    });

    it('hides the icon from screen readers when humanStatus is omitted', () => {
      createWrapper({ status: 'RUNNING' });

      expect(findStatusIcon().attributes('aria-label')).toBeUndefined();
      expect(findStatusIcon().attributes('aria-hidden')).toBe('true');
    });
  });

  describe('when status is not provided', () => {
    beforeEach(() => {
      createWrapper({ status: '', humanStatus: '' });
    });

    it('renders the unknown state icon', () => {
      expect(findStatusIcon().props('name')).toBe('status-neutral');
    });

    it('renders the subtle icon variant', () => {
      expect(findStatusIcon().props('variant')).toBe('subtle');
    });
  });

  describe.each`
    status        | expectedIcon        | expectedVariant
    ${'CREATED'}  | ${'status-waiting'} | ${'subtle'}
    ${'RUNNING'}  | ${'status-running'} | ${'info'}
    ${'FINISHED'} | ${'status-success'} | ${'success'}
    ${'PAUSED'}   | ${'status-paused'}  | ${'subtle'}
    ${'FAILED'}   | ${'status-failed'}  | ${'danger'}
  `('when status is $status', ({ status, expectedIcon, expectedVariant }) => {
    beforeEach(() => {
      createWrapper({ status, humanStatus: status.toLowerCase() });
    });

    it(`renders the ${expectedIcon} icon`, () => {
      expect(findStatusIcon().props('name')).toBe(expectedIcon);
    });

    it(`renders the ${expectedVariant} icon variant`, () => {
      expect(findStatusIcon().props('variant')).toBe(expectedVariant);
    });

    it('renders a 12px icon', () => {
      expect(findStatusIcon().props('size')).toBe(12);
    });
  });
});
