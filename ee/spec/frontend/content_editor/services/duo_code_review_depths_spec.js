import {
  findDuoCodeReviewDepthQuery,
  getDuoCodeReviewDepths,
  isDuoCodeReviewDepthEnabled,
} from 'ee/content_editor/services/duo_code_review_depths';

describe('ee/content_editor/services/duo_code_review_depths', () => {
  describe('getDuoCodeReviewDepths', () => {
    describe('when duo_code_review_deep_flow is enabled', () => {
      beforeEach(() => {
        window.gon = { features: { duoCodeReviewDeepFlow: true } };
      });

      it.each(['/request_review', '/assign_reviewer', '/reviewer'])(
        'returns Standard and Deep after %s',
        (command) => {
          expect(getDuoCodeReviewDepths(command).map(({ name }) => name)).toEqual([
            'standard',
            'deep',
          ]);
        },
      );

      it.each(['/assign', '/unassign_reviewer', undefined])(
        'returns nothing after %s',
        (command) => {
          expect(getDuoCodeReviewDepths(command)).toEqual([]);
        },
      );
    });

    describe('when duo_code_review_deep_flow is disabled', () => {
      beforeEach(() => {
        window.gon = { features: { duoCodeReviewDeepFlow: false } };
      });

      it('returns nothing after /request_review', () => {
        expect(getDuoCodeReviewDepths('/request_review')).toEqual([]);
      });
    });
  });

  describe('isDuoCodeReviewDepthEnabled', () => {
    it.each([true, false])('follows the flag when it is %s', (enabled) => {
      window.gon = { features: { duoCodeReviewDeepFlow: enabled } };

      expect(isDuoCodeReviewDepthEnabled()).toBe(enabled);
    });
  });

  describe('findDuoCodeReviewDepthQuery', () => {
    describe('when duo_code_review_deep_flow is enabled', () => {
      beforeEach(() => {
        window.gon = { features: { duoCodeReviewDeepFlow: true } };
      });

      it.each`
        line                                   | query
        ${'/request_review @GitLabDuo -'}      | ${''}
        ${'/assign_reviewer @gitlabduo -de'}   | ${'de'}
        ${'/reviewer @alice @GitLabDuo -deep'} | ${'deep'}
      `('returns "$query" for "$line"', ({ line, query }) => {
        expect(findDuoCodeReviewDepthQuery(line)).toBe(query);
      });

      it.each([
        '/request_review @alice -',
        '/request_review @GitLabDuoBot -',
        '/assign @GitLabDuo -',
        '- a list item',
        'Some text -',
      ])('returns null for "%s"', (line) => {
        expect(findDuoCodeReviewDepthQuery(line)).toBeNull();
      });
    });

    describe('when duo_code_review_deep_flow is disabled', () => {
      it('returns null', () => {
        window.gon = { features: { duoCodeReviewDeepFlow: false } };

        expect(findDuoCodeReviewDepthQuery('/request_review @GitLabDuo -')).toBeNull();
      });
    });
  });
});
