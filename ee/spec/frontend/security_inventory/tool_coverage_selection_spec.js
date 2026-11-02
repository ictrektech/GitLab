import { tokensToQueryParams } from 'ee/security_inventory/filter_url_sync';
import {
  cardSelectionFromParams,
  paramsFromCardSelection,
} from 'ee/security_inventory/tool_coverage_selection';
import { STATUS_FILTER_TO_TOOL_STATUS } from 'ee/security_inventory/constants';
import { toolCoverageTokens } from 'ee/security_inventory/components/tool_coverage_tokens';
import { statusTokens } from 'ee/security_inventory/components/status_tokens';

const definedParams = (params) =>
  Object.fromEntries(Object.entries(params).filter(([, value]) => value != null));

const noSelection = { scanner: 'ANY', status: null };

describe('cardSelectionFromParams', () => {
  it('reads a scanner and status from one param', () => {
    expect(cardSelectionFromParams({ dast: 'failed' })).toEqual({
      scanner: 'DAST',
      status: 'FAILED',
    });
  });

  it('reads a param written in upper case', () => {
    expect(cardSelectionFromParams({ dast: 'FAILED' })).toEqual({
      scanner: 'DAST',
      status: 'FAILED',
    });
  });

  it('reads past params with no value', () => {
    expect(cardSelectionFromParams({ dast: 'failed', sast: null, search: null })).toEqual({
      scanner: 'DAST',
      status: 'FAILED',
    });
  });

  it('reads past a filter it cannot show', () => {
    expect(
      cardSelectionFromParams({
        dast: 'failed',
        search: 'redis',
        'attribute~business_impact': '1',
        'gte[critical]': '5',
      }),
    ).toEqual({ scanner: 'DAST', status: 'FAILED' });
  });

  it.each([
    [
      { scanner: 'DAST', status: 'SUCCESS' },
      { type: 'DAST', value: { data: 'SUCCESS', operator: '=' } },
    ],
    [
      { scanner: 'ANY', status: 'FAILED' },
      { type: 'STATUS', value: { data: 'NEEDS_ATTENTION', operator: '=' } },
    ],
  ])('reads %o back from the params the search bar writes', (selection, barToken) => {
    const barParams = tokensToQueryParams([barToken], [...statusTokens, ...toolCoverageTokens]);

    expect(definedParams(barParams)).toEqual(definedParams(paramsFromCardSelection(selection)));
    expect(cardSelectionFromParams(barParams)).toEqual(selection);
  });

  it.each`
    param                | status
    ${'needs_attention'} | ${'FAILED'}
    ${'stale_scans'}     | ${'STALE'}
    ${'unprotected'}     | ${'NOT_CONFIGURED'}
    ${'has_scanners'}    | ${'SUCCESS'}
  `('reads all scanners with $status from $param', ({ param, status }) => {
    expect(cardSelectionFromParams({ status: param })).toEqual({ scanner: 'ANY', status });
  });

  it.each`
    param                                        | scanner
    ${'sast_advanced'}                           | ${'SAST_ADVANCED'}
    ${'secret_detection_pipeline_based'}         | ${'SECRET_DETECTION_PIPELINE_BASED'}
    ${'secret_detection_secret_push_protection'} | ${'SECRET_DETECTION_SECRET_PUSH_PROTECTION'}
    ${'container_scanning_for_registry'}         | ${'CONTAINER_SCANNING_FOR_REGISTRY'}
  `('reads $param as the sub-scanner $scanner', ({ param, scanner }) => {
    expect(cardSelectionFromParams({ [param]: 'failed' })).toEqual({ scanner, status: 'FAILED' });
  });

  describe('business logic', () => {
    describe('when the bl_security_analyzer flag is on', () => {
      beforeEach(() => {
        window.gon.features = { blSecurityAnalyzer: true };
      });

      it('reads the selection back from the params the search bar writes', () => {
        const selection = { scanner: 'BUSINESS_LOGIC', status: 'FAILED' };
        const barParams = tokensToQueryParams(
          [{ type: 'BUSINESS_LOGIC', value: { data: 'FAILED', operator: '=' } }],
          toolCoverageTokens,
        );

        expect(definedParams(barParams)).toEqual(definedParams(paramsFromCardSelection(selection)));
        expect(cardSelectionFromParams(barParams)).toEqual(selection);
      });
    });

    describe('when the bl_security_analyzer flag is off', () => {
      it('ignores a business logic param', () => {
        expect(cardSelectionFromParams({ business_logic: 'failed' })).toEqual(noSelection);
      });

      it('reads the other scanner when a business logic param is also set', () => {
        expect(cardSelectionFromParams({ dast: 'failed', business_logic: 'failed' })).toEqual({
          scanner: 'DAST',
          status: 'FAILED',
        });
      });
    });
  });

  describe('skillguard', () => {
    describe('when the skillguard_analyzer flag is on', () => {
      beforeEach(() => {
        window.gon.features = { skillguardAnalyzer: true };
      });

      it('reads the selection back from the params the search bar writes', () => {
        const selection = { scanner: 'SKILLGUARD', status: 'FAILED' };
        const barParams = tokensToQueryParams(
          [{ type: 'SKILLGUARD', value: { data: 'FAILED', operator: '=' } }],
          toolCoverageTokens,
        );

        expect(definedParams(barParams)).toEqual(definedParams(paramsFromCardSelection(selection)));
        expect(cardSelectionFromParams(barParams)).toEqual(selection);
      });
    });

    describe('when the skillguard_analyzer flag is off', () => {
      it('ignores a skillguard param', () => {
        expect(cardSelectionFromParams({ skillguard: 'failed' })).toEqual(noSelection);
      });

      it('reads the other scanner when a skillguard param is also set', () => {
        expect(cardSelectionFromParams({ dast: 'failed', skillguard: 'failed' })).toEqual({
          scanner: 'DAST',
          status: 'FAILED',
        });
      });
    });
  });

  describe('with no tool coverage param', () => {
    it('returns no selection', () => {
      expect(cardSelectionFromParams({})).toEqual(noSelection);
      expect(cardSelectionFromParams()).toEqual(noSelection);
    });
  });

  describe('with a second tool coverage param', () => {
    it('returns no selection', () => {
      expect(cardSelectionFromParams({ dast: 'failed', sast: 'stale' })).toEqual(noSelection);
      expect(cardSelectionFromParams({ dast: 'failed', status: 'has_scanners' })).toEqual(
        noSelection,
      );
    });
  });

  describe('with only filters the card cannot show', () => {
    it('returns no selection', () => {
      expect(cardSelectionFromParams({ critical: 'gte:5' })).toEqual(noSelection);
      expect(cardSelectionFromParams({ 'attribute~business_impact': '1' })).toEqual(noSelection);
    });
  });

  describe('with a status the card does not offer', () => {
    it('returns no selection', () => {
      expect(cardSelectionFromParams({ status: 'nope' })).toEqual(noSelection);
      expect(cardSelectionFromParams({ dast: 'nope' })).toEqual(noSelection);
    });
  });
});

describe('STATUS_FILTER_TO_TOOL_STATUS', () => {
  it('keeps one tool status per status filter', () => {
    const toolStatuses = Object.values(STATUS_FILTER_TO_TOOL_STATUS);

    expect(new Set(toolStatuses).size).toBe(toolStatuses.length);
  });
});

describe('paramsFromCardSelection', () => {
  describe('with one scanner chosen', () => {
    it.each`
      scanner            | status              | param
      ${'SAST_IAC'}      | ${'STALE'}          | ${{ sast_iac: 'stale' }}
      ${'DAST'}          | ${'SUCCESS'}        | ${{ dast: 'success' }}
      ${'SAST'}          | ${'NOT_CONFIGURED'} | ${{ sast: 'not_configured' }}
      ${'DAST'}          | ${'FAILED'}         | ${{ dast: 'failed' }}
      ${'SAST_ADVANCED'} | ${'FAILED'}         | ${{ sast_advanced: 'failed' }}
    `('sets $param for $scanner', ({ scanner, status, param }) => {
      expect(definedParams(paramsFromCardSelection({ scanner, status }))).toEqual(param);
    });
  });

  describe('with a status the card cannot show', () => {
    it.each([
      { scanner: 'DAST', status: 'NOPE' },
      { scanner: 'ANY', status: 'NOPE' },
      { status: 'FAILED' },
      { scanner: 'NOT_A_SCANNER', status: 'FAILED' },
    ])('clears every param for %o', (selection) => {
      expect(definedParams(paramsFromCardSelection(selection))).toEqual({});
    });
  });

  describe('with every scanner included', () => {
    it('sets the status param', () => {
      expect(definedParams(paramsFromCardSelection({ scanner: 'ANY', status: 'SUCCESS' }))).toEqual(
        { status: 'has_scanners' },
      );
    });

    it('clears the scanner params it replaces', () => {
      const params = paramsFromCardSelection({ scanner: 'ANY', status: 'SUCCESS' });

      expect(params).toMatchObject({ status: 'has_scanners', dast: null, sast: null });
    });
  });

  it('clears the filter it replaces', () => {
    const params = paramsFromCardSelection({ scanner: 'DAST', status: 'FAILED' });

    expect(params).toMatchObject({ dast: 'failed', sast: null, status: null });
    expect(Object.keys(params)).not.toContain('search');
    expect(Object.keys(params)).not.toContain('attribute~business_impact');
  });

  describe('with no status selected', () => {
    it('clears every tool coverage param', () => {
      expect(definedParams(paramsFromCardSelection({ scanner: 'DAST', status: null }))).toEqual({});
      expect(paramsFromCardSelection({ scanner: 'DAST', status: null })).toMatchObject({
        dast: null,
        status: null,
      });
      expect(definedParams(paramsFromCardSelection())).toEqual({});
    });
  });

  it('returns params the card reads back', () => {
    ['SUCCESS', 'NOT_CONFIGURED', 'FAILED', 'STALE'].forEach((status) => {
      [
        { scanner: 'ANY', status },
        { scanner: 'DAST', status },
        { scanner: 'SECRET_DETECTION_SECRET_PUSH_PROTECTION', status },
      ].forEach((selection) => {
        expect(cardSelectionFromParams(paramsFromCardSelection(selection))).toEqual(selection);
      });
    });
  });
});
