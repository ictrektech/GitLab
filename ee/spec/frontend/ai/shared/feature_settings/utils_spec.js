import {
  groupDuoCodeReviewDepths,
  sortFeatureSettingsByTitle,
  sortFeatureSettingsByReleaseStateThenTitle,
} from 'ee/ai/shared/feature_settings/utils';

const setting = (title, releaseState = 'GA') => ({ title, releaseState });
const titlesOf = (featureSettings) => featureSettings.map(({ title }) => title);

describe('feature settings utils', () => {
  describe('sortFeatureSettingsByTitle', () => {
    it('orders the feature settings alphabetically by title', () => {
      const sorted = sortFeatureSettingsByTitle([
        setting('Security Review'),
        setting('Agents & flows'),
        setting('Agentic Code Review'),
      ]);

      expect(titlesOf(sorted)).toEqual([
        'Agentic Code Review',
        'Agents & flows',
        'Security Review',
      ]);
    });

    it.each([null, undefined, ''])('tolerates a %p title and orders it first', (title) => {
      const sorted = sortFeatureSettingsByTitle([setting('Agents & flows'), setting(title)]);

      expect(titlesOf(sorted)).toEqual([title, 'Agents & flows']);
    });

    it('does not mutate the given array', () => {
      const featureSettings = [setting('Security Review'), setting('Agents & flows')];

      sortFeatureSettingsByTitle(featureSettings);

      expect(titlesOf(featureSettings)).toEqual(['Security Review', 'Agents & flows']);
    });
  });

  describe('sortFeatureSettingsByReleaseStateThenTitle', () => {
    it('orders by release state before title', () => {
      const sorted = sortFeatureSettingsByReleaseStateThenTitle([
        setting('Troubleshoot Job', 'EXPERIMENT'),
        setting('Explain Code', 'BETA'),
        setting('General Chat', 'GA'),
      ]);

      expect(titlesOf(sorted)).toEqual(['General Chat', 'Explain Code', 'Troubleshoot Job']);
    });

    it('keeps a beta feature below a GA feature that is later in the alphabet', () => {
      const sorted = sortFeatureSettingsByReleaseStateThenTitle([
        setting('Secret Vulnerability False Positive Detection', 'GA'),
        setting('Resolve Dependency Bump Breaking Changes', 'BETA'),
      ]);

      expect(titlesOf(sorted)).toEqual([
        'Secret Vulnerability False Positive Detection',
        'Resolve Dependency Bump Breaking Changes',
      ]);
    });

    it('orders alphabetically by title within a release state', () => {
      const sorted = sortFeatureSettingsByReleaseStateThenTitle([
        setting('Security Review', 'BETA'),
        setting('SAST Vulnerability Resolution', 'BETA'),
        setting('Resolve Dependency Bump Breaking Changes', 'BETA'),
      ]);

      expect(titlesOf(sorted)).toEqual([
        'Resolve Dependency Bump Breaking Changes',
        'SAST Vulnerability Resolution',
        'Security Review',
      ]);
    });

    it('orders a feature setting with an unrecognised release state last', () => {
      const sorted = sortFeatureSettingsByReleaseStateThenTitle([
        setting('Agents & flows', 'SOMETHING_NEW'),
        setting('Security Review', 'EXPERIMENT'),
      ]);

      expect(titlesOf(sorted)).toEqual(['Security Review', 'Agents & flows']);
    });

    it('does not mutate the given array', () => {
      const featureSettings = [setting('Explain Code', 'BETA'), setting('General Chat', 'GA')];

      sortFeatureSettingsByReleaseStateThenTitle(featureSettings);

      expect(titlesOf(featureSettings)).toEqual(['Explain Code', 'General Chat']);
    });
  });

  describe('groupDuoCodeReviewDepths', () => {
    const standard = { feature: 'review_merge_request_dap', title: 'Agentic Code Review' };
    const deep = { feature: 'review_merge_request_dap_deep', title: 'Deep Code Review' };
    const agents = { feature: 'duo_agent_platform', title: 'Agents & flows' };
    const security = { feature: 'security_review', title: 'Security Review' };

    describe('when both depths are listed', () => {
      it('replaces them with a header row and one row per depth, Standard first', () => {
        expect(groupDuoCodeReviewDepths([agents, deep, security, standard])).toEqual([
          agents,
          { feature: 'duo_code_review_depths', title: 'Agentic Code Review', isDepthHeader: true },
          {
            ...standard,
            depthLabel: 'Standard',
            depthDescription: 'Efficient review, limited context',
            isDepthChild: true,
            isDepthBlockEnd: false,
          },
          {
            ...deep,
            depthLabel: 'Deep',
            depthDescription: 'Extensive analysis, more context',
            isDepthChild: true,
            isDepthBlockEnd: true,
          },
          security,
        ]);
      });
    });

    describe('when only one depth is listed', () => {
      it('leaves the feature settings unchanged', () => {
        const featureSettings = [agents, standard];

        expect(groupDuoCodeReviewDepths(featureSettings)).toBe(featureSettings);
      });
    });
  });
});
