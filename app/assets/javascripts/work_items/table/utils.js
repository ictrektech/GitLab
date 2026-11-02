import updateWorkItemMutation from '../graphql/update_work_item.mutation.graphql';

/**
 * Saves a field edited in a table cell. `input` holds the fields to change, as in
 * `WorkItemUpdateInput`, without the id.
 *
 * Rejects both when the request fails and when the server returns errors, so cells handle
 * every failure in one place.
 */
export const updateWorkItemField = async (apollo, { id, input, useWorkItemFeatures = false }) => {
  const { data } = await apollo.mutate({
    mutation: updateWorkItemMutation,
    variables: {
      input: { id, ...input },
      useWorkItemFeatures: Boolean(useWorkItemFeatures),
    },
  });

  const errors = data?.workItemUpdate?.errors;
  if (errors?.length) {
    const fields = Object.keys(input).join(', ');
    throw new Error(`Work item ${fields} update failed on table view: ${errors.join(', ')}`);
  }

  return data.workItemUpdate.workItem;
};
