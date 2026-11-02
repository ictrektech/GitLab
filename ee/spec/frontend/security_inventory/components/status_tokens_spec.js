import { statusTokens } from 'ee/security_inventory/components/status_tokens';

describe('statusTokens', () => {
  const [statusToken] = statusTokens;

  it('renders one unique status token', () => {
    expect(statusTokens).toHaveLength(1);
    expect(statusToken.type).toBe('STATUS');
    expect(statusToken.unique).toBe(true);
  });

  it('includes an option for each coverage state', () => {
    expect(statusToken.options).toStrictEqual([
      { value: 'NEEDS_ATTENTION', title: 'Needs attention' },
      { value: 'STALE_SCANS', title: 'Has stale scans' },
      { value: 'HAS_SCANNERS', title: 'Has scanners enabled' },
      { value: 'UNPROTECTED', title: 'Unprotected' },
    ]);
  });
});
