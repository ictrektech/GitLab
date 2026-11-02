import fs from 'fs';
import path from 'path';
import { useFakeDate } from 'helpers/fake_date';
import {
  startOfReportingWindow,
  toEvaluations,
  toEvaluationsCount,
  verdictLabel,
  verdictVariant,
} from 'ee/policy_store/evaluations';

describe('startOfReportingWindow', () => {
  useFakeDate(2026, 8, 9, 17, 42);

  // Pinned to UTC midnight so the number does not change as the day passes and
  // the Apollo cache key stays stable across mounts.
  it('starts at UTC midnight six days back, so today counts as the seventh day', () => {
    expect(startOfReportingWindow()).toBe('2026-09-03T00:00:00.000Z');
  });
});

describe('toEvaluationsCount', () => {
  it('reads the total from the connection', () => {
    expect(toEvaluationsCount({ count: 12 })).toBe(12);
  });

  it('counts zero as zero rather than unknown', () => {
    expect(toEvaluationsCount({ count: 0 })).toBe(0);
  });

  it.each([null, undefined, {}])('reads %p as unknown', (connection) => {
    expect(toEvaluationsCount(connection)).toBe(null);
  });
});

describe('toEvaluations', () => {
  const node = (overrides = {}) => ({
    id: 'gid://gitlab/Govern::PolicyEvaluation/1',
    triggerType: 'PROJECT_BEFORE_SETTINGS_UPDATE',
    mode: 'ENFORCE',
    verdict: 'DENY',
    evaluatedAt: '2026-10-20T09:00:00Z',
    projectId: 9,
    project: { id: 'gid://gitlab/Project/9', nameWithNamespace: 'A / B', webPath: '/a/b' },
    violations: [{ id: 'gid://gitlab/Govern::PolicyViolation/1', details: { a: 1 } }],
    ...overrides,
  });

  it.each([null, undefined, {}])(
    'reads %p as unknown rather than an empty history',
    (connection) => {
      expect(toEvaluations(connection)).toBe(null);
    },
  );

  it('reads an empty connection as an empty history', () => {
    expect(toEvaluations({ nodes: [] })).toEqual([]);
  });

  // The enum arrives as its value name, not the wire id the catalog is keyed by.
  it('resolves the trigger through the catalog', () => {
    const [row] = toEvaluations({ nodes: [node()] });

    expect(row.trigger.id).toBe('project.before_settings_update');
    expect(row.trigger.label).toBe('Project settings change requested');
  });

  // The whole point of RECORDED_TRIGGERS: without it this row would read its wire id.
  it('resolves the drift check, which no author can pick', () => {
    const [row] = toEvaluations({
      nodes: [node({ triggerType: 'PROJECT_SCHEDULED_SETTINGS_DRIFT_CHECK' })],
    });

    expect(row.trigger.id).toBe('project.scheduled_settings_drift_check');
    expect(row.trigger.label).toBe('Daily settings check');
  });

  it('falls back to the raw value for a trigger neither catalog knows', () => {
    const [row] = toEvaluations({ nodes: [node({ triggerType: 'PROJECT_SOMETHING_NEW' })] });

    expect(row.trigger.label).toBe('PROJECT_SOMETHING_NEW');
    expect(row.trigger.icon).toBe('question-o');
  });

  it('lowercases the mode and verdict enums onto the ids the labels are keyed by', () => {
    const [row] = toEvaluations({ nodes: [node({ mode: 'AUDIT', verdict: 'REQUIRE_APPROVAL' })] });

    expect(row.mode).toBe('audit');
    expect(row.verdict).toBe('require_approval');
  });

  it('keeps the project, the timestamp and the violations', () => {
    const [row] = toEvaluations({ nodes: [node()] });

    expect(row.project.nameWithNamespace).toBe('A / B');
    expect(row.evaluatedAt).toBe('2026-10-20T09:00:00Z');
    expect(row.violations).toHaveLength(1);
  });

  it('reads an unscoped evaluation as having no project and no violations', () => {
    const [row] = toEvaluations({
      nodes: [node({ projectId: null, project: null, violations: null })],
    });

    expect(row.projectId).toBe(null);
    expect(row.project).toBe(null);
    expect(row.violations).toEqual([]);
  });

  // Both null the project, and only the id says which of the two happened.
  it('keeps the id of a project the viewer cannot read', () => {
    const [row] = toEvaluations({ nodes: [node({ project: null })] });

    expect(row.projectId).toBe(9);
    expect(row.project).toBe(null);
  });
});

describe('verdictLabel and verdictVariant', () => {
  it.each`
    verdict               | label                  | variant
    ${'allow'}            | ${'Allowed'}           | ${'success'}
    ${'deny'}             | ${'Denied'}            | ${'danger'}
    ${'require_approval'} | ${'Approval required'} | ${'warning'}
  `('presents $verdict as $label', ({ verdict, label, variant }) => {
    expect(verdictLabel(verdict)).toBe(label);
    expect(verdictVariant(verdict)).toBe(variant);
  });

  it('falls back to the raw value for a verdict it does not know', () => {
    expect(verdictLabel('escalate')).toBe('escalate');
    expect(verdictVariant('escalate')).toBe('neutral');
  });

  // The fallback above keeps an unknown verdict from crashing the list, but it renders
  // the raw wire value — the leak RECORDED_TRIGGERS exists to close for triggers. The
  // verdict enum is closed and lives in one place, so pin the frontend's copy to it.
  it('labels every verdict the model can record', () => {
    const source = fs.readFileSync(
      path.join(__dirname, '../../../app/models/govern/policy_evaluation.rb'),
      'utf8',
    );
    const declaration = source.match(/enum :verdict, \{([^}]+)\}/);

    expect(declaration).not.toBe(null);

    const verdicts = [...declaration[1].matchAll(/(\w+):/g)].map(([, verdict]) => verdict);

    expect(verdicts.length).toBeGreaterThan(0);
    expect(verdicts.filter((verdict) => verdictLabel(verdict) === verdict)).toEqual([]);
  });
});
