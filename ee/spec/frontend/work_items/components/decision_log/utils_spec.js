import {
  activeDecisions,
  decisionAnchorId,
  decisionText,
  resolvedDecisions,
} from 'ee/work_items/components/decision_log/utils';

describe('activeDecisions', () => {
  const resolved = { id: 1, state: 'RESOLVED' };
  const archived = { id: 2, state: 'ARCHIVED' };

  describe('when the log mixes archived and resolved decisions', () => {
    it('keeps only the ones that are not archived', () => {
      expect(activeDecisions([resolved, archived])).toEqual([resolved]);
    });
  });

  describe('when the log is empty', () => {
    it('returns nothing', () => {
      expect(activeDecisions([])).toEqual([]);
    });
  });

  describe('when no decisions are given', () => {
    it('returns nothing', () => {
      expect(activeDecisions()).toEqual([]);
    });
  });
});

describe('resolvedDecisions', () => {
  const open = { id: 1, state: 'ACTIVE' };
  const resolved = { id: 2, state: 'RESOLVED' };
  const archived = { id: 3, state: 'ARCHIVED' };

  describe('when the log mixes open, resolved and archived decisions', () => {
    it('keeps only the ones that are not open', () => {
      expect(resolvedDecisions([open, resolved, archived])).toEqual([resolved, archived]);
    });
  });

  describe('when no decisions are given', () => {
    it('returns nothing', () => {
      expect(resolvedDecisions()).toEqual([]);
    });
  });
});

describe('decisionText', () => {
  const option = (content, selected) => ({ content, selected });
  const withOptions = (nodes) => ({ question: 'Which IdP first?', options: { nodes } });

  describe('when more than one option is settled', () => {
    it('joins the settled options', () => {
      const decision = withOptions([
        option('Okta', true),
        option('Azure AD', false),
        option('Google', true),
      ]);

      expect(decisionText(decision)).toBe('Okta, Google');
    });
  });

  describe('when one option is settled', () => {
    it('returns that option', () => {
      expect(decisionText(withOptions([option('Okta', true)]))).toBe('Okta');
    });
  });

  describe('when no option is settled', () => {
    it('returns the question', () => {
      expect(decisionText(withOptions([option('Okta', false)]))).toBe('Which IdP first?');
    });
  });

  describe('when the backend returns no question', () => {
    it('returns the title', () => {
      const decision = { question: null, title: 'Which IdP first?', options: { nodes: [] } };

      expect(decisionText(decision)).toBe('Which IdP first?');
    });
  });

  describe('when no decision is given', () => {
    it('returns an empty string', () => {
      expect(decisionText()).toBe('');
    });
  });
});

describe('decisionAnchorId', () => {
  it('builds the hash from the numeric id of the decision', () => {
    expect(decisionAnchorId({ id: 'gid://gitlab/WorkItems::Decision/12' })).toBe('decision_12');
  });
});
