import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlLabel } from '@gitlab/ui';
import { createMockSubscription } from 'mock-apollo-client';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import MetadataPanel from 'ee/merge_requests/ai_overview/components/metadata_panel.vue';
import metadataQuery from 'ee/merge_requests/ai_overview/queries/mr_ai_overview_metadata.query.graphql';
import labelsSubscription from 'ee/merge_requests/ai_overview/queries/mr_ai_overview_labels.subscription.graphql';
import milestoneSubscription from 'ee/merge_requests/ai_overview/queries/mr_ai_overview_milestone.subscription.graphql';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { labels, makeLabel, makeMetadata, metadataResponse, milestone } from '../mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('AI Overview metadata panel', () => {
  let wrapper;
  let queryHandler;
  let labelsSubscriptionHandler;
  let milestoneSubscriptionHandler;
  let labelsUpdates;
  let milestoneUpdates;

  const createComponent = ({ overrides = {}, handler } = {}) => {
    labelsUpdates = createMockSubscription();
    milestoneUpdates = createMockSubscription();
    labelsSubscriptionHandler = jest.fn(() => labelsUpdates);
    milestoneSubscriptionHandler = jest.fn(() => milestoneUpdates);
    queryHandler =
      handler ?? jest.fn().mockResolvedValue(metadataResponse(makeMetadata(overrides)));
    const apolloProvider = createMockApollo([[metadataQuery, queryHandler]]);
    apolloProvider.defaultClient.setRequestHandler(labelsSubscription, labelsSubscriptionHandler);
    apolloProvider.defaultClient.setRequestHandler(
      milestoneSubscription,
      milestoneSubscriptionHandler,
    );

    wrapper = mountExtended(MetadataPanel, {
      apolloProvider,
      provide: { projectPath: 'group/proj', iid: '1' },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findSection = () => wrapper.find('section');
  const findLabels = () => wrapper.findAllComponents(GlLabel);
  const findMilestoneLink = () => wrapper.findByTestId('milestone-link');
  const findInlineLabels = () => wrapper.findByTestId('labels-inline');
  const findLabelsCount = () => wrapper.findByTestId('labels-count');
  const findLabelsToggle = () => wrapper.findByTestId('labels-toggle');
  const findLabelsList = () => wrapper.findByTestId('labels-list');
  const manyLabels = (count) =>
    labels(
      ...Array.from({ length: count }, (_, index) =>
        makeLabel({ id: `gid://gitlab/ProjectLabel/${index + 1}`, title: `label ${index + 1}` }),
      ),
    );
  const milestoneTooltip = () => getBinding(findMilestoneLink().element, 'gl-tooltip').value;

  const createWithMilestone = async (overrides) => {
    createComponent({ overrides: { milestone: { ...milestone, ...overrides } } });
    await waitForPromises();
  };

  describe('with labels and a milestone', () => {
    beforeEach(async () => {
      createComponent({
        overrides: {
          labels: labels(
            makeLabel(),
            makeLabel({
              id: 'gid://gitlab/ProjectLabel/2',
              title: 'workflow::in review',
              color: '#8fbc8f',
              description: null,
            }),
          ),
        },
      });
      await waitForPromises();
    });

    it('fetches them for the merge request', () => {
      expect(queryHandler).toHaveBeenCalledWith({ projectPath: 'group/proj', iid: '1' });
    });

    it('renders a label for each one on the merge request', () => {
      expect(findLabels()).toHaveLength(2);
      expect(findLabels().at(0).props()).toMatchObject({
        title: 'backend',
        backgroundColor: '#428BCA',
        description: 'Server-side changes',
        scoped: false,
      });
    });

    it('renders scoped labels as scoped', () => {
      expect(findLabels().at(1).props('scoped')).toBe(true);
    });

    it('links the milestone', () => {
      expect(findMilestoneLink().text()).toBe('19.5');
      expect(findMilestoneLink().attributes('href')).toBe('/group/proj/-/milestones/4');
    });

    it('styles the milestone as the sidebar does, not as a blue link', () => {
      expect(findMilestoneLink().classes()).toEqual(
        expect.arrayContaining(['!gl-text-inherit', 'hover:!gl-text-link']),
      );
    });

    it('puts the milestone dates in a tooltip', () => {
      // Intl puts thin spaces around the range dash.
      expect(milestoneTooltip().replace(/\s/g, ' ')).toBe('Sep 12 – Oct 9, 2026');
    });
  });

  describe('label overflow', () => {
    it('shows up to three labels beside the heading', async () => {
      createComponent({ overrides: { labels: manyLabels(3) } });
      await waitForPromises();

      expect(findInlineLabels().findAllComponents(GlLabel)).toHaveLength(3);
      expect(findLabelsCount().exists()).toBe(false);
      expect(findLabelsToggle().exists()).toBe(false);
      expect(findLabelsList().exists()).toBe(false);
    });

    describe('with more than three labels', () => {
      beforeEach(async () => {
        createComponent({ overrides: { labels: manyLabels(5) } });
        await waitForPromises();
      });

      it('shows a count badge beside the heading in place of the labels', () => {
        expect(findInlineLabels().exists()).toBe(false);
        expect(findLabelsCount().text()).toBe('5');
        expect(findLabelsCount().element.previousElementSibling.textContent).toBe('Labels');
      });

      it('keeps the labels hidden underneath until asked', () => {
        expect(findLabelsList().element.style.display).toBe('none');
        expect(findLabelsToggle().text()).toBe('Show');
        expect(findLabelsToggle().attributes()).toMatchObject({
          'aria-expanded': 'false',
          'aria-controls': findLabelsList().attributes('id'),
        });
      });

      it('shows and hides every label underneath from the toggle', async () => {
        await findLabelsToggle().trigger('click');

        expect(findLabelsList().element.style.display).toBe('');
        expect(findLabelsList().findAllComponents(GlLabel)).toHaveLength(5);
        expect(findLabels().at(4).props('title')).toBe('label 5');
        expect(findLabelsToggle().text()).toBe('Hide');
        expect(findLabelsToggle().attributes('aria-expanded')).toBe('true');

        await findLabelsToggle().trigger('click');

        expect(findLabelsList().element.style.display).toBe('none');
        expect(findLabelsToggle().text()).toBe('Show');
      });
    });
  });

  describe('milestone dates', () => {
    it.each`
      startDate       | dueDate         | tooltip
      ${'2026-09-12'} | ${null}         | ${'Sep 12, 2026 – No due date'}
      ${null}         | ${'2026-10-09'} | ${'No start date – Oct 9, 2026'}
      ${null}         | ${null}         | ${null}
    `('show "$tooltip" from $startDate to $dueDate', async ({ startDate, dueDate, tooltip }) => {
      await createWithMilestone({ startDate, dueDate });

      expect(milestoneTooltip()).toBe(tooltip);
    });
  });

  it('marks an expired milestone, as the sidebar does', async () => {
    await createWithMilestone({ expired: true });

    expect(findMilestoneLink().text().replace(/\s+/g, ' ')).toBe('19.5 (expired)');
  });

  it('renders only the labels when there is no milestone', async () => {
    createComponent({ overrides: { milestone: null } });
    await waitForPromises();

    expect(findLabels()).toHaveLength(1);
    expect(findMilestoneLink().exists()).toBe(false);
  });

  it('renders only the milestone when there are no labels', async () => {
    createComponent({ overrides: { labels: labels() } });
    await waitForPromises();

    expect(wrapper.text()).not.toContain('Labels');
    expect(findMilestoneLink().exists()).toBe(true);
  });

  it('renders nothing when there are neither labels nor a milestone', async () => {
    createComponent({ overrides: { labels: labels(), milestone: null } });
    await waitForPromises();

    expect(findSection().exists()).toBe(false);
  });

  it('renders nothing while loading', () => {
    createComponent();

    expect(findSection().exists()).toBe(false);
  });

  it('renders nothing and reports the error when the query fails', async () => {
    createComponent({ handler: jest.fn().mockRejectedValue(new Error('nope')) });
    await waitForPromises();

    expect(findSection().exists()).toBe(false);
    expect(Sentry.captureException).toHaveBeenCalled();
  });

  it('does not subscribe before the merge request is known', () => {
    createComponent();

    expect(labelsSubscriptionHandler).not.toHaveBeenCalled();
    expect(milestoneSubscriptionHandler).not.toHaveBeenCalled();
  });

  it('follows the labels and milestone subscriptions for the loaded merge request', async () => {
    createComponent();
    await waitForPromises();

    expect(labelsSubscriptionHandler).toHaveBeenCalledWith({
      issuableId: 'gid://gitlab/MergeRequest/3',
    });
    expect(milestoneSubscriptionHandler).toHaveBeenCalledWith({
      issuableId: 'gid://gitlab/MergeRequest/3',
    });
  });

  it('applies a labels update without a refetch', async () => {
    createComponent();
    await waitForPromises();

    labelsUpdates.next({
      data: {
        issuableLabelsUpdated: {
          __typename: 'MergeRequest',
          id: 'gid://gitlab/MergeRequest/3',
          labels: labels(makeLabel({ id: 'gid://gitlab/ProjectLabel/2', title: 'frontend' })),
        },
      },
    });
    await waitForPromises();

    expect(findLabels().wrappers.map((label) => label.props('title'))).toEqual(['frontend']);
    expect(queryHandler).toHaveBeenCalledTimes(1);
  });

  it('applies a milestone removal without a refetch', async () => {
    createComponent();
    await waitForPromises();

    milestoneUpdates.next({
      data: {
        issuableMilestoneUpdated: {
          __typename: 'MergeRequest',
          id: 'gid://gitlab/MergeRequest/3',
          milestone: null,
        },
      },
    });
    await waitForPromises();

    expect(findMilestoneLink().exists()).toBe(false);
    expect(findLabels()).toHaveLength(1);
    expect(queryHandler).toHaveBeenCalledTimes(1);
  });
});
