/* eslint-disable import-x/extensions */
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import IntegrationSlowWaitsReporter, {
  formatSlowWaits,
} from '../../../../scripts/frontend/integration_slow_waits_reporter.mjs';
import { SLOW_WAIT_HINT } from '../../../../scripts/frontend/post_integration_test_summary.mjs';

const slowWait = (test, elapsedMs) =>
  JSON.stringify({
    file: '/gdk/gitlab/ee/spec/frontend/integration/a_spec.js',
    test,
    elapsedMs,
    ceilingMs: 3000,
  });

const runResults = (assertionResults) => ({
  testResults: [
    {
      testFilePath: '/gdk/gitlab/ee/spec/frontend/integration/b_spec.js',
      testResults: assertionResults,
    },
  ],
});

describe('formatSlowWaits', () => {
  describe('with no slow waits or timeouts', () => {
    it('returns no lines', () => {
      expect(formatSlowWaits({ slowWaits: [], timedOut: [], path: 'tmp/w.jsonl' })).toEqual([]);
    });
  });

  describe('with slow waits and a timed-out test', () => {
    it('lists the timeout first, then the waits slowest first', () => {
      expect(
        formatSlowWaits({
          slowWaits: [
            { path: 'a_spec.js', test: 'renders', elapsedMs: 2100, ceilingMs: 3000 },
            { path: 'a_spec.js', test: 'filters', elapsedMs: 2500, ceilingMs: 3000 },
          ],
          timedOut: [{ path: 'b_spec.js', test: 'hangs' }],
          path: 'tmp/w.jsonl',
        }),
      ).toEqual([
        '',
        'Slow waits (3)',
        '  🔴 timed out   b_spec.js  hangs',
        '  ⚠️  2.5s / 3s  a_spec.js  filters',
        '  ⚠️  2.1s / 3s  a_spec.js  renders',
        SLOW_WAIT_HINT,
        'Recorded in tmp/w.jsonl',
      ]);
    });
  });
});

describe('IntegrationSlowWaitsReporter', () => {
  let rootDir;
  let reporter;

  const recordedPath = () => join(rootDir, 'tmp/jest-integration-local-slow-waits.jsonl');

  beforeEach(() => {
    rootDir = mkdtempSync(join(tmpdir(), 'slow-waits-reporter-'));
    jest.replaceProperty(process, 'env', { ...process.env });
    delete process.env.JEST_INTEGRATION_SLOW_WAITS_FILE;
    jest.spyOn(process.stderr, 'write').mockImplementation(() => true);
    reporter = new IntegrationSlowWaitsReporter({ rootDir });
  });

  describe('onRunStart', () => {
    beforeEach(() => {
      reporter.onRunStart();
    });

    it('points the test workers at a file under tmp/', () => {
      expect(process.env.JEST_INTEGRATION_SLOW_WAITS_FILE).toBe(recordedPath());
    });

    it('starts the file empty', () => {
      expect(readFileSync(recordedPath(), 'utf8')).toBe('');
    });

    describe('when a previous run left waits behind', () => {
      beforeEach(() => {
        writeFileSync(recordedPath(), `${slowWait('old run', 2500)}\n`);
        reporter.onRunStart();
      });

      it('clears them', () => {
        expect(readFileSync(recordedPath(), 'utf8')).toBe('');
      });
    });
  });

  describe('when JEST_INTEGRATION_SLOW_WAITS_FILE is already set', () => {
    beforeEach(() => {
      process.env.JEST_INTEGRATION_SLOW_WAITS_FILE = join(rootDir, 'custom.jsonl');
      reporter = new IntegrationSlowWaitsReporter({ rootDir });
      reporter.onRunStart();
    });

    it('keeps the path that was set', () => {
      expect(process.env.JEST_INTEGRATION_SLOW_WAITS_FILE).toBe(join(rootDir, 'custom.jsonl'));
    });
  });

  describe('onRunComplete', () => {
    beforeEach(() => {
      reporter.onRunStart();
    });

    describe('with no slow waits or timeouts', () => {
      beforeEach(() => {
        reporter.onRunComplete(
          new Set(),
          runResults([{ fullName: 'passes', status: 'passed', failureMessages: [] }]),
        );
      });

      it('prints nothing', () => {
        expect(process.stderr.write).not.toHaveBeenCalled();
      });
    });

    describe('with a recorded slow wait and a timed-out test', () => {
      beforeEach(() => {
        writeFileSync(recordedPath(), `${slowWait('renders the list', 2500)}\n`);
        reporter.onRunComplete(
          new Set(),
          runResults([
            {
              fullName: 'App hangs',
              status: 'failed',
              failureMessages: ['thrown: "Exceeded timeout of 7000 ms for a test.'],
            },
          ]),
        );
      });

      it('prints both to stderr with repo-relative paths', () => {
        expect(process.stderr.write).toHaveBeenCalledWith(
          `${[
            '',
            'Slow waits (2)',
            '  🔴 timed out   ee/spec/frontend/integration/b_spec.js  App hangs',
            '  ⚠️  2.5s / 3s  ee/spec/frontend/integration/a_spec.js  renders the list',
            SLOW_WAIT_HINT,
            `Recorded in ${recordedPath()}`,
          ].join('\n')}\n`,
        );
      });
    });
  });
});
