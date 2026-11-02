import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { NAMESPACE_TYPES } from 'ee/security_orchestration/constants';
import { APPROVAL_POLICY_TYPE } from 'ee/security_orchestration/components/constants';
import { getText, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import updatePolicy from '../fixture_variants/update_policy';
import { SYNTHETIC_SAVE_ERROR, SYNTHETIC_SECONDARY_SAVE_ERROR } from '../test_constants';
import { expectNoMergeRequestOpened, mountPolicyEditor } from '../test_setup';

const findSaveButton = () => document.querySelector('[data-testid="save-policy"]');
const findErrorAlert = () => document.querySelector('[data-testid="error-alert"]');
const findScopeSelector = () => document.querySelector('[data-testid="project-scope-type"]');
const findErrorListItems = () =>
  [...findErrorAlert().querySelectorAll('li')].map((item) => getText(item));
// An error the backend blames on `actions` renders on the action, not in the alert.
const findActionAlert = () => document.querySelector('[data-testid="action-0"] .gl-alert');

// Synthetic messages, so this cannot be mistaken for coverage of the backend's wording.
describe('Security policy editor save failure', () => {
  // The group editor mounts a different tree: `scope_section.vue` turns its selector on.
  describe.each`
    namespaceType              | hasScopeSelector
    ${NAMESPACE_TYPES.PROJECT} | ${false}
    ${NAMESPACE_TYPES.GROUP}   | ${true}
  `('at $namespaceType level', ({ namespaceType, hasScopeSelector }) => {
    it('renders every message the save mutation returns', async () => {
      setQueryVariant(updatePolicy).error();

      mountPolicyEditor({ namespaceType });

      const saveButton = await waitForElement(findSaveButton);
      // Pins edit mode, so a regression cannot silently test the create flow instead.
      expect(getText(saveButton)).toBe('Update via merge request');
      // Proves the right tree mounted: at project level the selector needs several projects.
      expect(findScopeSelector() !== null).toBe(hasScopeSelector);
      // Absent before the click, so the alert below belongs to the failed save. A
      // point-in-time read is enough: the click runs on this same tick, so nothing can
      // render in between.
      expect(findErrorAlert()).toBe(null);

      saveButton.click();

      const alert = await waitForElement(findErrorAlert);

      // Equality keeps the two messages apart, so neither satisfies the other's check.
      expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
      expect(findErrorListItems()).toEqual([SYNTHETIC_SECONDARY_SAVE_ERROR]);

      expectNoMergeRequestOpened();
    });
  });

  // Rule mode has its own error branch, keyed on `validationErrors`, and only the approval
  // editor saves in rule mode. The two cases differ only in the field, the discriminator.
  describe('when a merge request approval policy save returns validation errors', () => {
    const mountApprovalEditor = () => mountPolicyEditor({ policyType: APPROVAL_POLICY_TYPE });

    it('surfaces every message when a validation error names a field other than the actions', async () => {
      setQueryVariant(updatePolicy).validationError();

      mountApprovalEditor();

      const saveButton = await waitForElement(findSaveButton);
      saveButton.click();

      const alert = await waitForElement(findErrorAlert);

      expect(getText(alert)).toContain(SYNTHETIC_SAVE_ERROR);
      expect(findErrorListItems()).toEqual([SYNTHETIC_SECONDARY_SAVE_ERROR]);

      expectNoMergeRequestOpened();
    });

    it('routes the message to the action instead of the alert when the only validation error is on the actions', async () => {
      setQueryVariant(updatePolicy).actionValidationError();

      mountApprovalEditor();

      const saveButton = await waitForElement(findSaveButton);
      saveButton.click();

      // Waiting on the action's own alert is what makes the absence below an assertion.
      const actionAlert = await waitForElement(findActionAlert);

      expect(getText(actionAlert)).toContain(SYNTHETIC_SAVE_ERROR);
      expect(findErrorAlert()).toBe(null);

      expectNoMergeRequestOpened();
    });
  });
});
