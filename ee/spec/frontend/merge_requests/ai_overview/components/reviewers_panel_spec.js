import { GlAvatar, GlIcon, GlLink } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ReviewersPanel from 'ee/merge_requests/ai_overview/components/reviewers_panel.vue';
import SuggestedReviewers from 'ee/merge_requests/components/reviewers/suggested_reviewers.vue';
import { interaction, makeMergeRequest, makeReviewer, reviewers } from '../mock_data';

// The sidebar's component has its own spec; this one only checks what the panel hands it.
const SuggestedReviewersStub = {
  name: SuggestedReviewers.name,
  inject: ['issuableId', 'issuableIid'],
  props: { canUpdate: { type: Boolean, required: true } },
  render(h) {
    return h('div');
  },
};

describe('AI Overview reviewers panel', () => {
  let wrapper;

  const createComponent = (overrides = {}, { aiSuggestedReviewersAvailable = true } = {}) => {
    wrapper = mountExtended(ReviewersPanel, {
      provide: { iid: '1', aiSuggestedReviewersAvailable },
      propsData: { mergeRequest: makeMergeRequest(overrides) },
      stubs: { SuggestedReviewers: SuggestedReviewersStub },
    });
  };

  const findRows = () => wrapper.findAllByTestId('reviewer-row');
  const rowIcon = (index) => findRows().at(index).findComponent(GlIcon);
  const findSuggestedReviewers = () => wrapper.findComponent(SuggestedReviewersStub);

  const reviewerWith = (id, reviewState) =>
    makeReviewer({
      id: `gid://gitlab/User/${id}`,
      username: `user${id}`,
      name: `User ${id}`,
      mergeRequestInteraction: interaction({ approved: false, reviewState }),
    });

  describe('with reviewers', () => {
    beforeEach(() => {
      createComponent({
        reviewers: reviewers(
          makeReviewer(),
          reviewerWith(3, 'REQUESTED_CHANGES'),
          reviewerWith(4, 'REVIEWED'),
          reviewerWith(5, 'REVIEW_STARTED'),
          reviewerWith(6, 'UNREVIEWED'),
        ),
      });
    });

    it('renders one row per reviewer with their avatar and name', () => {
      expect(findRows()).toHaveLength(5);
      expect(findRows().at(0).findComponent(GlAvatar).props('src')).toBe('/avatar.png');
      expect(findRows().at(0).text()).toContain('Elena Kowalski');
    });

    it('links each reviewer to their profile with the user popover data', () => {
      const link = findRows().at(0).findComponent(GlLink);

      expect(link.attributes('href')).toBe('/elena');
      expect(link.classes()).toContain('js-user-link');
      expect(link.attributes('data-user-id')).toBe('2');
      expect(link.attributes('data-username')).toBe('elena');
    });

    it.each`
      index | label                  | variant
      ${0}  | ${'Approved'}          | ${'success'}
      ${1}  | ${'Requested changes'} | ${'danger'}
      ${2}  | ${'Commented'}         | ${'info'}
      ${3}  | ${'Review started'}    | ${'subtle'}
      ${4}  | ${'Awaiting review'}   | ${'subtle'}
    `('shows what reviewer $index has done so far', ({ index, label, variant }) => {
      expect(findRows().at(index).text()).toContain(label);
      expect(rowIcon(index).props('variant')).toBe(variant);
    });

    it('counts the approvals in the header', () => {
      expect(wrapper.text()).toContain('1 of 5 approved');
    });
  });

  describe('without reviewers', () => {
    beforeEach(() => {
      createComponent({ reviewers: reviewers() });
    });

    it('renders an empty state instead of rows', () => {
      expect(findRows()).toHaveLength(0);
      expect(wrapper.text()).toContain('No reviewers yet');
      expect(wrapper.text()).not.toContain('approved');
    });
  });

  it.each`
    description                       | mergeRequestInteraction
    ${'without interaction data'}     | ${null}
    ${'who took their approval back'} | ${interaction({ approved: false, reviewState: 'UNAPPROVED' })}
  `('treats a reviewer $description as awaiting review', ({ mergeRequestInteraction }) => {
    createComponent({ reviewers: reviewers(makeReviewer({ mergeRequestInteraction })) });

    expect(findRows().at(0).text()).toContain('Awaiting review');
  });

  // The state can lag behind the approval itself, so the flag decides.
  it('shows an approval whatever the review state says', () => {
    createComponent({
      reviewers: reviewers(
        makeReviewer({ mergeRequestInteraction: interaction({ reviewState: 'REVIEWED' }) }),
      ),
    });

    expect(findRows().at(0).text()).toContain('Approved');
  });

  describe('recommended reviewers', () => {
    it('shows the sidebar recommendations for this merge request', () => {
      createComponent();

      expect(findSuggestedReviewers().props('canUpdate')).toBe(true);
      expect(findSuggestedReviewers().vm.issuableId).toBe(3);
      expect(findSuggestedReviewers().vm.issuableIid).toBe('1');
    });

    it('lets them add reviewers only for someone who can update the merge request', () => {
      createComponent({
        userPermissions: { __typename: 'MergeRequestPermissions', updateMergeRequest: false },
      });

      expect(findSuggestedReviewers().props('canUpdate')).toBe(false);
    });

    it('leaves them out when the flow is off for the project', () => {
      createComponent({}, { aiSuggestedReviewersAvailable: false });

      expect(findSuggestedReviewers().exists()).toBe(false);
    });
  });
});
