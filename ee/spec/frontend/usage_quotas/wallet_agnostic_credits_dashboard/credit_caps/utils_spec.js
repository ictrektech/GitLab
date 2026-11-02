import { parseOverridesCsv as parseCsv } from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/utils';

describe('parseOverridesCsv', () => {
  describe('with valid input', () => {
    it('parses a single valid line', () => {
      // prettier-ignore
      const csv = [
        'user1,100,true',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides).toEqual([{ username: 'user1', cap: 100, enabled: true }]);
    });

    it('parses multiple valid lines', () => {
      // prettier-ignore
      const csv = [
        'user1,100,true',
        'user2,50.5,false',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides).toEqual([
        { username: 'user1', cap: 100, enabled: true },
        { username: 'user2', cap: 50.5, enabled: false },
      ]);
    });

    it('trims whitespace around values', () => {
      // prettier-ignore
      const csv = [
        ' user1 , 100 , true ',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides).toEqual([{ username: 'user1', cap: 100, enabled: true }]);
    });

    describe('with an optional header row', () => {
      it('ignores a header row when it is the first line', () => {
        // prettier-ignore
        const csv = [
          'username,cap,enabled',
          'user1,100,true',
          'user2,50,false',
        ].join('\n');

        const { overrides, errors } = parseCsv(csv);

        expect(errors).toHaveLength(0);
        expect(overrides).toHaveLength(2);
        expect(overrides[0].username).toBe('user1');
      });

      it.each(['Username,Cap,Enabled', 'USERNAME,CAP,ENABLED', 'Username , Cap , Enabled'])(
        'ignores header row with variant casing/spacing: "%s"',
        (headerLine) => {
          const csv = [headerLine, 'user1,100,true'].join('\n');

          const { overrides, errors } = parseCsv(csv);

          expect(errors).toHaveLength(0);
          expect(overrides).toHaveLength(1);
        },
      );

      it.each(['username,cap', 'username,cap,enabled,extra'])(
        'does not skip an incomplete or extended header-like row: "%s"',
        (headerLine) => {
          const csv = [headerLine, 'user1,100,true'].join('\n');

          const { errors } = parseCsv(csv);

          expect(errors).toHaveLength(1);
          expect(errors[0]).toContain('Line 1');
        },
      );

      it('shows an error when header row is not on the first line', () => {
        // prettier-ignore
        const csv = [
          'user1,100,true',
          'username,cap,enabled',
        ].join('\n');

        const { errors } = parseCsv(csv);

        expect(errors).toHaveLength(1);
        expect(errors[0]).toContain('Line 2');
        expect(errors[0]).toContain('header should be placed on the first line');
      });
    });

    it('ignores blank lines', () => {
      // prettier-ignore
      const csv = [
        'user1,100,true',
        '',
        'user2,50,false',
        '',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides).toHaveLength(2);
    });

    it('ignores lines with only spaces or tabs', () => {
      // prettier-ignore
      const csv = [
        'user1,100,true',
        '   ',
        'user2,50,false',
        '\t',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides).toHaveLength(2);
    });

    it('allows cap of zero', () => {
      // prettier-ignore
      const csv = [
        'user1,0,true',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides).toEqual([{ username: 'user1', cap: 0, enabled: true }]);
    });

    it('allows fractional cap values', () => {
      // prettier-ignore
      const csv = [
        'user1,99.99,false',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides).toEqual([{ username: 'user1', cap: 99.99, enabled: false }]);
    });

    it('handles quoted fields with commas inside', () => {
      // prettier-ignore
      const csv = [
        '"user,one",100,true',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides).toEqual([{ username: 'user,one', cap: 100, enabled: true }]);
    });

    it('returns enabled: false when enabled column is "false"', () => {
      // prettier-ignore
      const csv = [
        'user1,10,false',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides[0].enabled).toBe(false);
    });
  });

  describe('with empty input', () => {
    it('returns no overrides and no errors for empty string', () => {
      const { overrides, errors } = parseCsv('');

      expect(overrides).toHaveLength(0);
      expect(errors).toHaveLength(0);
    });
  });

  describe('with invalid input', () => {
    describe('when input cannot be parsed', () => {
      it('returns a malformed error for input with unclosed quotes', () => {
        const { overrides, errors } = parseCsv('"user1,100,true');

        expect(overrides).toHaveLength(0);
        expect(errors[0]).toContain('could not be parsed');
      });
    });

    it('returns an error when a line has fewer than 3 fields', () => {
      // prettier-ignore
      const csv = [
        'user1,100',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(overrides).toHaveLength(0);
      expect(errors[0]).toContain('Line 1');
      expect(errors[0]).toContain('3 comma-separated values');
    });

    it('returns an error when a line has only 1 field', () => {
      // prettier-ignore
      const csv = [
        'user1',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(overrides).toHaveLength(0);
      expect(errors[0]).toContain('Line 1');
      expect(errors[0]).toContain('3 comma-separated values');
    });

    it.each(['user1\t100\ttrue', 'user1;100;true'])(
      'returns an error when "%s" is not separated with a comma',
      (line) => {
        const { overrides, errors } = parseCsv(line);

        expect(overrides).toHaveLength(0);
        expect(errors[0]).toContain('Line 1');
        expect(errors[0]).toContain('3 comma-separated values');
      },
    );

    it('returns an error when a line has more than 3 fields', () => {
      // prettier-ignore
      const csv = [
        'user1,100,true,extra',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(overrides).toHaveLength(0);
      expect(errors[0]).toContain('Line 1');
      expect(errors[0]).toContain('3 comma-separated values');
    });

    it('returns an error when username is empty', () => {
      // prettier-ignore
      const csv = [
        ',100,true',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(overrides).toHaveLength(0);
      expect(errors[0]).toContain('username is required');
    });

    it('returns an error when username is whitespace only', () => {
      // prettier-ignore
      const csv = [
        '   ,100,true',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(overrides).toHaveLength(0);
      expect(errors[0]).toContain('username is required');
    });

    it('returns an error when username contains @', () => {
      // prettier-ignore
      const csv = [
        'user@example.com,100,true',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(overrides).toHaveLength(0);
      expect(errors[0]).toContain('"@"');
    });

    it('returns an error when cap is missing', () => {
      // prettier-ignore
      const csv = [
        'user1,,true',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(overrides).toHaveLength(0);
      expect(errors[0]).toContain('cap value is required');
    });

    it.each(['abc', 'Infinity', '-Infinity', 'NaN'])(
      'returns an error when cap is "%s"',
      (capValue) => {
        // prettier-ignore
        const csv = [
          `user1,${capValue},true`,
        ].join('\n');

        const { overrides, errors } = parseCsv(csv);

        expect(overrides).toHaveLength(0);
        expect(errors[0]).toContain('valid number');
      },
    );

    it.each(['-1', '-0.01', '-100'])('returns an error when cap is negative (%s)', (capValue) => {
      // prettier-ignore
      const csv = [
        `user1,${capValue},true`,
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(overrides).toHaveLength(0);
      expect(errors[0]).toContain('must not be negative');
    });

    it.each(['yes', 'no', '1', '0', ''])(
      'returns an error when enabled is "%s"',
      (enabledValue) => {
        // prettier-ignore
        const csv = [
          `user1,100,${enabledValue}`,
        ].join('\n');

        const { overrides, errors } = parseCsv(csv);

        expect(overrides).toHaveLength(0);
        expect(errors[0]).toContain('"true" or "false"');
      },
    );

    it.each([
      ['true', true],
      ['True', true],
      ['TRUE', true],
      ['false', false],
      ['False', false],
      ['FALSE', false],
    ])('accepts "%s" as enabled value and normalises to boolean', (enabledValue, expected) => {
      // prettier-ignore
      const csv = [
        `user1,100,${enabledValue}`,
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(0);
      expect(overrides[0].enabled).toBe(expected);
    });

    it('collects errors from multiple invalid lines', () => {
      // prettier-ignore
      const csv = [
        'user1,abc,true',
        'user2,100,yes',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(overrides).toHaveLength(0);
      expect(errors).toHaveLength(2);
      expect(errors[0]).toContain('Line 1');
      expect(errors[1]).toContain('Line 2');
    });

    it('returns no overrides when any line has an error', () => {
      // prettier-ignore
      const csv = [
        'user1,100,true',
        'user2,bad,true',
      ].join('\n');

      const { overrides, errors } = parseCsv(csv);

      expect(errors).toHaveLength(1);
      expect(overrides).toHaveLength(0);
    });

    it('assigns line numbers matching the source textarea line', () => {
      // prettier-ignore
      const csv = [
        '',
        'user1,abc,true',
      ].join('\n');

      const { errors } = parseCsv(csv);

      expect(errors[0]).toContain('Line 2');
    });
  });
});
