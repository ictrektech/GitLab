import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { screen, waitFor } from '@testing-library/vue';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import ImplementationWidget from 'ee/work_items/components/implementation_widget/implementation_widget.vue';
import {
  fullMount,
  waitAndClick,
  waitAndSetValue,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import { setFeatureFlags, setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { workItemAgentPlan } from 'ee_jest/integration/work_items/fixture_variants';
import {
  lastRequestVariables,
  snapshotRequests,
  expectGraphQLCalls,
} from 'ee_jest/integration/core/operation_helpers';

Vue.use(VueApollo);

const WidgetHost = {
  components: { ImplementationWidget },
  data() {
    return {
      activePanel: null,
      workItem: {
        id: 'gid://gitlab/WorkItem/1',
        iid: '1',
        workItemType: { name: 'Issue' },
      },
    };
  },
  template: `<implementation-widget
    :work-item="workItem"
    :can-update="true"
    :is-panel-open="activePanel === 'workplan'"
    @request-panel="activePanel = $event"
  />`,
};

describe('Readiness score drawer', () => {
  const findTrigger = () => screen.queryByTestId('readiness-details-button');
  const findPanel = () => screen.queryByTestId('readiness-drawer')?.querySelector('aside') ?? null;

  const mountWidget = (workplanScore = true) => {
    setFeatureFlags({ workplanScore });
    fullMount(WidgetHost, {
      apolloProvider,
      provide: { fullPath: 'gitlab-org/gitlab' },
    });
  };

  beforeAll(() => createPortalElement());
  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  describe('with a scored plan', () => {
    beforeEach(async () => {
      setQueryVariant(workItemAgentPlan).withContentAndScore();
      mountWidget();
      await waitForElement(findTrigger);
    });

    it('keeps feedback out of the initial requests', () => {
      expect(lastRequestVariables('workItemAgentPlan')).toMatchObject({
        includeReadinessScore: true,
      });
      expect(snapshotRequests()).not.toHaveProperty('workItemAgentPlanReadinessFeedback');
      expect(findPanel()).toBe(null);
    });

    describe('after opening readiness details', () => {
      let beforeOpening;

      beforeEach(async () => {
        beforeOpening = snapshotRequests();
        findTrigger().click();
        await waitFor(() => {
          expect(findPanel()?.textContent).toContain('Add acceptance criteria.');
        });
      });

      it('renders safely formatted feedback from its own query', () => {
        expectGraphQLCalls(beforeOpening, {
          expect: ['workItemAgentPlanReadinessFeedback'],
          forbid: ['workItemAgentPlan'],
        });
        expect(findPanel().querySelector('ol li strong').textContent).toBe(
          'Add acceptance criteria.',
        );
        expect(findPanel().querySelector('h2').textContent.trim()).toBe('Readiness');
        expect(findPanel().querySelector('h3').textContent.trim()).toBe('How to improve readiness');
      });

      it('closes with Escape and restores trigger focus', async () => {
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', keyCode: 27 }));
        await waitFor(() => expect(findPanel()).toBe(null));
        expect(document.activeElement).toBe(findTrigger());
      });

      it('toggles closed using the same trigger', async () => {
        findTrigger().click();
        await waitFor(() => expect(findPanel()).toBe(null));
        expect(findTrigger().getAttribute('aria-expanded')).toBe('false');
      });

      it('closes only the drawer when Escape is pressed inside it above the workplan', async () => {
        screen.getByTestId('open-workplan-button').click();
        await waitForElement(() => screen.queryByTestId('workplan-panel'));
        findPanel()
          .querySelector('h2')
          .dispatchEvent(
            new KeyboardEvent('keydown', { key: 'Escape', keyCode: 27, bubbles: true }),
          );
        await waitFor(() => expect(findPanel()).toBe(null));
        expect(screen.queryByTestId('workplan-panel')).not.toBe(null);
      });

      describe('after switching to the workplan and saving', () => {
        let baseline;

        beforeEach(async () => {
          screen.getByTestId('open-workplan-button').click();
          await waitForElement(() => screen.queryByTestId('workplan-panel'));
          expect(findPanel()).not.toBe(null);
          findTrigger().click();
          await waitFor(() => expect(findPanel()).toBe(null));
          await waitAndClick(() => screen.queryByTestId('panel-edit-button'));
          await waitAndSetValue(
            () => screen.queryByTestId('workplan-editor')?.querySelector('textarea') ?? null,
            'Updated plan',
          );
          baseline = snapshotRequests();
          await waitAndClick(() => screen.queryByTestId('save-workplan-button'));
          await waitFor(() =>
            expect(screen.queryByTestId('workplan-rendered')?.textContent).toContain(
              'Updated plan',
            ),
          );
        });

        it('preserves feedback through the cache write without refetching', async () => {
          findTrigger().click();
          await waitFor(() =>
            expect(findPanel()?.textContent).toContain('Add acceptance criteria.'),
          );
          expect(screen.queryByTestId('workplan-panel')).not.toBe(null);
          expectGraphQLCalls(baseline, {
            expect: ['updateWorkItemAgentPlan'],
            forbid: ['workItemAgentPlan', 'workItemAgentPlanReadinessFeedback'],
          });
        });
      });
    });
  });

  describe('without feedback or a score', () => {
    beforeEach(async () => {
      setQueryVariant(workItemAgentPlan).withContent();
      mountWidget();
      await waitForElement(() => screen.queryByTestId('open-workplan-button'));
    });

    it('hides the readiness component and drawer', () => {
      expect(findTrigger()).toBe(null);
      expect(findPanel()).toBe(null);
    });
  });

  describe('with the flag disabled', () => {
    beforeEach(async () => {
      setQueryVariant(workItemAgentPlan).withContentAndScore();
      mountWidget(false);
      await waitForElement(() => screen.queryByTestId('open-workplan-button'));
    });

    it('does not expose the trigger or request feedback', () => {
      expect(findTrigger()).toBe(null);
      expect(lastRequestVariables('workItemAgentPlan')).toMatchObject({
        includeReadinessScore: false,
      });
      expect(snapshotRequests()).not.toHaveProperty('workItemAgentPlanReadinessFeedback');
    });
  });
});
