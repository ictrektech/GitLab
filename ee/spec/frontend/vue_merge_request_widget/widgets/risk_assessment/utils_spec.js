import { getRiskAssessmentState } from 'ee/vue_merge_request_widget/widgets/risk_assessment/utils';
import { riskHeadline } from 'ee/vue_merge_request_widget/widgets/risk_assessment/constants';

describe('getRiskAssessmentState', () => {
  const assessment = (overrides = {}) => ({
    status: 'COMPLETE',
    riskTier: 'HIGH',
    confidenceTier: 'HIGH',
    rationale: 'Touches the payment flow.',
    stale: false,
    duoWorkflowId: null,
    contributingSignals: [],
    missingSignals: [],
    ...overrides,
  });

  it('falls back to an empty assessment before one arrives', () => {
    expect(getRiskAssessmentState(null)).toMatchObject({
      status: null,
      tier: null,
      contributions: [],
      missingSignalLabels: [],
      isAssessed: false,
      hasDetails: false,
      showsFooter: false,
      meterSeverity: null,
      meterLabel: 'Risk level not available',
      summaryTitle: '%{boldStart}Risk assessment:%{boldEnd} Not available',
    });
  });

  it('describes a completed assessment', () => {
    expect(getRiskAssessmentState(assessment())).toMatchObject({
      isAssessed: true,
      isRefreshing: false,
      hasDetails: true,
      tierLabel: 'High risk',
      meterSeverity: 'HIGH',
      meterLabel: 'Risk level: High risk',
      summaryTitle: riskHeadline('HIGH', 'HIGH'),
    });
  });

  it.each`
    status        | isRefreshing | summaryTitle
    ${'QUEUED'}   | ${true}      | ${riskHeadline('HIGH', 'HIGH')}
    ${'SCORING'}  | ${true}      | ${riskHeadline('HIGH', 'HIGH')}
    ${'COMPLETE'} | ${false}     | ${riskHeadline('HIGH', 'HIGH')}
  `(
    'keeps the previous score while a $status assessment is refreshed',
    ({ status, isRefreshing, summaryTitle }) => {
      const state = getRiskAssessmentState(assessment({ status }));

      expect(state).toMatchObject({ isAssessed: true, isRefreshing, summaryTitle });
      // The details belong to the old score, so they wait for the new one.
      expect(state.hasDetails).toBe(!isRefreshing);
    },
  );

  it.each`
    description                 | riskAssessment                                       | options                | summaryTitle
    ${'still loading'}          | ${null}                                              | ${{ isLoading: true }} | ${'%{boldStart}Risk assessment:%{boldEnd} Evaluating…'}
    ${'failed'}                 | ${assessment({ status: 'FAILED' })}                  | ${{}}                  | ${'%{boldStart}Risk assessment:%{boldEnd} Unavailable'}
    ${'queued without a score'} | ${assessment({ status: 'QUEUED', riskTier: null })}  | ${{}}                  | ${'%{boldStart}Risk assessment:%{boldEnd} Queued'}
    ${'pending'}                | ${assessment({ status: 'PENDING', riskTier: null })} | ${{}}                  | ${'%{boldStart}Risk assessment:%{boldEnd} Pending'}
  `('names an assessment that is $description', ({ riskAssessment, options, summaryTitle }) => {
    const state = getRiskAssessmentState(riskAssessment, options);

    expect(state.isAssessed).toBe(false);
    expect(state.meterSeverity).toBeNull();
    expect(state.summaryTitle).toBe(summaryTitle);
  });

  it('labels the meter as assessing while loading', () => {
    expect(getRiskAssessmentState(null, { isLoading: true }).meterLabel).toBe('Assessing risk');
  });

  describe('stale warning', () => {
    it.each`
      description                     | overrides                                             | showsStaleWarning
      ${'a stale completed score'}    | ${{ stale: true }}                                    | ${true}
      ${'a stale failed run'}         | ${{ stale: true, status: 'FAILED' }}                  | ${true}
      ${'a stale score being redone'} | ${{ stale: true, status: 'QUEUED' }}                  | ${false}
      ${'a stale pending record'}     | ${{ stale: true, status: 'PENDING', riskTier: null }} | ${false}
      ${'a fresh score'}              | ${{}}                                                 | ${false}
    `('is $showsStaleWarning for $description', ({ overrides, showsStaleWarning }) => {
      const state = getRiskAssessmentState(assessment(overrides));

      expect(state.showsStaleWarning).toBe(showsStaleWarning);
      expect(state.showsFooter).toBe(showsStaleWarning);
    });
  });

  describe('details', () => {
    it.each`
      description                                 | overrides                                                                              | hasDetails
      ${'a rationale'}                            | ${{}}                                                                                  | ${true}
      ${'contributing signals'}                   | ${{ rationale: null, contributingSignals: [{ key: 'size' }] }}                         | ${true}
      ${'low confidence with missing signals'}    | ${{ rationale: null, confidenceTier: 'LOW', missingSignals: [{ label: 'Coverage' }] }} | ${true}
      ${'missing signals without low confidence'} | ${{ rationale: null, missingSignals: [{ label: 'Coverage' }] }}                        | ${false}
      ${'nothing to explain the score'}           | ${{ rationale: null }}                                                                 | ${false}
    `('are shown for $description: $hasDetails', ({ overrides, hasDetails }) => {
      expect(getRiskAssessmentState(assessment(overrides)).hasDetails).toBe(hasDetails);
    });

    it('leaves out missing signals that have no label', () => {
      const state = getRiskAssessmentState(
        assessment({ missingSignals: [{ label: 'Coverage' }, { label: null }] }),
      );

      expect(state.missingSignalLabels).toEqual(['Coverage']);
    });
  });

  describe('session link', () => {
    it.each`
      description                      | overrides                                | duoChatAvailable | showsSessionLink
      ${'a session the user can open'} | ${{ duoWorkflowId: 5 }}                  | ${true}          | ${true}
      ${'no Duo Chat for the user'}    | ${{ duoWorkflowId: 5 }}                  | ${false}         | ${false}
      ${'no session'}                  | ${{}}                                    | ${true}          | ${false}
      ${'no details to discuss'}       | ${{ duoWorkflowId: 5, rationale: null }} | ${true}          | ${false}
    `(
      'is $showsSessionLink for $description',
      ({ overrides, duoChatAvailable, showsSessionLink }) => {
        const state = getRiskAssessmentState(assessment(overrides), { duoChatAvailable });

        expect(state.showsSessionLink).toBe(showsSessionLink);
        expect(state.showsFooter).toBe(showsSessionLink);
      },
    );
  });
});
