import updateFixture from 'test_fixtures/graphql/ci/pipeline_triggers/integration/update_pipeline_trigger.mutation.graphql.json';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  getText,
  waitAndClick,
  waitForAssertion,
  waitForElement,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  MASKED_TOKEN,
  editTriggerDescription,
  findClipboardButton,
  findEditButton,
  findInvalidBadge,
  findOwnerLink,
  findRevealButton,
  findRevokeButton,
  findRowByDescription,
  findRows,
  findTokenCell,
  invalidTrigger,
  mountTriggersList,
  notOwnedTrigger,
  ownedTrigger,
  triggers,
} from './test_setup';

const { id: updatedTriggerId, description: UPDATED_DESCRIPTION } =
  updateFixture.data.pipelineTriggerUpdate.pipelineTrigger;
const REVOKE_CONFIRMATION =
  'By revoking a trigger token you will break any processes making use of it. Are you sure?';

const findOwnedRow = () => findRowByDescription(ownedTrigger.description);
const findNotOwnedRow = () => findRowByDescription(notOwnedTrigger.description);
const findInvalidRow = () => findRowByDescription(invalidTrigger.description);

describe('Pipeline trigger tokens settings', () => {
  beforeEach(async () => {
    mountTriggersList();
    await waitForElement(findOwnedRow);
  });

  it('lists every trigger with its token masked', () => {
    expect(findRows()).toHaveLength(triggers.length);

    findRows().forEach((row) => {
      expect(getText(findTokenCell(row))).toContain(MASKED_TOKEN);
    });
  });

  it('flags a trigger whose owner cannot access the project as invalid', () => {
    const row = findInvalidRow();

    expect(getText(findInvalidBadge(row))).toBe('invalid');
    expect(findInvalidBadge(findOwnedRow())).toBe(null);
  });

  // This test only covers the frontend's contract with rails-ujs for the revoke action.
  // The server side is covered by the 'trigger "Revoke" workflow' examples in
  // spec/features/triggers_spec.rb.
  it('offers to revoke a trigger after confirmation', () => {
    const button = findRevokeButton(findOwnedRow());

    expect(button.getAttribute('href')).toBe(ownedTrigger.projectTriggerPath);
    expect(button.dataset.method).toBe('delete');
    expect(button.dataset.confirm).toBe(REVOKE_CONFIRMATION);
  });

  describe('when values are revealed', () => {
    beforeEach(async () => {
      await waitAndClick(findRevealButton);
      await waitForAssertion(() => {
        expect(getText(findTokenCell(findOwnedRow()))).toContain(ownedTrigger.token);
      });
    });

    it('relabels the button to hide the values again', () => {
      // The list writes the label through `innerText`, which jsdom stores without
      // reflecting it into `textContent`, so the same property is read back here.
      expect(findRevealButton().innerText).toBe('Hide values');
    });

    it('shows the full token, a copy button and the edit action for the owned trigger', () => {
      const row = findOwnedRow();

      expect(getText(findTokenCell(row))).not.toContain(MASKED_TOKEN);
      expect(findClipboardButton(row)).not.toBe(null);
      expect(findEditButton(row)).not.toBe(null);
      expect(findOwnerLink(row).getAttribute('title')).toBe(ownedTrigger.owner.name);
      expect(findOwnerLink(row).getAttribute('href')).toBe(ownedTrigger.owner.path);
    });

    it("shows only the short token, without a copy button, for another user's trigger", () => {
      const row = findNotOwnedRow();

      expect(getText(findTokenCell(row))).toContain(notOwnedTrigger.token);
      expect(findClipboardButton(row)).toBe(null);
      expect(findOwnerLink(row).getAttribute('title')).toBe(notOwnedTrigger.owner.name);
    });

    it('masks the tokens again on a second click', async () => {
      await waitAndClick(findRevealButton);

      await waitForAssertion(() => {
        expect(getText(findTokenCell(findOwnedRow()))).toContain(MASKED_TOKEN);
      });
    });
  });

  describe('when editing a trigger description', () => {
    beforeEach(async () => {
      await editTriggerDescription(findOwnedRow(), UPDATED_DESCRIPTION);
      await waitForElement(() => findRowByDescription(UPDATED_DESCRIPTION));
    });

    it('sends the new description for the edited trigger', () => {
      expect(lastRequestVariables('updatePipelineTrigger')).toEqual({
        id: updatedTriggerId,
        description: UPDATED_DESCRIPTION,
      });
    });

    it('updates the row in place', () => {
      expect(findRowByDescription(ownedTrigger.description)).toBe(null);
      expect(findRows()).toHaveLength(triggers.length);
    });
  });
});
