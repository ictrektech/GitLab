import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import waitForPromises from 'helpers/wait_for_promises';
import ReviewDrawer from '~/batch_comments/components/review_drawer.vue';
import PreviewItem from '~/batch_comments/components/preview_item.vue';
import SummarizeMyReview from 'ee/batch_comments/components/summarize_my_review.vue';
import { globalAccessorPlugin } from '~/pinia/plugins';
import { useLegacyDiffs } from '~/diffs/stores/legacy_diffs';
import { useNotes } from '~/notes/store/legacy_notes';
import { useBatchComments } from '~/batch_comments/store';
import reviewDrawerQuery from '~/batch_comments/queries/review_drawer.query.graphql';

jest.mock('~/autosave');
jest.mock('~/vue_shared/components/markdown/eventhub');

Vue.use(PiniaVuePlugin);
Vue.use(VueApollo);

describe('ReviewDrawer', () => {
  let wrapper;
  let pinia;

  const createComponent = ({ canApprove = true, canSummarize = false, stubs = {} } = {}) => {
    const requestHandlers = [
      [
        reviewDrawerQuery,
        () =>
          Promise.resolve({
            data: {
              project: {
                id: 1,
                mergeRequest: {
                  id: 1,
                  allowsMultipleReviewers: true,
                  author: { id: 'gid://gitlab/User/99' },
                  userPermissions: {
                    canApprove,
                    updateMergeRequest: true,
                  },
                  reviewers: {
                    nodes: [],
                  },
                },
              },
            },
          }),
      ],
    ];
    const apolloProvider = createMockApollo(requestHandlers);

    wrapper = mountExtended(ReviewDrawer, {
      pinia,
      apolloProvider,
      provide: { canSummarize },
      stubs: { PreviewItem: stubComponent(PreviewItem), ...stubs },
    });
  };

  beforeEach(() => {
    pinia = createTestingPinia({
      plugins: [globalAccessorPlugin],
    });
    useLegacyDiffs().projectPath = 'gitlab-org/gitlab';
    useNotes().noteableData.id = 1;
    useNotes().noteableData.preview_note_path = '/preview';
    useNotes().noteableData.noteableType = 'merge_request';
    useNotes().notesData.markdownDocsPath = '/markdown/docs';
    useNotes().notesData.quickActionsDocsPath = '/quickactions/docs';
    useBatchComments();
  });

  it.each`
    requirePasswordToApprove | exists   | existsText
    ${true}                  | ${true}  | ${'shows'}
    ${false}                 | ${false} | ${'hides'}
  `(
    '$existsText approve password if require_password_to_approve is $requirePasswordToApprove',
    async ({ requirePasswordToApprove, exists }) => {
      useNotes().noteableData.require_password_to_approve = requirePasswordToApprove;
      useBatchComments().drawerOpened = true;

      createComponent({ requirePasswordToApprove });

      await waitForPromises();

      expect(wrapper.findByTestId('approve_password').exists()).toBe(exists);
    },
  );

  it.each`
    draftsCount | exists
    ${0}        | ${false}
    ${1}        | ${true}
  `(
    'exists is $exists for summarize button with $draftsCount drafts',
    async ({ draftsCount, exists }) => {
      useBatchComments().drafts = new Array(draftsCount).fill({});
      useBatchComments().drawerOpened = true;
      createComponent({ canSummarize: true });
      await wrapper.findComponentByTestId('placeholder-input-field').vm.$emit('focus');
      await waitForPromises();

      expect(wrapper.findByTestId('mutation-trigger').exists()).toBe(exists);
    },
  );

  it('syncs the summarize loading state with the summarize button', async () => {
    useBatchComments().drafts = [{}];
    useBatchComments().drawerOpened = true;
    createComponent({
      canSummarize: true,
      stubs: { SummarizeMyReview: stubComponent(SummarizeMyReview) },
    });
    await wrapper.findComponentByTestId('placeholder-input-field').vm.$emit('focus');
    await waitForPromises();
    const findSummarizeMyReview = () => wrapper.findComponent(SummarizeMyReview);

    expect(findSummarizeMyReview().props('summarizeReviewLoading')).toBe(false);

    await findSummarizeMyReview().vm.$emit('loading', true);

    expect(findSummarizeMyReview().props('summarizeReviewLoading')).toBe(true);
  });
});
