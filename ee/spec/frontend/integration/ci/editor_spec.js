import { waitFor } from '@testing-library/vue';
import { editor as monacoEditor } from 'monaco-editor';
import {
  findButtonByText,
  getText,
  waitAndClick,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import {
  findSourceEditor,
  findTab,
  findTabPanel,
  findValidationMessage,
  mountPipelineEditor,
} from './test_setup';

describe('Pipeline editor', () => {
  beforeEach(() => {
    createPortalElement();
  });

  describe('with a CI configuration on the default branch', () => {
    beforeEach(async () => {
      mountPipelineEditor();
      await waitForElement(findSourceEditor);
    });

    it('renders the editor and all pipeline editor tabs', () => {
      expect(findTab('Edit').getAttribute('aria-selected')).toBe('true');
      expect(findTab('Visualize')).not.toBe(null);
      expect(findTab('Validate')).not.toBe(null);
      expect(findTab('Full configuration')).not.toBe(null);
    });

    describe('when the configuration is changed and Reset is clicked', () => {
      beforeEach(async () => {
        monacoEditor.getModels()[0].setValue('Changed');
        await waitAndClick(() => findButtonByText('Reset'));
      });

      describe('when the reset is confirmed', () => {
        beforeEach(async () => {
          await waitAndClick(() => findButtonByText('Reset file'));
        });

        it('restores the committed configuration', async () => {
          await waitFor(() => {
            expect(monacoEditor.getModels()[0].getValue()).toBe('Default');
          });
        });
      });

      describe('when the reset is canceled', () => {
        beforeEach(async () => {
          await waitAndClick(() => findButtonByText('Cancel'));
        });

        it('keeps the changed configuration', () => {
          expect(monacoEditor.getModels()[0].getValue()).toBe('Changed');
        });
      });
    });
  });

  describe('without a CI configuration', () => {
    beforeEach(() => {
      mountPipelineEditor({ branch: 'empty' });
    });

    it('offers the pipeline template picker', async () => {
      await waitFor(() => {
        expect(getText(document.body)).toContain('Get up and running with GitLab CI/CD');
      });
    });

    describe('when the starter template is selected', () => {
      beforeEach(async () => {
        await waitAndClick(() => findButtonByText('Start building'));
      });

      it('loads the recorded starter template into the editor', async () => {
        await waitForElement(findSourceEditor);
        await waitFor(() => {
          expect(monacoEditor.getModels()[0].getValue()).toContain(
            'This file is a template, and might need editing before it works on your project.',
          );
        });
      });
    });
  });

  describe('with valid CI syntax', () => {
    beforeEach(async () => {
      mountPipelineEditor({ branch: 'test' });
      await waitForElement(findSourceEditor);
    });

    it('reports that the pipeline syntax is correct', async () => {
      await waitFor(() => {
        expect(getText(findValidationMessage())).toContain('Pipeline syntax is correct');
      });
    });

    describe('when the Visualize tab is selected', () => {
      beforeEach(async () => {
        await waitAndClick(() => findTab('Visualize'));
      });

      it('renders the pipeline graph', async () => {
        const visualizationTab = await waitForElement(() =>
          findTabPanel('visualization-tab').querySelector('[data-testid="graph-container"]'),
        );

        await waitFor(() => {
          expect(getText(visualizationTab)).toContain('job_a');
        });
      });
    });

    describe('when the pipeline is validated', () => {
      beforeEach(async () => {
        await waitAndClick(() => findTab('Validate'));
        await waitAndClick(() => findButtonByText('Validate pipeline'));
      });

      it('reports a successful simulation', async () => {
        await waitFor(() => {
          expect(getText(document.body)).toContain('Simulation completed successfully');
        });
      });
    });

    describe('when the Full configuration tab is selected', () => {
      beforeEach(async () => {
        await waitAndClick(() => findTab('Full configuration'));
      });

      it('renders the merged configuration as view only', async () => {
        const mergedTab = await waitForElement(() => findTabPanel('merged-tab'));

        await waitFor(() => {
          expect(monacoEditor.getModels().some((model) => model.getValue().includes('job_a'))).toBe(
            true,
          );
          expect(getText(mergedTab)).toContain('Full configuration is view only');
        });
      });
    });
  });

  describe('with invalid CI syntax', () => {
    beforeEach(async () => {
      mountPipelineEditor({ branch: 'despair' });
      await waitForElement(findSourceEditor);
    });

    it('reports that the configuration is invalid', async () => {
      await waitFor(() => {
        expect(getText(findValidationMessage())).toContain(
          'This GitLab CI configuration is invalid',
        );
      });
    });

    describe('when the Visualize tab is selected', () => {
      beforeEach(async () => {
        await waitAndClick(() => findTab('Visualize'));
      });

      it('shows the invalid syntax message instead of a graph', async () => {
        const visualizationTab = await waitForElement(() => findTabPanel('visualization-tab'));

        await waitFor(() => {
          expect(getText(visualizationTab)).toContain(
            'Your CI/CD configuration syntax is invalid. Select the Validate tab for more details.',
          );
          expect(visualizationTab.querySelector('[data-testid="graph-container"]')).toBe(null);
        });
      });
    });

    describe('when the pipeline is validated', () => {
      beforeEach(async () => {
        await waitAndClick(() => findTab('Validate'));
        await waitAndClick(() => findButtonByText('Validate pipeline'));
      });

      it('reports that the simulation completed with errors', async () => {
        await waitFor(() => {
          expect(getText(document.body)).toContain('Pipeline simulation completed with errors');
        });
      });
    });

    describe('when the Full configuration tab is selected', () => {
      beforeEach(async () => {
        await waitAndClick(() => findTab('Full configuration'));
      });

      it('renders the merged configuration as view only', async () => {
        const mergedTab = await waitForElement(() => findTabPanel('merged-tab'));

        await waitFor(() => {
          expect(monacoEditor.getModels().some((model) => model.getValue().includes('job3'))).toBe(
            true,
          );
          expect(getText(mergedTab)).toContain('Full configuration is view only');
        });
      });
    });
  });
});
