import { getIdFromGraphQLId } from '~/graphql_shared/utils';

export const isCreatedLinkedItem = ({ linkType }) => linkType === 'CREATED';

/**
 * Flattens the work items, merge requests, notes and pipelines linked to an
 * agent session into one list, in that order.
 */
export const buildLinkedItems = (details) => {
  const workItems = (details.workItemLinks?.nodes || [])
    .filter(({ workItem }) => workItem)
    .map(({ linkType, workItem }) => ({
      linkType,
      kind: 'workItem',
      icon: 'work-item-issue',
      reference: `#${workItem.iid}`,
      href: workItem.webPath,
    }));
  const mergeRequests = (details.mergeRequestLinks?.nodes || [])
    .filter(({ mergeRequest }) => mergeRequest)
    .map(({ linkType, mergeRequest }) => ({
      linkType,
      kind: 'mergeRequest',
      icon: 'merge-request',
      reference: `!${mergeRequest.iid}`,
      href: mergeRequest.webPath,
    }));
  // A note that triggered the session (an @mention) has the TRIGGERED link type.
  const notes = (details.noteLinks?.nodes || [])
    .filter(({ note }) => note)
    .map(({ linkType, note }) => ({
      linkType,
      kind: 'note',
      icon: 'comment',
      reference: note.discussion?.noteable?.reference,
      href: note.url,
    }));
  const pipelines = (details.pipelineLinks?.nodes || [])
    .filter(({ pipeline }) => pipeline)
    .map(({ linkType, pipeline }) => ({
      linkType,
      kind: 'pipeline',
      icon: 'pipeline',
      reference: `#${getIdFromGraphQLId(pipeline.id)}`,
      href: pipeline.path,
    }));

  return [...workItems, ...mergeRequests, ...notes, ...pipelines];
};

/**
 * Picks up to two linked items to show: the item the session started from, then
 * the item it created, so the direction reads as a story. With several sources,
 * what the session produced stays visible over a second source.
 */
export const pickShownLinkedItems = (items) => {
  const source = items.find((item) => !isCreatedLinkedItem(item));
  const created = items.find(isCreatedLinkedItem);

  return source && created ? [source, created] : items.slice(0, 2);
};
