import { GlIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import MergeReadiness from 'ee/merge_requests/ai_overview/components/merge_readiness.vue';
import {
  check,
  checksWith,
  failingChecks,
  makeMergeRequest,
  makeReviewer,
  passingChecks,
  pipeline,
  reviewers,
} from '../mock_data';

describe('AI Overview merge readiness', () => {
  let wrapper;

  const createComponent = (overrides = {}) => {
    wrapper = mountExtended(MergeReadiness, {
      propsData: { mergeRequest: makeMergeRequest(overrides) },
    });
  };

  const findRows = () => wrapper.findAllByTestId('readiness-row');
  const rowText = (index) => findRows().at(index).text();
  const findRowLabel = (index) => findRows().at(index).find('[data-testid="readiness-row-label"]');
  const rowDetail = (index) => findRowLabel(index).attributes('title');
  const rowIcon = (index) => findRows().at(index).findComponent(GlIcon);
  const rowIconVariant = (index) => rowIcon(index).props('variant');

  describe('rows', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders one row per merge check', () => {
      expect(findRows()).toHaveLength(4);
    });

    it('builds the rows from the merge request data', () => {
      expect(rowDetail(0)).toBe('1 of 2 required');
      expect(rowDetail(1)).toBe('3 unresolved threads');
      expect(rowDetail(2)).toBe('Running');
      expect(rowDetail(3)).toBe('None');
    });

    it('keeps the detail in a tooltip on the label, and in text for screen readers', () => {
      expect(findRowLabel(1).text()).toBe('Discussions');
      expect(rowDetail(1)).toBe('3 unresolved threads');
      expect(findRows().at(1).find('[data-testid="readiness-row-detail"]').text()).toBe(
        '3 unresolved threads',
      );
      expect(findRows().at(1).find('[data-testid="readiness-row-detail"]').classes()).toContain(
        'gl-sr-only',
      );
      expect(findRowLabel(1).attributes('tabindex')).toBe('0');
      expect(findRowLabel(1).classes()).toEqual(
        expect.arrayContaining(['gl-underline', 'gl-decoration-dotted']),
      );
    });

    it('offers no buttons on the rows', () => {
      expect(findRows().at(1).find('a, button').exists()).toBe(false);
      expect(findRows().at(2).find('a, button').exists()).toBe(false);
    });

    it('takes each row state from its mergeability check', () => {
      expect(rowIconVariant(0)).toBe('danger');
      expect(rowIconVariant(2)).toBe('info');
      expect(rowIconVariant(3)).toBe('success');
    });

    it('names each row state for screen readers', () => {
      expect(rowIcon(0).props('ariaLabel')).toBe('Blocked');
      expect(rowIcon(2).props('ariaLabel')).toBe('In progress');
      expect(rowIcon(3).props('ariaLabel')).toBe('Passing');
    });

    it('counts only the passing checks', () => {
      expect(wrapper.text()).toContain('1 of 4 checks passing');
      expect(wrapper.text()).toContain('This merge request is not ready to merge');
    });
  });

  it('reports the merge request as ready when every check passes', () => {
    createComponent({
      approvalsLeft: 0,
      resolvedDiscussionsCount: 4,
      mergeabilityChecks: passingChecks,
    });

    expect(wrapper.text()).toContain('4 of 4 checks passing');
    expect(wrapper.text()).toContain('Ready to merge');
  });

  it('treats approvals as not required when the check is turned off', () => {
    createComponent({
      approvalsRequired: 0,
      mergeabilityChecks: [check('NOT_APPROVED', 'INACTIVE'), ...failingChecks.slice(1)],
    });

    expect(rowDetail(0)).toBe('Not required');
    expect(rowIconVariant(0)).toBe('subtle');
  });

  describe('a check the project has turned off', () => {
    beforeEach(() => {
      createComponent({
        mergeabilityChecks: checksWith(check('CI_MUST_PASS', 'INACTIVE')),
        headPipeline: pipeline('Failed'),
      });
    });

    it('does not block the merge', () => {
      expect(wrapper.text()).toContain('Ready to merge');
      expect(wrapper.text()).toContain('4 of 4 checks passing');
    });

    it('does not claim the row is passing while its detail says otherwise', () => {
      expect(rowDetail(2)).toBe('Failed');
      expect(rowIconVariant(2)).toBe('subtle');
      expect(rowIcon(2).props('ariaLabel')).toBe('Not required');
    });
  });

  it('leaves a turned-off check without a default row out of the panel', () => {
    createComponent({
      mergeabilityChecks: [...passingChecks, check('STATUS_CHECKS_MUST_PASS', 'INACTIVE')],
    });

    expect(findRows()).toHaveLength(4);
    expect(wrapper.text()).not.toContain('Status checks');
  });

  describe('a check passing with an override', () => {
    beforeEach(() => {
      createComponent({
        mergeabilityChecks: checksWith(check('SECURITY_POLICY_VIOLATIONS', 'WARNING')),
      });
    });

    it('earns a row, so the override is not silently green', () => {
      expect(findRows()).toHaveLength(5);
      expect(rowText(4)).toContain('Security policies');
      expect(rowIconVariant(4)).toBe('warning');
      expect(rowIcon(4).props('ariaLabel')).toBe('Override added');
    });

    it('still lets the merge through, but says so with caution', () => {
      expect(wrapper.text()).toContain('Ready to merge, with caution');
      expect(wrapper.text()).toContain('5 of 5 checks passing');
    });
  });

  describe('a check that has not finished', () => {
    beforeEach(() => {
      createComponent({ mergeabilityChecks: checksWith(check('CONFLICT', 'CHECKING')) });
    });

    it('does not present the unfinished check as a verdict', () => {
      expect(wrapper.text()).toContain('Checking whether this merge request can be merged');
      expect(wrapper.text()).not.toContain('not ready to merge');
    });

    it('says the row is being checked rather than reporting the raw field', () => {
      expect(rowDetail(3)).toBe('Checking for merge conflicts.');
    });
  });

  it('treats a check it heard nothing about as unfinished, not as passing', () => {
    createComponent({ mergeabilityChecks: [] });

    expect(wrapper.text()).toContain('Checking whether this merge request can be merged');
    expect(wrapper.text()).toContain('0 of 4 checks passing');
    expect(wrapper.text()).not.toContain('Ready to merge');
  });

  it('treats a status it does not recognise as unfinished', () => {
    createComponent({ mergeabilityChecks: checksWith(check('CONFLICT', 'SOMETHING_NEW')) });

    expect(rowIconVariant(3)).toBe('info');
    expect(wrapper.text()).toContain('Checking whether this merge request can be merged');
  });

  describe.each`
    state       | title                  | summary
    ${'merged'} | ${'Merged'}            | ${'This merge request has been merged.'}
    ${'closed'} | ${'Closed'}            | ${'This merge request was closed without being merged.'}
    ${'locked'} | ${'Merge in progress'} | ${'This merge request is being merged.'}
  `('when the merge request is $state', ({ state, title, summary }) => {
    beforeEach(() => {
      // The merge gate reports `not_open` as a failing check, which read as "not ready to merge".
      createComponent({ state, mergeabilityChecks: [check('NOT_OPEN', 'FAILED')] });
    });

    it('replaces the readiness panel rather than scoring it', () => {
      expect(wrapper.text()).toContain(title);
      expect(wrapper.text()).toContain(summary);
      expect(findRows()).toHaveLength(0);
    });
  });

  describe('a blocking check without a row of its own', () => {
    beforeEach(() => {
      createComponent({
        approvalsLeft: 0,
        resolvedDiscussionsCount: 4,
        mergeabilityChecks: [
          ...passingChecks.slice(0, 4),
          check('DRAFT_STATUS', 'FAILED'),
          check('NEED_REBASE', 'SUCCESS'),
        ],
      });
    });

    it('earns a row of its own, explained by the widget failure reason', () => {
      expect(findRows()).toHaveLength(5);
      expect(findRowLabel(4).text()).toBe('Draft');
      expect(rowDetail(4)).toBe('Merge request must not be draft.');
    });

    it('holds back the verdict', () => {
      expect(wrapper.text()).toContain('4 of 5 checks passing');
      expect(wrapper.text()).toContain('This merge request is not ready to merge');
    });
  });

  describe('hero', () => {
    beforeEach(() => {
      createComponent();
    });

    it('says the merge request is not ready', () => {
      expect(wrapper.text()).toContain('This merge request is not ready to merge');
    });
  });

  describe('when the current user is a reviewer who has not approved', () => {
    const viewer = () =>
      reviewers(
        makeReviewer({
          id: 'gid://gitlab/User/3',
          username: 'marco',
          mergeRequestInteraction: { approved: false, reviewState: 'REVIEWED' },
        }),
      );

    beforeEach(() => {
      window.gon = { current_username: 'marco' };
    });

    it('names their review as the blocker', () => {
      createComponent({ reviewers: viewer() });

      expect(wrapper.text()).toContain('Your review is the blocker');
    });

    it('keeps the neutral title while approvals are not what blocks the merge', () => {
      createComponent({
        reviewers: viewer(),
        mergeabilityChecks: checksWith(check('CI_MUST_PASS', 'FAILED')),
      });

      expect(wrapper.text()).toContain('This merge request is not ready to merge');
      expect(wrapper.text()).not.toContain('Your review is the blocker');
    });

    it('says nothing about their review once the merge request is merged', () => {
      createComponent({
        reviewers: viewer(),
        state: 'merged',
        mergeabilityChecks: [check('NOT_OPEN', 'FAILED')],
      });

      expect(wrapper.text()).toContain('Merged');
      expect(wrapper.text()).not.toContain('Your review is the blocker');
    });
  });

  it('does not single out a reviewer who has already approved', () => {
    window.gon = { current_username: 'elena' };
    createComponent();

    expect(wrapper.text()).toContain('This merge request is not ready to merge');
    expect(wrapper.text()).not.toContain('Your review is the blocker');
  });
});
