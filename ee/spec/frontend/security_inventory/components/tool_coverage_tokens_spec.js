import {
  toolCoverageTokens,
  visibleToolCoverageTokens,
} from 'ee/security_inventory/components/tool_coverage_tokens';
import { BUSINESS_LOGIC_KEY, SKILLGUARD_KEY } from 'ee/security_inventory/constants';

describe('toolCoverageTokens', () => {
  const [groupToken] = toolCoverageTokens;
  const defaultMatcher = (keyword, query) => keyword.toLowerCase().includes(query.toLowerCase());
  const matches = (query) => groupToken.match({ query, title: groupToken.title, defaultMatcher });
  const findToken = (type) => visibleToolCoverageTokens().find((token) => token.type === type);

  describe('while both experiment flags are off', () => {
    it('offers neither experiment token', () => {
      expect(findToken(BUSINESS_LOGIC_KEY)).toBeUndefined();
      expect(findToken(SKILLGUARD_KEY)).toBeUndefined();
      expect(visibleToolCoverageTokens()).toHaveLength(toolCoverageTokens.length - 2);
    });

    it('does not match the tool coverage group on either label', () => {
      expect(matches('Business logic')).toBe(false);
      expect(matches('SkillGuard')).toBe(false);
    });
  });

  describe('when the bl_security_analyzer flag is on', () => {
    beforeEach(() => {
      window.gon.features = { blSecurityAnalyzer: true };
    });

    it('offers the business logic token like the other scanner tokens', () => {
      expect(findToken(BUSINESS_LOGIC_KEY)).toMatchObject({
        title: 'Business logic scanning (BL)',
        segmentTitle: 'Business logic scanning',
        unique: true,
        options: expect.arrayContaining([{ value: 'SUCCESS', title: 'Enabled' }]),
      });
    });

    it('still withholds the skillguard token', () => {
      expect(findToken(SKILLGUARD_KEY)).toBeUndefined();
    });

    it('matches the tool coverage group on the business logic label', () => {
      expect(matches('Business logic')).toBe(true);
    });
  });

  describe('when the skillguard_analyzer flag is on', () => {
    beforeEach(() => {
      window.gon.features = { skillguardAnalyzer: true };
    });

    it('offers the skillguard token like the other scanner tokens', () => {
      expect(findToken(SKILLGUARD_KEY)).toMatchObject({
        title: 'SkillGuard (SG)',
        segmentTitle: 'SkillGuard',
        unique: true,
        options: expect.arrayContaining([{ value: 'SUCCESS', title: 'Enabled' }]),
      });
    });

    it('still withholds the business logic token', () => {
      expect(findToken(BUSINESS_LOGIC_KEY)).toBeUndefined();
    });

    it('matches the tool coverage group on the skillguard label', () => {
      expect(matches('SkillGuard')).toBe(true);
    });
  });

  describe('when both flags are on', () => {
    beforeEach(() => {
      window.gon.features = { blSecurityAnalyzer: true, skillguardAnalyzer: true };
    });

    it('offers every token', () => {
      expect(visibleToolCoverageTokens()).toEqual(toolCoverageTokens);
    });
  });
});
