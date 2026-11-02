import {
  buildEmptyRule,
  buildDefaultRuleForType,
  getRuleListKey,
  getRuleList,
  toggleRuleListKey,
  namesToItems,
  itemsToNames,
  exceptionsToLines,
  linesToExceptions,
  ruleWithExceptionsForKey,
  isValidReferenceLink,
  EXCEPTION_KEY_ID,
  EXCEPTION_KEY_PURL,
} from 'ee/security_orchestration/components/policy_editor/dependency_firewall/utils';
import {
  RULE_TYPE_LICENSE,
  RULE_TYPE_MALICIOUS,
  RULE_TYPE_RISK_SEVERITY,
  RULE_TYPE_PACKAGE_VERSION,
} from 'ee/security_orchestration/components/policy_editor/dependency_firewall/constants';

describe('dependency_firewall/utils', () => {
  it('buildEmptyRule returns a rule with no type and a unique id', () => {
    expect(buildEmptyRule()).toMatchObject({ type: '' });
    expect(buildEmptyRule().id).not.toBe(buildEmptyRule().id);
  });

  it.each`
    type                         | expected
    ${RULE_TYPE_LICENSE}         | ${{ type: RULE_TYPE_LICENSE, denied: [] }}
    ${RULE_TYPE_MALICIOUS}       | ${{ type: RULE_TYPE_MALICIOUS, denied: [{ is_malicious: true }] }}
    ${RULE_TYPE_RISK_SEVERITY}   | ${{ type: RULE_TYPE_RISK_SEVERITY, denied: [{ threshold: 0 }] }}
    ${RULE_TYPE_PACKAGE_VERSION} | ${{ type: RULE_TYPE_PACKAGE_VERSION, denied: [{ name: '', version: '' }] }}
  `('buildDefaultRuleForType($type) returns $expected', ({ type, expected }) => {
    expect(buildDefaultRuleForType(type)).toMatchObject(expected);
  });

  it('buildDefaultRuleForType gives each rule a unique id', () => {
    expect(buildDefaultRuleForType(RULE_TYPE_LICENSE).id).not.toBe(
      buildDefaultRuleForType(RULE_TYPE_LICENSE).id,
    );
  });

  it('buildDefaultRuleForType returns empty rule for unrecognized type', () => {
    expect(buildDefaultRuleForType('unknown')).toMatchObject({ type: '' });
  });

  it('getRuleListKey returns "denied" when the rule has a denied list', () => {
    expect(getRuleListKey({ type: RULE_TYPE_LICENSE, denied: [] })).toBe('denied');
  });

  it('getRuleListKey returns "allowed" when the rule has an allowed list', () => {
    expect(getRuleListKey({ type: RULE_TYPE_LICENSE, allowed: [] })).toBe('allowed');
  });

  it('getRuleList returns the array under whichever key is present', () => {
    expect(getRuleList({ type: RULE_TYPE_LICENSE, allowed: [{ name: 'MIT' }] })).toEqual([
      { name: 'MIT' },
    ]);
  });

  it('toggleRuleListKey moves the existing list to the new key', () => {
    expect(
      toggleRuleListKey({ type: RULE_TYPE_LICENSE, denied: [{ name: 'MIT' }] }, 'allowed'),
    ).toEqual({
      type: RULE_TYPE_LICENSE,
      allowed: [{ name: 'MIT' }],
    });
  });

  it('namesToItems/itemsToNames round-trip', () => {
    const names = ['MIT', 'GPL-3.0'];
    expect(itemsToNames(namesToItems(names))).toEqual(names);
  });

  it('exceptionsToLines/linesToExceptions round-trip for purls', () => {
    const exceptions = [{ purl: 'pkg:npm/lodash@4.17.21' }];
    expect(linesToExceptions(exceptionsToLines(exceptions), EXCEPTION_KEY_PURL)).toEqual(
      exceptions,
    );
  });

  it('exceptionsToLines/linesToExceptions round-trip for ids', () => {
    const exceptions = [{ id: 'CVE-2021-23337' }];
    expect(linesToExceptions(exceptionsToLines(exceptions), EXCEPTION_KEY_ID)).toEqual(exceptions);
  });

  it('linesToExceptions keys every line by the field it came from, not by its text', () => {
    // A half-typed PURL must stay in the packages field rather than becoming an id.
    expect(linesToExceptions(['pk', 'pkg:npm/lodash@4.17.21'], EXCEPTION_KEY_PURL)).toEqual([
      { purl: 'pk' },
      { purl: 'pkg:npm/lodash@4.17.21' },
    ]);
    expect(linesToExceptions(['pkg:npm/lodash@4.17.21'], EXCEPTION_KEY_ID)).toEqual([
      { id: 'pkg:npm/lodash@4.17.21' },
    ]);
  });

  describe('ruleWithExceptionsForKey', () => {
    it('adds exceptions under the given key', () => {
      const rule = { type: RULE_TYPE_LICENSE, denied: [{ name: 'MIT' }] };

      expect(
        ruleWithExceptionsForKey(rule, ['pkg:npm/lodash@4.17.21'], EXCEPTION_KEY_PURL),
      ).toEqual({
        type: RULE_TYPE_LICENSE,
        denied: [{ name: 'MIT' }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }],
      });
    });

    it('removes the exceptions key entirely when the list is cleared', () => {
      const rule = {
        type: RULE_TYPE_LICENSE,
        denied: [{ name: 'MIT' }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.21' }],
      };

      const updated = ruleWithExceptionsForKey(rule, [], EXCEPTION_KEY_PURL);

      expect(updated).toEqual({ type: RULE_TYPE_LICENSE, denied: [{ name: 'MIT' }] });
      expect(updated).not.toHaveProperty('exceptions');
    });

    it('preserves entries under the other key instead of relabelling or dropping them', () => {
      // A malicious/license rule hand-edited to add a `{ id }` exception must keep it when
      // the (purl-only) UI field is touched, rather than silently turning it into a purl.
      const rule = {
        type: RULE_TYPE_MALICIOUS,
        denied: [{ is_malicious: true }],
        exceptions: [{ id: 'CVE-2021-23337' }],
      };

      const updated = ruleWithExceptionsForKey(
        rule,
        ['pkg:npm/lodash@4.17.21'],
        EXCEPTION_KEY_PURL,
      );

      expect(updated.exceptions).toEqual([
        { id: 'CVE-2021-23337' },
        { purl: 'pkg:npm/lodash@4.17.21' },
      ]);
    });

    it('replaces only entries under the given key, not the whole list', () => {
      const rule = {
        type: RULE_TYPE_MALICIOUS,
        denied: [{ is_malicious: true }],
        exceptions: [{ id: 'CVE-2021-23337' }, { purl: 'pkg:npm/old-lib' }],
      };

      const updated = ruleWithExceptionsForKey(rule, ['pkg:npm/new-lib'], EXCEPTION_KEY_PURL);

      expect(updated.exceptions).toEqual([{ id: 'CVE-2021-23337' }, { purl: 'pkg:npm/new-lib' }]);
    });
  });

  describe('isValidReferenceLink', () => {
    it.each(['https://example.com/CVE-123', 'http://example.com'])('accepts %s', (link) => {
      expect(isValidReferenceLink(link)).toBe(true);
    });

    it.each([
      'ftp://example.com',
      'example.com',
      'https://',
      'https://a\nb',
      'mailto:x\nhttps://example.com',
    ])('rejects %s', (link) => {
      expect(isValidReferenceLink(link)).toBe(false);
    });
  });
});
