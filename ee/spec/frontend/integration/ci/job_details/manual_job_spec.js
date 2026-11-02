import playJobWithInputs from 'test_fixtures/graphql/ci/job_details/integration/play_job_with_inputs.mutation.graphql.json';
import { ignoreConsoleMessages } from 'helpers/console_watcher';
import { TYPENAME_CI_BUILD } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import * as urlUtility from '~/lib/utils/url_utility';
import {
  getText,
  waitAndClick,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import { lastRequestVariables, snapshotRequests } from 'ee_jest/integration/core/operation_helpers';
import restJobVariants from './fixture_variants/rest_job';
import { PLAY_ERROR } from './fixture_variants/play_job_with_inputs';
import {
  findErrorAlert,
  findInputRow,
  findRunJobButton,
  findVariablesToggle,
  mountJobDetails,
  setInputRowValue,
  setVariable,
  useManualJob,
  useManualJobWithInputs,
  useNoTraceResponse,
  usePlayJobError,
} from './test_setup';

const toBuildId = (job) => convertToGraphQLId(TYPENAME_CI_BUILD, job.id);
const PLAYED_JOB_PATH = playJobWithInputs.data.jobPlay.job.webPath;

let visitUrlSpy;

const runJob = async () => {
  await waitAndClick(findRunJobButton);
  await waitForAssertion(() => {
    expect(snapshotRequests().playJobWithInputs).toBe(1);
  });
};

const mountManualJob = async () => {
  useNoTraceResponse();
  mountJobDetails();
  await waitForElement(findRunJobButton);
};

describe('Manual job run form', () => {
  beforeEach(() => {
    visitUrlSpy = jest.spyOn(urlUtility, 'visitUrl');
  });

  describe('when the job is a manual job without inputs', () => {
    beforeEach(async () => {
      useManualJob();
      await mountManualJob();
    });

    // A successful play redirects; jsdom refuses and logs it. Ignoring the message keeps the
    // production `visitUrl` in the chain instead of mocking away part of the flow.
    describe('when the user runs it with a variable', () => {
      ignoreConsoleMessages([/Not implemented: navigation/]);

      beforeEach(async () => {
        await waitAndClick(findVariablesToggle);
        setVariable({ key: 'key_name', value: 'key_value' });
        await runJob();
      });

      it('sends the variable with the job play request', () => {
        expect(lastRequestVariables('playJobWithInputs')).toEqual({
          id: toBuildId(restJobVariants.MANUAL),
          variables: [{ key: 'key_name', value: 'key_value' }],
          inputs: [],
        });
      });

      it('redirects to the played job without an error alert', async () => {
        await waitForAssertion(() => {
          expect(visitUrlSpy).toHaveBeenCalledWith(PLAYED_JOB_PATH);
        });
        expect(findErrorAlert()).toBe(null);
      });
    });
  });

  describe('when the job play fails', () => {
    beforeEach(async () => {
      useManualJob();
      usePlayJobError();
      await mountManualJob();
      await runJob();
      await waitForElement(findErrorAlert);
    });

    it('shows the error and stays on the page', () => {
      expect(getText(findErrorAlert())).toContain(PLAY_ERROR);
      expect(visitUrlSpy).not.toHaveBeenCalled();
    });
  });

  describe('when the job is a manual job with inputs', () => {
    beforeEach(async () => {
      useManualJobWithInputs();
      await mountManualJob();
      // `getJob` replaces the cached `inputsSpec` with its `{ name }`-only selection, so
      // `getJobInputs` refetches. Let it land here, not in the next test's cache.
      await waitForAssertion(() => {
        expect(snapshotRequests().getJobInputs).toBe(2);
      });
      await waitForElement(() => findInputRow('environment'));
    });

    it('shows the job inputs', () => {
      expect(findInputRow('environment')).not.toBe(null);
    });

    describe('when the user runs it with an input value', () => {
      ignoreConsoleMessages([/Not implemented: navigation/]);

      beforeEach(async () => {
        setInputRowValue('environment', 'production');
        await runJob();
      });

      it('sends only the modified input with the job play request', () => {
        expect(lastRequestVariables('playJobWithInputs')).toEqual({
          id: toBuildId(restJobVariants.MANUAL_WITH_INPUTS),
          variables: [],
          inputs: [{ name: 'environment', value: 'production' }],
        });
      });

      it('redirects to the played job without an error alert', async () => {
        await waitForAssertion(() => {
          expect(visitUrlSpy).toHaveBeenCalledWith(PLAYED_JOB_PATH);
        });
        expect(findErrorAlert()).toBe(null);
      });
    });
  });
});
