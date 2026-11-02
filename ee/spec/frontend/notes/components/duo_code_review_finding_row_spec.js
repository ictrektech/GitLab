import { GlBadge, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoCodeReviewFindingRow from 'ee/notes/components/duo_code_review_finding_row.vue';

describe('DuoCodeReviewFindingRow', () => {
  let wrapper;

  const createComponent = (finding = {}) => {
    wrapper = shallowMountExtended(DuoCodeReviewFindingRow, {
      propsData: {
        finding: { severity: 'major', category: 'logic-error', depth: 'standard', ...finding },
      },
      stubs: { GlSprintf },
    });
  };

  const findRow = () => wrapper.findByTestId('duo-code-review-finding-row');
  const findLabel = () => wrapper.findByTestId('duo-code-review-finding-label');
  const findDepthBadge = () => wrapper.findComponent(GlBadge);

  it.each`
    severity      | text                               | classes
    ${'critical'} | ${'Critical finding: Logic error'} | ${['gl-bg-feedback-danger', 'gl-text-feedback-danger']}
    ${'major'}    | ${'Major finding: Logic error'}    | ${['gl-bg-feedback-warning', 'gl-text-feedback-warning']}
    ${'minor'}    | ${'Minor finding: Logic error'}    | ${['gl-bg-subtle', 'gl-text-default']}
  `('renders a $severity finding', ({ severity, text, classes }) => {
    createComponent({ severity });

    expect(findLabel().text()).toBe(text);
    expect(findRow().classes()).toEqual(expect.arrayContaining(classes));
  });

  it('humanizes underscored categories', () => {
    createComponent({ category: 'missing_test' });

    expect(findLabel().text()).toBe('Major finding: Missing test');
  });

  it.each`
    depth         | label
    ${'standard'} | ${'Standard review'}
    ${'deep'}     | ${'Deep review'}
  `('shows the $depth review depth', ({ depth, label }) => {
    createComponent({ depth });

    expect(findDepthBadge().text()).toBe(label);
  });

  it('does not render an unknown severity', () => {
    createComponent({ severity: 'info' });

    expect(findRow().exists()).toBe(false);
  });
});
