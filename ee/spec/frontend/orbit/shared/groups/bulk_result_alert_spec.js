import { GlAlert } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import BulkResultAlert from 'ee/orbit/shared/groups/bulk_result_alert.vue';

describe('BulkResultAlert', () => {
  let wrapper;

  const createComponent = (result, props = {}) => {
    wrapper = shallowMountExtended(BulkResultAlert, { propsData: { result, ...props } });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);

  describe.each`
    action       | title
    ${'turnOn'}  | ${'GitLab Orbit is on for 3 groups'}
    ${'turnOff'} | ${'GitLab Orbit is off for 3 groups'}
    ${'exclude'} | ${'3 groups are excluded from automatic indexing'}
    ${'include'} | ${'3 groups are no longer excluded'}
  `('when $action succeeds', ({ action, title }) => {
    beforeEach(() => {
      createComponent({ action, total: 3, failed: [] });
    });

    it(`shows "${title}" and no retry button`, () => {
      expect(findAlert().props()).toMatchObject({ variant: 'info', title, primaryButtonText: '' });
    });
  });

  describe('when turn on succeeds', () => {
    beforeEach(() => {
      createComponent({ action: 'turnOn', total: 1, failed: [] });
    });

    it('explains how long indexing takes', () => {
      expect(findAlert().text()).toContain('Indexing starts in a few minutes');
    });
  });

  describe('when some groups fail', () => {
    beforeEach(() => {
      createComponent({
        action: 'turnOn',
        total: 3,
        failed: [{ name: 'Acme', fullPath: 'acme', message: 'Not allowed' }],
      });
    });

    it('lists each failed group by full path with its reason', () => {
      expect(findAlert().props()).toMatchObject({
        variant: 'danger',
        title: '1 of 3 groups was not updated',
        primaryButtonText: 'Try again',
      });
      expect(findAlert().text()).toContain('acme: Not allowed');
    });

    it('emits retry from Try again', () => {
      findAlert().vm.$emit('primary-action');

      expect(wrapper.emitted('retry')).toEqual([[]]);
    });
  });

  describe('when some groups fail and none can be retried', () => {
    beforeEach(() => {
      createComponent(
        {
          action: 'turnOn',
          total: 1,
          failed: [{ name: 'Acme', fullPath: 'acme', message: 'Not eligible.' }],
        },
        { canRetry: false },
      );
    });

    it('lists the failed group with no Try again', () => {
      expect(findAlert().props('primaryButtonText')).toBe('');
      expect(findAlert().text()).toContain('acme: Not eligible.');
    });
  });

  describe('when more groups fail than the alert lists', () => {
    beforeEach(() => {
      const failed = Array.from({ length: 7 }, (_, index) => ({
        name: 'Twin',
        fullPath: `twin-${index}`,
        message: 'Not allowed',
      }));
      createComponent({ action: 'turnOff', total: 7, failed });
    });

    it('lists the first 5 groups and counts the others', () => {
      expect(wrapper.findAll('li')).toHaveLength(6);
      expect(findAlert().text()).toContain('twin-4: Not allowed');
      expect(findAlert().text()).not.toContain('twin-5');
      expect(wrapper.findByTestId('unlisted-failures').text()).toBe('And 2 more groups');
    });
  });
});
