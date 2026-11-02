import { useFakeDate } from 'helpers/fake_date';
import { auditEventsHref, formatAgentType, formatSessionSource } from 'ee/ai/governance/utils';

describe('formatAgentType', () => {
  it.each([
    ['claude-code', 'Claude Code'],
    ['cursor', 'Cursor'],
    ['codex', 'Codex'],
  ])('names the %s agent type by its product name', (agentType, name) => {
    expect(formatAgentType(agentType)).toBe(name);
  });
});

describe('formatSessionSource', () => {
  it.each([
    ['cursor', 'Cursor (glab)'],
    ['codex', 'Codex (glab)'],
    ['claude-code', 'Claude Code (glab)'],
  ])('names a glab session with the %s agent type after its agent', (agentType, label) => {
    expect(formatSessionSource({ source: 'CLAUDE_CODE_GLAB', agentType })).toBe(label);
  });

  it('keeps the glab source label when the session has no agent type', () => {
    expect(formatSessionSource({ source: 'CLAUDE_CODE_GLAB', agentType: null })).toBe(
      'Claude Code (glab)',
    );
  });

  it.each([
    ['GITLAB_DUO', 'GitLab Duo'],
    ['CLAUDE_CODE_COMPLIANCE_API', 'Claude Code (Compliance API)'],
  ])('labels a %s session by its source alone', (source, label) => {
    expect(formatSessionSource({ source, agentType: 'cursor' })).toBe(label);
  });

  it('returns undefined for an unknown source or a missing session', () => {
    expect(formatSessionSource({ source: 'SOMETHING_NEW', agentType: 'cursor' })).toBeUndefined();
    expect(formatSessionSource(null)).toBeUndefined();
  });
});

describe('auditEventsHref', () => {
  useFakeDate(2026, 9, 19, 10);

  it.each([
    ['LAST_7_DAYS', '2026-10-12'],
    ['LAST_30_DAYS', '2026-09-19'],
  ])('starts the %s link at the start of the window', (timeframe, startTimeAfter) => {
    expect(auditEventsHref(timeframe, { projectPath: 'g/p' })).toBe(
      `?tab=agent-artifacts&projectPath=g%2Fp&startTimeAfter=${startTimeAfter}`,
    );
  });

  it('carries a DAP or Connected agent class', () => {
    expect(auditEventsHref('LAST_7_DAYS', { projectPath: 'g/p', agentClass: 'EXTERNAL' })).toBe(
      '?tab=agent-artifacts&projectPath=g%2Fp&agentClass=EXTERNAL&startTimeAfter=2026-10-12',
    );
  });

  it('leaves out the ALL agent class', () => {
    expect(auditEventsHref('LAST_7_DAYS', { projectPath: 'g/p', agentClass: 'ALL' })).toBe(
      '?tab=agent-artifacts&projectPath=g%2Fp&startTimeAfter=2026-10-12',
    );
  });

  it('leaves the date out for a timeframe it does not know', () => {
    expect(auditEventsHref('LAST_24_HOURS')).toBe('?tab=agent-artifacts');
  });
});
