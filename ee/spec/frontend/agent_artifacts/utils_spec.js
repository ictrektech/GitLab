import {
  formatEventName,
  formatSessionName,
  getClientType,
  normalizeLegacySession,
} from 'ee/agent_artifacts/utils';
import { mockArtifactNodes } from './mock_data';

describe('normalizeLegacySession', () => {
  it('maps a session artifact onto the governance session shape', () => {
    const [node] = mockArtifactNodes;

    expect(normalizeLegacySession(node)).toEqual({
      ...node,
      flowType: 'false_positive_detection/v1',
      sessionStartedAt: '2026-03-05T22:14:17Z',
      sessionId: '1908',
    });
  });
});

describe('formatSessionName', () => {
  it('formats the flow type when present', () => {
    expect(formatSessionName({ flowType: 'code_review/v1', source: 'GITLAB_DUO' })).toBe(
      'Code review/v1',
    );
  });

  it.each([
    ['CLAUDE_CODE_GLAB', 'Claude Code (glab)'],
    ['CLAUDE_CODE_COMPLIANCE_API', 'Claude Code (Compliance API)'],
  ])('falls back to the %s source label when there is no flow type', (source, label) => {
    expect(formatSessionName({ flowType: null, source })).toBe(label);
  });

  it.each([
    ['cursor', 'Cursor (glab)'],
    ['codex', 'Codex (glab)'],
    ['claude-code', 'Claude Code (glab)'],
    [null, 'Claude Code (glab)'],
  ])('names a glab session with the %s agent type after its agent', (agentType, label) => {
    expect(formatSessionName({ flowType: null, source: 'CLAUDE_CODE_GLAB', agentType })).toBe(
      label,
    );
  });

  it('falls back to the generic agent session name without a flow type or known source', () => {
    expect(formatSessionName({ flowType: null })).toBe('Agent session');
  });
});

describe('getClientType', () => {
  it.each([null, undefined])('returns the GitLab Duo default when agentType is %s', (agentType) => {
    expect(getClientType({ agentType })).toEqual({
      name: 'GitLab Duo',
      icon: 'tanuki-ai',
    });
  });

  it.each([
    ['claude-code', 'Claude Code'],
    ['opencode', 'OpenCode'],
    ['cursor', 'Cursor'],
    ['codex', 'Codex'],
  ])('returns the named entry for known agent type %s', (agentType, name) => {
    expect(getClientType({ agentType })).toEqual({ name });
  });

  it('humanises unknown agent types instead of falling back to GitLab Duo', () => {
    expect(getClientType({ agentType: 'some-new-agent' })).toEqual({ name: 'Some new agent' });
  });
});

describe('formatEventName', () => {
  describe('with ai_ prefix', () => {
    it.each([
      ['ai_agent_session_ended', 'Agent session ended'],
      ['ai_llm_input_sent', 'Llm input sent'],
      ['ai_tool_invoked', 'Tool invoked'],
    ])('converts %s to %s', (input, expected) => {
      expect(formatEventName(input)).toBe(expected);
    });
  });

  describe('without ai_ prefix', () => {
    it('capitalises the first letter and replaces underscores with spaces', () => {
      expect(formatEventName('tool_execution')).toBe('Tool execution');
    });
  });

  describe('falsy input guard', () => {
    it.each([null, undefined, ''])('returns an empty string for %s', (input) => {
      expect(formatEventName(input)).toBe('');
    });
  });
});
