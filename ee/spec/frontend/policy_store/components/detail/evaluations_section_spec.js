import { shallowMount } from '@vue/test-utils';
import { GlLink, GlLoadingIcon } from '@gitlab/ui';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import EvaluationsSection from 'ee/policy_store/components/detail/evaluations_section.vue';
import SummarySection from 'ee/policy_store/components/detail/summary_section.vue';
import { toEvaluations } from 'ee/policy_store/evaluations';
import { mockGraphqlEvaluation } from '../../mock_data';

describe('PolicyEvaluationsSection', () => {
  let wrapper;

  const rows = (...overrides) =>
    toEvaluations({ nodes: overrides.map((override) => mockGraphqlEvaluation(override)) });

  const createComponent = (props = {}) => {
    wrapper = shallowMount(EvaluationsSection, {
      propsData: props,
      stubs: {
        SummarySection: {
          ...SummarySection,
          template: '<section><slot></slot></section>',
        },
      },
    });
  };

  const findByTestId = (id) => wrapper.find(`[data-testid="${id}"]`);
  const findComponentByTestId = (id) => wrapper.findComponent(`[data-testid="${id}"]`);
  const findAllByTestId = (id) => wrapper.findAll(`[data-testid="${id}"]`);

  it('shows a loading icon instead of the list while the evaluations load', () => {
    createComponent({ loading: true, evaluations: null });

    expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    expect(findByTestId('evaluations-unreadable').exists()).toBe(false);
  });

  // The two null-ish states say different things, and conflating them would tell a
  // viewer who cannot read the evaluations that the policy has never run.
  it('says the evaluations could not be loaded when there are none to read', () => {
    createComponent({ evaluations: null });

    expect(findByTestId('evaluations-unreadable').text()).toBe(
      'The evaluations of this policy could not be loaded.',
    );
  });

  it('says the policy has not run yet when the history is empty', () => {
    createComponent({ evaluations: [] });

    expect(findByTestId('evaluations-empty').text()).toBe(
      'This policy has not been evaluated yet.',
    );
  });

  describe('with evaluations', () => {
    beforeEach(() => {
      createComponent({
        evaluations: rows({}, { id: 'gid://gitlab/Govern::PolicyEvaluation/12' }),
      });
    });

    it('renders one entry per evaluation', () => {
      expect(findAllByTestId('evaluation-entry')).toHaveLength(2);
      expect(findByTestId('evaluations-empty').exists()).toBe(false);
    });

    it('names the trigger rather than its wire id', () => {
      expect(findByTestId('evaluation-trigger').text()).toBe('Project settings change requested');
    });

    it('badges the verdict and the mode', () => {
      const verdict = findComponentByTestId('evaluation-verdict');
      const mode = findComponentByTestId('evaluation-mode');

      expect([verdict.text(), mode.text()]).toEqual(['Denied', 'Enforce']);
      expect([verdict.props('variant'), mode.props('variant')]).toEqual(['danger', 'danger']);
    });

    it('links the project the evaluation ran for', () => {
      const link = wrapper.findComponent(GlLink);

      expect(link.text()).toBe('Flight / Dashboard');
      expect(link.attributes('href')).toBe('/flightjs/dashboard');
    });

    it('shows when the evaluation ran', () => {
      expect(wrapper.findComponent(TimeAgoTooltip).props('time')).toBe('2026-10-20T09:00:00Z');
    });

    it('shows the violation details verbatim', () => {
      expect(findByTestId('evaluation-violation').text()).toBe(
        JSON.stringify({ setting: 'visibility', expected: 'private', actual: 'public' }, null, 2),
      );
    });
  });

  it('says so when the evaluation was not scoped to a project', () => {
    createComponent({ evaluations: rows({ projectId: null, project: null }) });

    expect(findByTestId('evaluation-project').text()).toBe('No project');
    expect(wrapper.findComponent(GlLink).exists()).toBe(false);
  });

  // Saying "No project" here would tell an auditor the policy ran org-wide when it
  // in fact ran against one project they are not allowed to see.
  it('distinguishes a project the viewer cannot see from no project at all', () => {
    createComponent({ evaluations: rows({ project: null }) });

    expect(findByTestId('evaluation-project').text()).toBe('A project you do not have access to');
    expect(wrapper.findComponent(GlLink).exists()).toBe(false);
  });

  it('renders no violation block for an evaluation that produced none', () => {
    createComponent({ evaluations: rows({ violations: [] }) });

    expect(findAllByTestId('evaluation-violation')).toHaveLength(0);
  });

  // Every violation block is its own region, so a screen reader announces the labels
  // one after another. A policy usually fires on a single trigger, so naming only the
  // trigger would leave a whole page of identically named regions.
  describe('violation labels', () => {
    const labels = () =>
      findAllByTestId('evaluation-violation').wrappers.map((w) => w.attributes('aria-label'));

    it('stays distinct when every evaluation shares a trigger', () => {
      createComponent({
        evaluations: rows({}, { id: 'gid://gitlab/Govern::PolicyEvaluation/12' }),
      });

      expect(labels()).toEqual([
        'Violation 1 of evaluation 1, Project settings change requested',
        'Violation 1 of evaluation 2, Project settings change requested',
      ]);
    });

    it('numbers the violations within an evaluation', () => {
      createComponent({
        evaluations: rows({
          violations: [
            { id: 'gid://gitlab/Govern::PolicyViolation/3', details: {} },
            { id: 'gid://gitlab/Govern::PolicyViolation/4', details: {} },
          ],
        }),
      });

      expect(labels()).toEqual([
        'Violation 1 of evaluation 1, Project settings change requested',
        'Violation 2 of evaluation 1, Project settings change requested',
      ]);
    });

    it('names the trigger each violation belongs to', () => {
      createComponent({
        evaluations: rows({
          triggerType: 'PROJECT_SCHEDULED_SETTINGS_DRIFT_CHECK',
        }),
      });

      expect(labels()).toEqual(['Violation 1 of evaluation 1, Daily settings check']);
    });
  });

  it('renders an empty object for a violation the engine recorded without details', () => {
    createComponent({
      evaluations: rows({
        violations: [{ id: 'gid://gitlab/Govern::PolicyViolation/9', details: null }],
      }),
    });

    expect(findByTestId('evaluation-violation').text()).toBe('{}');
  });
});
