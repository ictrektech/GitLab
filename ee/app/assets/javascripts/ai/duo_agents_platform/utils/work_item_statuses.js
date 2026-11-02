import { getStatuses } from 'ee/work_items/utils';
import { filterWorkItemTypesByIds, workItemStatusNameOptions } from './index';

/**
 * Lists the statuses of the selected work item types, or of every type when no type is selected.
 * Kept out of index.js, so that its many importers do not load the work item constants.
 */
export const workItemTypesStatusNameOptions = (workItemTypes, typeIds) =>
  workItemStatusNameOptions(getStatuses(filterWorkItemTypesByIds(workItemTypes, typeIds)));
