import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import updateWorkItemMutation from '~/work_items/graphql/update_work_item.mutation.graphql';
import { updateWorkItemField } from '~/work_items/table/utils';
import { updateWorkItemMutationResponse } from 'ee_else_ce_jest/work_items/mock_data';

Vue.use(VueApollo);

describe('work items table utils', () => {
  describe('updateWorkItemField', () => {
    const id = 'gid://gitlab/WorkItem/1';

    const update = (mutationHandler, options = {}) => {
      const { defaultClient } = createMockApollo([[updateWorkItemMutation, mutationHandler]]);

      return updateWorkItemField(defaultClient, { id, input: { title: 'New title' }, ...options });
    };

    it('sends the input for the work item', async () => {
      const mutationHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponse);

      await update(mutationHandler);

      expect(mutationHandler).toHaveBeenCalledWith({
        input: { id, title: 'New title' },
        useWorkItemFeatures: false,
      });
    });

    it('sends useWorkItemFeatures when the feature field is enabled', async () => {
      const mutationHandler = jest.fn().mockResolvedValue({
        data: { workItemUpdate: { workItem: null, errors: [] } },
      });

      await update(mutationHandler, { useWorkItemFeatures: true });

      expect(mutationHandler).toHaveBeenCalledWith(
        expect.objectContaining({ useWorkItemFeatures: true }),
      );
    });

    it('resolves to the updated work item', async () => {
      const mutationHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponse);

      await expect(update(mutationHandler)).resolves.toMatchObject({
        id: updateWorkItemMutationResponse.data.workItemUpdate.workItem.id,
      });
    });

    it('rejects with the field and errors when the server returns errors', async () => {
      const mutationHandler = jest.fn().mockResolvedValue({
        data: { workItemUpdate: { workItem: null, errors: ['Title is too long'] } },
      });

      await expect(update(mutationHandler)).rejects.toThrow(
        'Work item title update failed on table view: Title is too long',
      );
    });

    it('rejects when the request fails', async () => {
      const mutationHandler = jest.fn().mockRejectedValue(new Error('Network error'));

      await expect(update(mutationHandler)).rejects.toThrow('Network error');
    });
  });
});
