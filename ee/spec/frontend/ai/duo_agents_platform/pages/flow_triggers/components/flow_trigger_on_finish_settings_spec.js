import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox, GlFormCheckbox } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { createAlert } from '~/alert';
import namespaceWorkItemTypesQuery from '~/work_items/graphql/namespace_work_item_types.query.graphql';
import { namespaceWorkItemTypesQueryResponse } from 'jest/work_items/mock_data';
import FlowTriggerOnFinishSettings from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/flow_trigger_on_finish_settings.vue';

jest.mock('~/alert');
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('FlowTriggerOnFinishSettings', () => {
  let wrapper;
  let queryHandler;

  const createComponent = async (props = {}) => {
    wrapper = shallowMountExtended(FlowTriggerOnFinishSettings, {
      apolloProvider: createMockApollo([[namespaceWorkItemTypesQuery, queryHandler]]),
      provide: { projectPath: 'gitlab-org/gitlab-test' },
      propsData: {
        statusOnFinish: null,
        readyMergeRequestsOnFinish: false,
        disabled: false,
        triggerStatusNames: ['To do'],
        ...props,
      },
    });

    await waitForPromises();
  };

  const findDescription = () => wrapper.findByTestId('on-finish-description');
  const findStatusListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findReadyCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findRestartWarning = () => wrapper.findByTestId('on-finish-restart-warning');

  beforeEach(() => {
    queryHandler = jest.fn().mockResolvedValue(namespaceWorkItemTypesQueryResponse);
  });

  describe('when the trigger meets the on-finish rule', () => {
    beforeEach(async () => {
      await createComponent();
    });

    it('is a group named by its heading and described by its description', () => {
      expect(wrapper.attributes('role')).toBe('group');
      expect(wrapper.attributes('aria-labelledby')).toBe(wrapper.find('h2').attributes('id'));
      expect(wrapper.attributes('aria-describedby')).toBe(findDescription().attributes('id'));
    });

    it('describes what the settings do', () => {
      expect(findDescription().text()).toBe(
        'Update the work item and its merge requests after a session that this trigger started finishes.',
      );
    });

    it('enables both controls', () => {
      expect(findStatusListbox().props('disabled')).toBe(false);
      expect(findReadyCheckbox().attributes('disabled')).toBeUndefined();
    });

    it('fetches the statuses of the project', () => {
      expect(queryHandler).toHaveBeenCalledWith({ fullPath: 'gitlab-org/gitlab-test' });
    });

    it('lists each status name once', () => {
      const values = findStatusListbox()
        .props('items')
        .map((item) => item.value);

      expect(values).toEqual(expect.arrayContaining(['To do', 'In progress', 'Done']));
      expect(new Set(values).size).toBe(values.length);
    });

    it('shows "Do not change status" when no status is set', () => {
      expect(findStatusListbox().props('toggleText')).toBe('Do not change status');
    });

    it('emits the selected status', () => {
      findStatusListbox().vm.$emit('select', 'Done');

      expect(wrapper.emitted('update:status-on-finish')).toEqual([['Done']]);
    });

    it('emits null when the status is cleared', () => {
      findStatusListbox().vm.$emit('reset');

      expect(wrapper.emitted('update:status-on-finish')).toEqual([[null]]);
    });

    it('emits the checkbox value', () => {
      findReadyCheckbox().vm.$emit('change', true);

      expect(wrapper.emitted('update:ready-merge-requests-on-finish')).toEqual([[true]]);
    });
  });

  describe('when a status is set', () => {
    describe('and the trigger does not run on it', () => {
      beforeEach(async () => {
        await createComponent({ statusOnFinish: 'Done' });
      });

      it('shows the status', () => {
        expect(findStatusListbox().props('toggleText')).toBe('Done');
        expect(findStatusListbox().props('selected')).toBe('Done');
      });

      it('does not warn', () => {
        expect(findRestartWarning().exists()).toBe(false);
      });
    });

    describe('and the trigger runs on it', () => {
      beforeEach(async () => {
        await createComponent({ statusOnFinish: 'To do' });
      });

      it('warns that the trigger can start again', () => {
        expect(findRestartWarning().text()).toBe(
          'This trigger runs on this status, so setting it can start another session.',
        );
      });
    });
  });

  describe('when the trigger has a type rule', () => {
    beforeEach(async () => {
      await createComponent({ triggerWorkItemTypeIds: [5] });
    });

    // In namespaceWorkItemTypesQueryResponse, Task (5) has its own lifecycle.
    it('lists only the statuses of the selected types', () => {
      expect(findStatusListbox().props('items')).toEqual([
        { value: 'To do', text: 'To do' },
        { value: 'In dev', text: 'In dev' },
        { value: 'In review', text: 'In review' },
        { value: 'Complete', text: 'Complete' },
      ]);
    });
  });

  describe('when a stored status is not a status of the selected types', () => {
    beforeEach(async () => {
      await createComponent({ statusOnFinish: 'Done', triggerWorkItemTypeIds: [5] });
    });

    it('keeps the status on load', () => {
      expect(wrapper.emitted('update:status-on-finish')).toBeUndefined();
    });
  });

  // setProps stands in for the parent, which passes the type IDs of the edited filter.
  describe('when the selected types change', () => {
    describe('and the new types do not have the status', () => {
      beforeEach(async () => {
        await createComponent({ statusOnFinish: 'Done' });
        await wrapper.setProps({ triggerWorkItemTypeIds: [5] });
      });

      it('clears the status', () => {
        expect(wrapper.emitted('update:status-on-finish')).toEqual([[null]]);
      });
    });

    describe('and the new types have the status', () => {
      beforeEach(async () => {
        await createComponent({ statusOnFinish: 'In dev' });
        await wrapper.setProps({ triggerWorkItemTypeIds: [5] });
      });

      it('keeps the status', () => {
        expect(wrapper.emitted('update:status-on-finish')).toBeUndefined();
      });
    });

    // The parent passes a new array on every filter edit, also when the types stay the same.
    describe('to the same types', () => {
      beforeEach(async () => {
        await createComponent({ statusOnFinish: 'Done', triggerWorkItemTypeIds: [5] });
        await wrapper.setProps({ triggerWorkItemTypeIds: [5] });
      });

      it('keeps the status', () => {
        expect(wrapper.emitted('update:status-on-finish')).toBeUndefined();
      });
    });

    describe('after the status query fails', () => {
      beforeEach(async () => {
        queryHandler = jest.fn().mockRejectedValue(new Error('boom'));
        await createComponent({ statusOnFinish: 'Done' });
        await wrapper.setProps({ triggerWorkItemTypeIds: [5] });
      });

      it('keeps the status', () => {
        expect(wrapper.emitted('update:status-on-finish')).toBeUndefined();
      });
    });
  });

  describe('when the trigger does not meet the on-finish rule', () => {
    beforeEach(async () => {
      await createComponent({ disabled: true });
    });

    it('says what the settings need', () => {
      expect(findDescription().text()).toBe(
        'Available only when Status changed is the only selected work item action and at least one status is selected.',
      );
    });

    it('disables both controls', () => {
      expect(findStatusListbox().props('disabled')).toBe(true);
      expect(findReadyCheckbox().attributes('disabled')).toBeDefined();
    });

    it('does not fetch statuses', () => {
      expect(queryHandler).not.toHaveBeenCalled();
    });
  });

  describe('when the status query fails', () => {
    beforeEach(async () => {
      queryHandler = jest.fn().mockRejectedValue(new Error('boom'));
      await createComponent();
    });

    it('reports the error to Sentry without a page alert', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
      expect(createAlert).not.toHaveBeenCalled();
    });

    it('explains the empty list', () => {
      expect(findStatusListbox().props('noResultsText')).toBe(
        'Could not load statuses. Refresh the page to try again.',
      );
    });

    it('keeps the checkbox enabled', () => {
      expect(findReadyCheckbox().attributes('disabled')).toBeUndefined();
    });
  });
});
