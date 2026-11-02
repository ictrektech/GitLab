import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import duoChatAvailableQuery from 'ee/ai/graphql/duo_chat_available.query.graphql';
import MrWidget from '~/vue_merge_request_widget/components/widget/widget.vue';
import RiskAssessmentWidget from 'ee/vue_merge_request_widget/widgets/risk_assessment/index.vue';
import SeverityMeter from 'ee/vue_shared/components/severity_meter/severity_meter.vue';
import RiskConfidenceNotice from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_confidence_notice.vue';
import RiskFooter from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_footer.vue';
import RiskRationale from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_rationale.vue';
import RiskSignalBreakdown from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_signal_breakdown.vue';
import RiskStaleWarning from 'ee/vue_merge_request_widget/widgets/risk_assessment/components/risk_stale_warning.vue';

Vue.use(VueApollo);

describe('WidgetRiskAssessment', () => {
  let wrapper;
  let duoChatAvailableHandler;

  const duoChatAvailableResponse = (available) => ({
    data: { currentUser: { id: 'gid://gitlab/User/1', duoChatAvailable: available } },
  });

  const completedAssessment = {
    status: 'COMPLETE',
    riskTier: 'HIGH',
    confidenceTier: 'HIGH',
    rationale: null,
    stale: false,
    duoWorkflowId: null,
    contributingSignals: [
      {
        signal: 'touches_auth',
        label: 'Authentication or authorization logic',
        detail: 'touches_auth: true (lib/auth.rb:44)',
      },
      { signal: 'gate.auth', label: 'Auth', detail: 'Authentication domain (lib/auth.rb)' },
      { signal: 'diff_shape.churn', label: 'Size of change', detail: null },
    ],
    missingSignals: [],
  };

  const createComponent = async ({
    riskAssessment = completedAssessment,
    isLoading = false,
    hasError = false,
    canRefresh = false,
    isSubmitting = false,
  } = {}) => {
    wrapper = shallowMountExtended(RiskAssessmentWidget, {
      apolloProvider: createMockApollo([[duoChatAvailableQuery, duoChatAvailableHandler]]),
      propsData: { riskAssessment, isLoading, hasError, canRefresh, isSubmitting },
      stubs: { MrWidget, GlSprintf, RiskFooter },
    });

    await waitForPromises();
  };

  const findWidget = () => wrapper.findComponent(MrWidget);
  const findMeter = () => wrapper.findComponent(SeverityMeter);
  // The framework renders the content slot only once expanded.
  const expandWidget = async () => {
    await wrapper.findComponentByTestId('toggle-button').vm.$emit('click');
    await waitForPromises();
  };
  const findSummary = () => wrapper.findByTestId('risk-summary');
  const summaryText = () => findSummary().text().replace(/\s+/g, ' ');
  const findBreakdown = () => wrapper.findComponent(RiskSignalBreakdown);
  const findConfidenceNotice = () => wrapper.findComponent(RiskConfidenceNotice);
  const findStaleWarning = () => wrapper.findComponent(RiskStaleWarning);
  const findRationale = () => wrapper.findComponent(RiskRationale);
  const findDuoSessionLink = () => wrapper.findComponentByTestId('risk-duo-session-link');
  const findUpdatingNote = () => wrapper.findByTestId('risk-updating');
  const findFooter = () => wrapper.findComponent(RiskFooter);

  beforeEach(() => {
    duoChatAvailableHandler = jest.fn().mockResolvedValue(duoChatAvailableResponse(true));
  });

  describe('the severity meter', () => {
    it('renders in the status-icon slot, driven by the risk tier', async () => {
      await createComponent();

      expect(findMeter().props('severity')).toBe('HIGH');
    });

    it('pulses while the assessment is loading', async () => {
      await createComponent({ riskAssessment: null, isLoading: true });

      expect(findMeter().props('loading')).toBe(true);
    });

    it('passes risk-domain wording as the accessible label', async () => {
      await createComponent();

      expect(findMeter().props('label')).toBe('Risk level: High risk');
    });
  });

  describe('when the assessment completed', () => {
    beforeEach(() => createComponent());

    it('renders the widget', () => {
      expect(wrapper.findByTestId('mr-risk-assessment-widget').exists()).toBe(true);
    });

    it('states the risk after a bold "Risk assessment:" prefix', () => {
      expect(summaryText()).toBe('Risk assessment: High with high confidence');
    });

    it('is collapsible', () => {
      expect(findWidget().props('isCollapsible')).toBe(true);
    });

    it('does not show a staleness warning', () => {
      expect(findStaleWarning().exists()).toBe(false);
    });

    it('does not show a duo session link, because no session produced this assessment', () => {
      expect(findDuoSessionLink().exists()).toBe(false);
    });

    describe('once expanded', () => {
      beforeEach(() => expandWidget());

      it('hands every contribution to the signal breakdown', () => {
        expect(findBreakdown().props('contributions')).toEqual(
          completedAssessment.contributingSignals,
        );
      });

      it('does not show a confidence notice', () => {
        expect(findConfidenceNotice().exists()).toBe(false);
      });

      it('does not show a rationale section, because there is none', () => {
        expect(findRationale().exists()).toBe(false);
      });
    });
  });

  describe('the headline wording', () => {
    // The tier and confidence words are concatenated into a fixed sentence:
    // "{Tier} with {confidence} confidence", for every combination.
    it.each`
      riskTier      | confidenceTier | headline
      ${'LOW'}      | ${'HIGH'}      | ${'Risk assessment: Low with high confidence'}
      ${'LOW'}      | ${'MEDIUM'}    | ${'Risk assessment: Low with medium confidence'}
      ${'LOW'}      | ${'LOW'}       | ${'Risk assessment: Low with low confidence'}
      ${'LOW'}      | ${'VERY_HIGH'} | ${'Risk assessment: Low with very high confidence'}
      ${'MEDIUM'}   | ${'HIGH'}      | ${'Risk assessment: Medium with high confidence'}
      ${'MEDIUM'}   | ${'MEDIUM'}    | ${'Risk assessment: Medium with medium confidence'}
      ${'MEDIUM'}   | ${'LOW'}       | ${'Risk assessment: Medium with low confidence'}
      ${'MEDIUM'}   | ${'VERY_HIGH'} | ${'Risk assessment: Medium with very high confidence'}
      ${'HIGH'}     | ${'HIGH'}      | ${'Risk assessment: High with high confidence'}
      ${'HIGH'}     | ${'MEDIUM'}    | ${'Risk assessment: High with medium confidence'}
      ${'HIGH'}     | ${'LOW'}       | ${'Risk assessment: High with low confidence'}
      ${'HIGH'}     | ${'VERY_HIGH'} | ${'Risk assessment: High with very high confidence'}
      ${'CRITICAL'} | ${'HIGH'}      | ${'Risk assessment: Critical with high confidence'}
      ${'CRITICAL'} | ${'MEDIUM'}    | ${'Risk assessment: Critical with medium confidence'}
      ${'CRITICAL'} | ${'LOW'}       | ${'Risk assessment: Critical with low confidence'}
      ${'CRITICAL'} | ${'VERY_HIGH'} | ${'Risk assessment: Critical with very high confidence'}
    `(
      'reads "$headline" for $riskTier risk at $confidenceTier confidence',
      async ({ riskTier, confidenceTier, headline }) => {
        await createComponent({
          riskAssessment: { ...completedAssessment, riskTier, confidenceTier },
        });

        expect(summaryText()).toBe(headline);
      },
    );

    // The backend scores tier and confidence independently, so a completed record
    // can carry a tier with no confidence. The headline must still keep the bold
    // "Risk assessment:" prefix rather than dropping to a bare tier word.
    it('keeps the "Risk assessment:" prefix when confidence is missing', async () => {
      await createComponent({
        riskAssessment: { ...completedAssessment, riskTier: 'HIGH', confidenceTier: null },
      });

      expect(summaryText()).toBe('Risk assessment: High');
    });

    // Defensive last resort: a completed record whose tier isn't one of the known
    // enum values surfaces the raw tier rather than an empty or misleading headline.
    it('surfaces the raw tier when it is unrecognized', async () => {
      await createComponent({
        riskAssessment: { ...completedAssessment, riskTier: 'SOME_NEW_TIER', confidenceTier: null },
      });

      expect(summaryText()).toBe('SOME_NEW_TIER');
    });
  });

  describe('when the assessment has a rationale', () => {
    const rationale =
      'Touches authentication logic without adding new test coverage, which drives the score.';

    beforeEach(async () => {
      await createComponent({ riskAssessment: { ...completedAssessment, rationale } });
      await expandWidget();
    });

    it('shows the rationale', () => {
      expect(findRationale().props('rationale')).toBe(rationale);
    });
  });

  describe('when a Duo workflow session produced the assessment', () => {
    const sessionAssessment = {
      ...completedAssessment,
      rationale: 'Touches authentication logic.',
      duoWorkflowId: 7,
    };

    it('does not show the link in the header', async () => {
      await createComponent({ riskAssessment: sessionAssessment });

      expect(findDuoSessionLink().exists()).toBe(false);
    });

    it('shows a small link to view the session in the footer once expanded', async () => {
      await createComponent({ riskAssessment: sessionAssessment });
      await expandWidget();

      expect(findDuoSessionLink().props('sessionId')).toBe(7);
      expect(findDuoSessionLink().props('size')).toBe('small');
    });

    it.each(['QUEUED', 'SCORING'])('hides the link while the assessment is %s', async (status) => {
      await createComponent({ riskAssessment: sessionAssessment });
      await expandWidget();
      expect(findDuoSessionLink().exists()).toBe(true);

      await wrapper.setProps({ riskAssessment: { ...sessionAssessment, status } });

      expect(findDuoSessionLink().exists()).toBe(false);
    });

    it('keeps the link in the footer when the assessment is stale', async () => {
      await createComponent({ riskAssessment: { ...sessionAssessment, stale: true } });
      await expandWidget();

      expect(findDuoSessionLink().props('sessionId')).toBe(7);
    });

    it('shows the link when there is no rationale', async () => {
      await createComponent({ riskAssessment: { ...sessionAssessment, rationale: null } });
      await expandWidget();

      expect(findDuoSessionLink().props('sessionId')).toBe(7);
    });

    it('does not check Duo Chat availability without a session', async () => {
      await createComponent();

      expect(duoChatAvailableHandler).not.toHaveBeenCalled();
    });

    describe.each([
      [
        'Duo Chat is not available',
        () => jest.fn().mockResolvedValue(duoChatAvailableResponse(false)),
      ],
      ['the availability check fails', () => jest.fn().mockRejectedValue(new Error('error'))],
    ])('when %s', (_, handler) => {
      beforeEach(() => {
        duoChatAvailableHandler = handler();
      });

      it('does not render the footer when the assessment is not stale', async () => {
        await createComponent({ riskAssessment: sessionAssessment });
        await expandWidget();

        expect(findFooter().exists()).toBe(false);
      });

      it('renders the footer without the link when the assessment is stale', async () => {
        await createComponent({ riskAssessment: { ...sessionAssessment, stale: true } });
        await expandWidget();

        expect(findStaleWarning().exists()).toBe(true);
        expect(findDuoSessionLink().exists()).toBe(false);
      });
    });

    it('does not show the link when a failed assessment is stale', async () => {
      await createComponent({
        riskAssessment: { ...sessionAssessment, status: 'FAILED', stale: true },
      });
      await expandWidget();

      expect(findStaleWarning().exists()).toBe(true);
      expect(findDuoSessionLink().exists()).toBe(false);
    });
  });

  describe('when confidence is low', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: {
          ...completedAssessment,
          confidenceTier: 'LOW',
          missingSignals: [
            { signal: 'coverage', label: 'test coverage' },
            { signal: 'ai_authorship', label: 'commit authorship' },
          ],
        },
      }),
    );

    it('names what could not be measured once expanded', async () => {
      await expandWidget();

      expect(findConfidenceNotice().props('missingLabels')).toEqual([
        'test coverage',
        'commit authorship',
      ]);
    });

    it('renders the confidence notice after the risk breakdown, not inside it', async () => {
      await expandWidget();

      const breakdown = findBreakdown().element;
      const notice = findConfidenceNotice().element;

      // The notice is a confidence statement, so it must sit below the risk
      // breakdown as a sibling rather than under the "what affected the score"
      // heading.
      expect(breakdown.contains(notice)).toBe(false);
      expect(breakdown.parentElement).toBe(notice.parentElement);

      const order = Array.from(breakdown.parentElement.children);
      expect(order.indexOf(breakdown)).toBeLessThan(order.indexOf(notice));
    });
  });

  describe('when confidence is low but nothing contributed to the score', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: {
          ...completedAssessment,
          confidenceTier: 'LOW',
          contributingSignals: [],
          missingSignals: [{ signal: 'coverage', label: 'test coverage' }],
        },
      }),
    );

    // Confidence is independent of what contributed, so the notice must stand on
    // its own even when there is no risk breakdown to sit beneath.
    it('still shows the confidence notice once expanded', async () => {
      await expandWidget();

      expect(findBreakdown().exists()).toBe(false);
      expect(findConfidenceNotice().exists()).toBe(true);
      expect(findConfidenceNotice().props('missingLabels')).toEqual(['test coverage']);
    });
  });

  describe('when a missing signal has no label', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: {
          ...completedAssessment,
          confidenceTier: 'LOW',
          missingSignals: [
            { signal: 'coverage', label: 'test coverage' },
            { signal: 'touches_auth', label: null },
          ],
        },
      }),
    );

    it('leaves the unnameable signal out of the list', async () => {
      await expandWidget();

      expect(findConfidenceNotice().props('missingLabels')).toEqual(['test coverage']);
    });
  });

  describe('when no missing signal can be named', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: {
          ...completedAssessment,
          confidenceTier: 'LOW',
          missingSignals: [{ signal: 'touches_auth', label: null }],
        },
      }),
    );

    it('passes no labels, so the notice can drop itself', async () => {
      await expandWidget();

      expect(findConfidenceNotice().props('missingLabels')).toEqual([]);
    });
  });

  describe('when the merge request changed after assessment', () => {
    beforeEach(async () => {
      await createComponent({ riskAssessment: { ...completedAssessment, stale: true } });
      await expandWidget();
    });

    it('warns that the assessment reflects an earlier diff', () => {
      expect(findStaleWarning().exists()).toBe(true);
    });
  });

  describe('when the assessment is still running', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: { ...completedAssessment, status: 'PENDING', riskTier: null },
      }),
    );

    it('says the assessment is pending', () => {
      expect(summaryText()).toBe('Risk assessment: Pending');
    });

    it('is not collapsible, since there is nothing to expand yet', () => {
      expect(findWidget().props('isCollapsible')).toBe(false);
    });

    it('shows an empty meter, since there is nothing to report yet', () => {
      expect(findMeter().props('severity')).toBe(null);
      expect(findMeter().props('loading')).toBe(false);
    });
  });

  describe.each(['QUEUED', 'SCORING'])('when a first assessment is %s', (status) => {
    beforeEach(() =>
      createComponent({
        riskAssessment: { ...completedAssessment, status, riskTier: null },
      }),
    );

    it('says the assessment is queued', () => {
      expect(summaryText()).toBe('Risk assessment: Queued');
    });

    it('shows an empty meter and cannot be expanded', () => {
      expect(findMeter().props('severity')).toBe(null);
      expect(findWidget().props('isCollapsible')).toBe(false);
    });
  });

  describe.each(['QUEUED', 'SCORING'])(
    'when a re-assessment is %s over a previous result',
    (status) => {
      beforeEach(() => createComponent({ riskAssessment: { ...completedAssessment, status } }));

      it('keeps stating the previous risk headline', () => {
        expect(summaryText()).toBe('Risk assessment: High with high confidence');
      });

      it('shows an updating note alongside the headline', () => {
        expect(findUpdatingNote().exists()).toBe(true);
      });

      it('keeps the meter at the previous level', () => {
        expect(findMeter().props('severity')).toBe('HIGH');
      });

      it('cannot be expanded, since the previous details no longer apply', () => {
        expect(findWidget().props('isCollapsible')).toBe(false);
      });

      describe('when new commits were pushed', () => {
        beforeEach(() =>
          createComponent({
            riskAssessment: { ...completedAssessment, status, stale: true },
          }),
        );

        it('hides the stale warning too, so it cannot be expanded', () => {
          expect(findWidget().props('isCollapsible')).toBe(false);
          expect(findStaleWarning().exists()).toBe(false);
        });
      });
    },
  );

  describe('when the record is complete but carries no score', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: { ...completedAssessment, riskTier: null, confidenceTier: null },
      }),
    );

    it('cannot be expanded, since there is no result to show', () => {
      expect(findWidget().props('isCollapsible')).toBe(false);
    });

    it('shows an empty meter', () => {
      expect(findMeter().props('severity')).toBe(null);
    });
  });

  describe('when the assessment failed', () => {
    beforeEach(() =>
      createComponent({
        riskAssessment: { ...completedAssessment, status: 'FAILED', riskTier: null },
      }),
    );

    it('says the assessment is unavailable', () => {
      expect(summaryText()).toBe('Risk assessment: Unavailable');
    });

    it('shows an empty meter and cannot be expanded, since there is no score', () => {
      expect(findMeter().props('severity')).toBe(null);
      expect(findWidget().props('isCollapsible')).toBe(false);
    });
  });

  describe('when a failed run left a previous score behind', () => {
    beforeEach(() =>
      createComponent({ riskAssessment: { ...completedAssessment, status: 'FAILED' } }),
    );

    it('still reports the failure rather than the stale score', () => {
      expect(summaryText()).toBe('Risk assessment: Unavailable');
    });

    it('does not show the previous score on the meter', () => {
      expect(findMeter().props('severity')).toBe(null);
    });

    it('cannot be expanded when the changes have not moved on', () => {
      expect(findWidget().props('isCollapsible')).toBe(false);
    });
  });

  describe('when the assessment is still being fetched', () => {
    beforeEach(() => createComponent({ riskAssessment: null, isLoading: true }));

    it('says the assessment is evaluating', () => {
      expect(summaryText()).toBe('Risk assessment: Evaluating…');
    });

    it('pulses the meter', () => {
      expect(findMeter().props('loading')).toBe(true);
      expect(findMeter().props('severity')).toBe(null);
    });
  });

  describe('when the fetch failed', () => {
    beforeEach(() => createComponent({ riskAssessment: null, hasError: true }));

    it('puts the widget into its error state', () => {
      expect(findWidget().props('hasError')).toBe(true);
    });

    // mr-widget surfaces the failure through its own error text; the meter owns the
    // status-icon slot in every state, so on error it just sits empty rather than
    // reintroducing a separate red failure icon.
    it('leaves the meter empty and still, not pulsing', () => {
      expect(findMeter().props('severity')).toBe(null);
      expect(findMeter().props('loading')).toBe(false);
    });
  });

  describe('refresh', () => {
    const staleAssessment = { ...completedAssessment, stale: true };

    // The button itself belongs to RiskStaleWarning, which this shallow mount
    // stubs, so what matters here is what the widget hands it.
    const openPanel = async (options) => {
      await createComponent(options);
      await expandWidget();
    };

    it('lets the warning offer a refresh when the assessment no longer matches', async () => {
      await openPanel({ riskAssessment: staleAssessment, canRefresh: true });

      expect(findStaleWarning().props()).toMatchObject({
        canRefresh: true,
        isSubmitting: false,
      });
    });

    it('passes the in-flight state down', async () => {
      await openPanel({
        riskAssessment: staleAssessment,
        canRefresh: true,
        isSubmitting: true,
      });

      expect(findStaleWarning().props('isSubmitting')).toBe(true);
    });

    it('re-emits refresh, so the app can start the flow', async () => {
      await openPanel({ riskAssessment: staleAssessment, canRefresh: true });

      findStaleWarning().vm.$emit('refresh');

      expect(wrapper.emitted('refresh')).toHaveLength(1);
    });

    it('offers no refresh when the user cannot run the flow', async () => {
      await openPanel({ riskAssessment: staleAssessment, canRefresh: false });

      expect(findStaleWarning().props('canRefresh')).toBe(false);
    });

    it.each(['QUEUED', 'SCORING'])(
      'hides the stale warning while a %s run is already working on the changes',
      async (status) => {
        await createComponent({
          riskAssessment: { ...staleAssessment, status },
          canRefresh: true,
        });

        expect(findStaleWarning().exists()).toBe(false);
      },
    );

    describe('when a refresh failed', () => {
      beforeEach(() =>
        openPanel({
          riskAssessment: { ...staleAssessment, status: 'FAILED', rationale: 'Touches auth.' },
          canRefresh: true,
        }),
      );

      it('can still be expanded', () => {
        expect(findWidget().props('isCollapsible')).toBe(true);
      });

      it('shows the stale warning with the refresh button, so the reader can try again', () => {
        expect(findStaleWarning().props('canRefresh')).toBe(true);
      });

      it('hides the details of the previous assessment', () => {
        expect(findRationale().exists()).toBe(false);
        expect(findBreakdown().exists()).toBe(false);
      });
    });
  });
});
