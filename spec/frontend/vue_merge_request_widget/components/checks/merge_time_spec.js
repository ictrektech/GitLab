import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import MergeTimeComponent from '~/vue_merge_request_widget/components/checks/merge_time.vue';
import StatusIcon from '~/vue_merge_request_widget/components/widget/status_icon.vue';
import mergeTimeQuery from '~/vue_merge_request_widget/queries/states/merge_time.query.graphql';

Vue.use(VueApollo);

const MR_PROPS = {
  targetProjectFullPath: 'gitlab',
  iid: '1',
  targetBranch: 'main',
};

const MERGE_AFTER = '2024-10-17T18:23:00Z';
const MERGE_BEFORE = '2024-10-18T09:00:00Z';

let wrapper;

function factory({ mrData = {}, check = { status: 'failed', identifier: 'merge_time' } } = {}) {
  const apolloProvider = createMockApollo([
    [
      mergeTimeQuery,
      jest.fn().mockResolvedValue({
        data: {
          project: {
            id: 1,
            mergeRequest: {
              id: 1,
              mergeAfter: mrData.mergeAfter ?? null,
              mergeBefore: mrData.mergeBefore ?? null,
            },
          },
        },
      }),
    ],
  ]);

  wrapper = mountExtended(MergeTimeComponent, {
    propsData: {
      check,
      mr: { ...MR_PROPS, ...mrData },
    },
    apolloProvider,
  });
}

describe('Merge request merge checks merge time component', () => {
  describe('failure reason text', () => {
    it('renders merge_after-only message', async () => {
      factory({ mrData: { mergeAfter: MERGE_AFTER } });
      await waitForPromises();

      expect(wrapper.text()).toBe('Merge must be after Oct 17, 2024, 6:23 PM');
    });

    it('renders both merge_after and merge_before message', async () => {
      factory({ mrData: { mergeAfter: MERGE_AFTER, mergeBefore: MERGE_BEFORE } });
      await waitForPromises();

      expect(wrapper.text()).toBe(
        'Merge must be between Oct 17, 2024, 6:23 PM and Oct 18, 2024, 9:00 AM',
      );
    });

    it('renders nothing when neither date is set', async () => {
      factory({ mrData: {} });
      await waitForPromises();

      expect(wrapper.text()).toBe('');
    });
  });

  describe('status icon', () => {
    it.each`
      status        | icon
      ${'success'}  | ${'success'}
      ${'failed'}   | ${'failed'}
      ${'inactive'} | ${'neutral'}
    `('renders $icon icon for $status result', async ({ status, icon }) => {
      factory({
        check: { status, identifier: 'merge_time' },
        mrData: { mergeAfter: MERGE_AFTER },
      });
      await waitForPromises();

      expect(wrapper.findComponent(StatusIcon).props('iconName')).toBe(icon);
    });
  });
});
