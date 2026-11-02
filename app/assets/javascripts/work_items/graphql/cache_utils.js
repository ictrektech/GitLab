import { produce } from 'immer';
import { camelCase, isEqual } from 'lodash-es';
import { TYPENAME_USER } from '~/graphql_shared/constants';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { getBaseURL } from '~/lib/utils/url_utility';
import { getDraft, clearDraft } from '~/lib/utils/autosave';
import {
  newWorkItemOptimisticUserPermissions,
  WIDGET_TYPE_ASSIGNEES,
  WIDGET_TYPE_COLOR,
  WIDGET_TYPE_HIERARCHY,
  WIDGET_TYPE_PARTICIPANTS,
  WIDGET_TYPE_PROGRESS,
  WIDGET_TYPE_START_AND_DUE_DATE,
  WIDGET_TYPE_TIME_TRACKING,
  WIDGET_TYPE_LABELS,
  WIDGET_TYPE_WEIGHT,
  WIDGET_TYPE_MILESTONE,
  WIDGET_TYPE_ITERATION,
  WIDGET_TYPE_HEALTH_STATUS,
  WIDGET_TYPE_DESCRIPTION,
  WIDGET_TYPE_AWARD_EMOJI,
  WIDGET_TYPE_NOTES,
  WIDGET_TYPE_CRM_CONTACTS,
  NEW_WORK_ITEM_IID,
  WIDGET_TYPE_LINKED_ITEMS,
  WIDGET_TYPE_LINKED_RESOURCES,
  STATE_CLOSED,
  WIDGET_TYPE_CUSTOM_FIELDS,
  WIDGET_TYPE_REQUESTER,
  WIDGET_TYPE_STATUS,
  WIDGET_TYPE_CURRENT_USER_TODOS,
  WIDGET_TYPE_DEVELOPMENT,
  WIDGET_TYPE_ERROR_TRACKING,
  WIDGET_TYPE_NOTIFICATIONS,
  WIDGET_TYPE_WORKPLAN,
  WIDGET_TYPE_DECISION_LOG,
} from 'ee_else_ce/work_items/constants';
import {
  findHierarchyWidget,
  findHierarchyWidgetChildren,
  findNotesWidget,
  getNewWorkItemAutoSaveKey,
  getNewWorkItemWidgetsAutoSaveKey,
  isNotesWidget,
  newWorkItemFullPath,
  newWorkItemId,
  getWorkItemFeatures,
} from '../utils';
import workItemByIidQuery from './work_item_by_iid.query.graphql';
import workItemCrmContactsQuery from './work_item_crm_contacts.query.graphql';
import workItemByIdQuery from './work_item_by_id.query.graphql';
import getWorkItemTreeQuery from './work_item_tree.query.graphql';

const getNotesWidgetFromSourceData = (draftData) =>
  draftData?.namespace?.workItem?.features
    ? draftData?.namespace?.workItem?.features.notes
    : findNotesWidget(draftData?.namespace?.workItem);

const updateNotesWidgetDataInDraftData = (draftData, notesWidget) => {
  if (draftData?.namespace?.workItem?.features) {
    draftData.namespace.workItem.features.notes = notesWidget;
  } else {
    const noteWidgetIndex = draftData.namespace.workItem.widgets.findIndex((widget) =>
      isNotesWidget(widget),
    );

    draftData.namespace.workItem.widgets[noteWidgetIndex] = notesWidget;
  }
};

const workItemFeaturesEnabled = () => Boolean(window.gon?.features?.workItemFeaturesField);

/**
 * Work Item note create subscription update query callback
 *
 * @param currentNotes
 * @param newNote
 */
export const updateCacheAfterCreatingNote = (currentNotes, newNote, { prepend = false } = {}) => {
  if (!newNote) {
    return currentNotes;
  }

  return produce(currentNotes, (draftData) => {
    const notesWidget = getNotesWidgetFromSourceData(draftData);

    // Early return if notesWidget or discussions is not available
    if (!notesWidget || !notesWidget.discussions) {
      return;
    }

    const discussion = notesWidget.discussions.nodes.find((d) => d.id === newNote.discussion.id);

    // handle the case where discussion already exists - we don't need to do anything, update will happen automatically
    if (discussion) {
      return;
    }

    if (prepend) {
      notesWidget.discussions.nodes.unshift(newNote.discussion);
    } else {
      notesWidget.discussions.nodes.push(newNote.discussion);
    }

    updateNotesWidgetDataInDraftData(draftData, notesWidget);
  });
};

/**
 * Work Item note delete subscription update query callback
 *
 * @param currentNotes
 * @param subscriptionData
 */
export const updateCacheAfterDeletingNote = (currentNotes, subscriptionData) => {
  if (!subscriptionData.data?.workItemNoteDeleted) {
    return currentNotes;
  }
  const deletedNote = subscriptionData.data.workItemNoteDeleted;
  const { id, discussionId, lastDiscussionNote } = deletedNote;

  return produce(currentNotes, (draftData) => {
    const notesWidget = getNotesWidgetFromSourceData(draftData);

    // Early return if notesWidget or discussions is not available
    if (!notesWidget || !notesWidget.discussions) {
      return;
    }

    const discussionIndex = notesWidget.discussions.nodes.findIndex(
      (discussion) => discussion.id === discussionId,
    );

    if (discussionIndex === -1) {
      return;
    }

    if (lastDiscussionNote) {
      notesWidget.discussions.nodes.splice(discussionIndex, 1);
    } else {
      const deletedThreadDiscussion = notesWidget.discussions.nodes[discussionIndex];
      const deletedThreadIndex = deletedThreadDiscussion.notes.nodes.findIndex(
        (note) => note.id === id,
      );
      deletedThreadDiscussion.notes.nodes.splice(deletedThreadIndex, 1);
      notesWidget.discussions.nodes[discussionIndex] = deletedThreadDiscussion;
    }

    updateNotesWidgetDataInDraftData(draftData, notesWidget);
  });
};

function updateNoteAwardEmojiCache(currentNotes, note, callback) {
  if (!note.awardEmoji) {
    return currentNotes;
  }
  const { awardEmoji } = note;

  return produce(currentNotes, (draftData) => {
    const notesWidget = getNotesWidgetFromSourceData(draftData);

    // Early return if notesWidget or discussions is not available
    if (!notesWidget || !notesWidget.discussions) {
      return;
    }

    notesWidget.discussions.nodes.forEach((discussion) => {
      discussion.notes.nodes.forEach((n) => {
        if (n.id === note.id) {
          callback(n, awardEmoji);
        }
      });
    });

    updateNotesWidgetDataInDraftData(draftData, notesWidget);
  });
}

export const updateCacheAfterAddingAwardEmojiToNote = (currentNotes, note) => {
  return updateNoteAwardEmojiCache(currentNotes, note, (n, awardEmoji) => {
    if (
      !n.awardEmoji.nodes.some(
        (emoji) => emoji.name === awardEmoji.name && emoji.user.id === awardEmoji.user.id,
      )
    ) {
      n.awardEmoji.nodes.push(awardEmoji);
    }
  });
};

export const updateCacheAfterRemovingAwardEmojiFromNote = (currentNotes, note) => {
  return updateNoteAwardEmojiCache(currentNotes, note, (n, awardEmoji) => {
    // eslint-disable-next-line no-param-reassign
    n.awardEmoji.nodes = n.awardEmoji.nodes.filter((emoji) => {
      return emoji.name !== awardEmoji.name || emoji.user.id !== awardEmoji.user.id;
    });
  });
};

export const addHierarchyChild = ({ cache, id, workItem, atIndex = null }) => {
  const queryArgs = {
    query: getWorkItemTreeQuery,
    variables: {
      id,
      useWorkItemFeatures: workItemFeaturesEnabled(),
    },
  };
  const sourceData = cache.readQuery(queryArgs);

  if (!sourceData) {
    return;
  }

  cache.writeQuery({
    ...queryArgs,
    data: produce(sourceData, (draftState) => {
      const widget = findHierarchyWidget(draftState?.workItem);
      widget.hasChildren = true;
      const children = findHierarchyWidgetChildren(draftState?.workItem) || [];
      const existingChild = children.find((child) => child.id === workItem?.id);
      if (!existingChild) {
        if (atIndex !== null) {
          children.splice(atIndex, 0, workItem);
        } else {
          children.unshift(workItem);
        }
        widget.hasChildren = children?.length > 0;
        widget.count = children?.length || 0;
      }
    }),
  });
};

export const addHierarchyChildren = ({ cache, id, newChildren }) => {
  const cacheId = cache.identify({ __typename: 'WorkItem', id });
  if (!cacheId) return;

  const mergeChildrenIntoHierarchy = (hierarchy) => {
    const existingChildren = hierarchy.children || {};
    const existingNodes = existingChildren.nodes || [];
    const existingIds = existingNodes.map((n) => n.id);

    // Filter duplicates
    const uniqueNewChildren = newChildren.filter((child) => !existingIds.includes(child.id));

    // Separate open/closed
    const openChildren = uniqueNewChildren.filter((child) => child.state !== STATE_CLOSED);
    const closedChildren = uniqueNewChildren.filter((child) => child.state === STATE_CLOSED);

    // Merge order: open first → existing → closed
    const mergedNodes = [...openChildren, ...existingNodes, ...closedChildren];

    return {
      ...hierarchy,
      children: {
        ...existingChildren,
        nodes: mergedNodes,
      },
      count: mergedNodes.length,
      hasChildren: mergedNodes.length > 0,
    };
  };

  cache.modify({
    id: cacheId,
    fields: {
      features(existing) {
        if (!existing?.hierarchy) return existing;
        return { ...existing, hierarchy: mergeChildrenIntoHierarchy(existing.hierarchy) };
      },
      widgets(existing = []) {
        return existing.map((widget) => {
          if (widget.type !== WIDGET_TYPE_HIERARCHY) return widget;
          return mergeChildrenIntoHierarchy(widget);
        });
      },
    },
  });
};

export const removeHierarchyChild = ({ cache, id, workItem }) => {
  const queryArgs = {
    query: getWorkItemTreeQuery,
    variables: {
      id,
      useWorkItemFeatures: workItemFeaturesEnabled(),
    },
  };
  const sourceData = cache.readQuery(queryArgs);

  if (!sourceData) {
    return;
  }

  cache.writeQuery({
    ...queryArgs,
    data: produce(sourceData, (draftState) => {
      const widget = findHierarchyWidget(draftState?.workItem);
      const children = findHierarchyWidgetChildren(draftState?.workItem);
      const index = children.findIndex((child) => child.id === workItem.id);
      if (index >= 0) children.splice(index, 1);
      widget.hasChildren = children?.length > 0;
      widget.count = children?.length || 0;
    }),
  });
};

export const updateParent = ({ cache, fullPath, iid, workItem }) => {
  const queryArgs = {
    query: workItemByIidQuery,
    variables: {
      fullPath,
      iid,
      useWorkItemFeatures: workItemFeaturesEnabled(),
    },
  };
  const sourceData = cache.readQuery(queryArgs);

  if (!sourceData) {
    return;
  }

  cache.writeQuery({
    ...queryArgs,
    data: produce(sourceData, (draftState) => {
      const children = findHierarchyWidgetChildren(draftState.namespace?.workItem);
      const index = children.findIndex((child) => child.id === workItem.id);
      if (index >= 0) children.splice(index, 1);
    }),
  });
};

export const getNewWorkItemSharedCache = ({
  workItemAttributesWrapperOrder = [],
  fullPath,
  context,
  workItemType,
  relatedItemId,
  isValidWorkItemDescription,
  workItemDescription = '',
  widgetDefinitions,
}) => {
  const widgetsAutosaveKey = getNewWorkItemWidgetsAutoSaveKey({ fullPath, context, relatedItemId });
  const fullDraftAutosaveKey = getNewWorkItemAutoSaveKey({
    fullPath,
    context,
    workItemType,
    relatedItemId,
  });

  const workItemTypeSpecificFeatures =
    getWorkItemFeatures(JSON.parse(getDraft(fullDraftAutosaveKey))) || {};
  const draftWorkItemCache = JSON.parse(getDraft(widgetsAutosaveKey)) || {};

  const draftTitle = draftWorkItemCache.TITLE || '';
  const draftDescription = draftWorkItemCache[WIDGET_TYPE_DESCRIPTION]?.description || null;

  const widgetDefinitionsHash = widgetDefinitions.reduce((acc, widget) => {
    return { ...acc, [widget.type]: { ...widget } };
  }, {});

  const startAndDueDateWidgetDefinitionHash = widgetDefinitionsHash[WIDGET_TYPE_START_AND_DUE_DATE];

  const features = {
    description: {
      __typename: 'WorkItemWidgetDescription',
      type: WIDGET_TYPE_DESCRIPTION,
      description: isValidWorkItemDescription ? workItemDescription : draftDescription,
      descriptionHtml: '',
      lastEditedAt: null,
      lastEditedBy: null,
      taskCompletionStatus: null,
    },
    assignees: {
      ...widgetDefinitionsHash[WIDGET_TYPE_ASSIGNEES],
      type: WIDGET_TYPE_ASSIGNEES,
      allowsMultipleAssignees:
        widgetDefinitionsHash[WIDGET_TYPE_ASSIGNEES]?.allowsMultipleAssignees ?? false,
      canInviteMembers: widgetDefinitionsHash[WIDGET_TYPE_ASSIGNEES]?.canInviteMembers ?? false,
      assignees: {
        nodes: draftWorkItemCache[WIDGET_TYPE_ASSIGNEES]?.assignees?.nodes || [],
        __typename: 'UserCoreConnection',
      },
      __typename: 'WorkItemWidgetAssignees',
    },
    labels: {
      ...widgetDefinitionsHash[WIDGET_TYPE_LABELS],
      type: WIDGET_TYPE_LABELS,
      allowsScopedLabels: widgetDefinitionsHash[WIDGET_TYPE_LABELS]?.allowsScopedLabels ?? false,
      labels: {
        nodes: draftWorkItemCache[WIDGET_TYPE_LABELS]?.labels?.nodes || [],
        __typename: 'LabelConnection',
      },
      __typename: 'WorkItemWidgetLabels',
    },
    milestone: {
      ...widgetDefinitionsHash[WIDGET_TYPE_MILESTONE],
      type: WIDGET_TYPE_MILESTONE,
      milestone: draftWorkItemCache[WIDGET_TYPE_MILESTONE]?.milestone || null,
      __typename: 'WorkItemWidgetMilestone',
    },
    iteration: {
      ...widgetDefinitionsHash[WIDGET_TYPE_ITERATION],
      type: WIDGET_TYPE_ITERATION,
      iteration: draftWorkItemCache[WIDGET_TYPE_ITERATION]?.iteration || null,
      __typename: 'WorkItemWidgetIteration',
    },
    weight: {
      ...widgetDefinitionsHash[WIDGET_TYPE_WEIGHT],
      type: WIDGET_TYPE_WEIGHT,
      weight: draftWorkItemCache[WIDGET_TYPE_WEIGHT]?.weight || null,
      rolledUpWeight: null,
      rolledUpCompletedWeight: null,
      __typename: 'WorkItemWidgetWeight',
    },
    startAndDueDate: {
      ...startAndDueDateWidgetDefinitionHash,
      type: WIDGET_TYPE_START_AND_DUE_DATE,
      dueDate: startAndDueDateWidgetDefinitionHash?.dueDate || null,
      startDate: startAndDueDateWidgetDefinitionHash?.startDate || null,
      isFixed: startAndDueDateWidgetDefinitionHash?.isFixed || false,
      rollUp: false,
      __typename: 'WorkItemWidgetStartAndDueDate',
    },
    healthStatus: {
      ...widgetDefinitionsHash[WIDGET_TYPE_HEALTH_STATUS],
      type: WIDGET_TYPE_HEALTH_STATUS,
      healthStatus: draftWorkItemCache[WIDGET_TYPE_HEALTH_STATUS]?.healthStatus || null,
      rolledUpHealthStatus: null,
      __typename: 'WorkItemWidgetHealthStatus',
    },
    color: {
      ...widgetDefinitionsHash[WIDGET_TYPE_COLOR],
      type: WIDGET_TYPE_COLOR,
      color: draftWorkItemCache[WIDGET_TYPE_COLOR]?.color || '#1068bf',
      textColor: '#FFFFFF',
      __typename: 'WorkItemWidgetColor',
    },
    status: (() => {
      const statusWidgetDefinition = widgetDefinitionsHash[WIDGET_TYPE_STATUS];
      const { defaultOpenStatus, allowedStatuses } = statusWidgetDefinition || {};
      const cachedStatus = draftWorkItemCache[WIDGET_TYPE_STATUS]?.status;
      const isCachedStatusAllowed =
        cachedStatus && allowedStatuses?.some((s) => s.name === cachedStatus.name);
      return {
        ...statusWidgetDefinition,
        status: isCachedStatusAllowed ? cachedStatus : defaultOpenStatus || null,
        __typename: 'WorkItemWidgetStatus',
      };
    })(),
    hierarchy: {
      ...widgetDefinitionsHash[WIDGET_TYPE_HIERARCHY],
      type: WIDGET_TYPE_HIERARCHY,
      hasChildren: false,
      hasParent: false,
      parent: null,
      depthLimitReachedByType: [],
      rolledUpCountsByType: [],
      children: {
        nodes: [],
        __typename: 'WorkItemConnection',
      },
      __typename: 'WorkItemWidgetHierarchy',
    },
    timeTracking: {
      ...widgetDefinitionsHash[WIDGET_TYPE_TIME_TRACKING],
      type: WIDGET_TYPE_TIME_TRACKING,
      timeEstimate: 0,
      humanReadableAttributes: {
        timeEstimate: '',
      },
      timelogs: {
        nodes: [],
        __typename: 'WorkItemTimelogConnection',
      },
      totalTimeSpent: 0,
      __typename: 'WorkItemWidgetTimeTracking',
    },
    linkedItems: {
      ...widgetDefinitionsHash[WIDGET_TYPE_LINKED_ITEMS],
      type: WIDGET_TYPE_LINKED_ITEMS,
      blockingCount: 0,
      blockedByCount: 0,
      linkedItems: {
        nodes: [],
      },
      __typename: 'WorkItemWidgetLinkedItems',
    },
    crmContacts: {
      ...widgetDefinitionsHash[WIDGET_TYPE_CRM_CONTACTS],
      type: WIDGET_TYPE_CRM_CONTACTS,
      contactsAvailable: false,
      contacts: {
        nodes: draftWorkItemCache[WIDGET_TYPE_CRM_CONTACTS]?.contacts?.nodes || [],
        __typename: 'CustomerRelationsContactConnection',
      },
      __typename: 'WorkItemWidgetCrmContacts',
    },
    awardEmoji: {
      ...widgetDefinitionsHash[WIDGET_TYPE_AWARD_EMOJI],
      type: WIDGET_TYPE_AWARD_EMOJI,
      upvotes: 0,
      downvotes: 0,
      newCustomEmojiPath: '',
      awardEmoji: {
        nodes: [],
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: null,
          endCursor: null,
          __typename: 'PageInfo',
        },
        __typename: 'AwardEmojiConnection',
      },
      __typename: 'WorkItemWidgetAwardEmoji',
    },
    notes: {
      ...widgetDefinitionsHash[WIDGET_TYPE_NOTES],
      type: WIDGET_TYPE_NOTES,
      discussionLocked: false,
      __typename: 'WorkItemWidgetNotes',
    },
    participants: {
      ...widgetDefinitionsHash[WIDGET_TYPE_PARTICIPANTS],
      type: WIDGET_TYPE_PARTICIPANTS,
      participants: {
        count: 0,
        nodes: [],
        __typename: 'UserCoreConnection',
      },
      __typename: 'WorkItemWidgetParticipants',
    },
    linkedResources: {
      ...widgetDefinitionsHash[WIDGET_TYPE_LINKED_RESOURCES],
      type: WIDGET_TYPE_LINKED_RESOURCES,
      linkedResources: {
        nodes: [],
        __typename: 'WorkItemLinkedResourceConnection',
      },
      __typename: 'WorkItemWidgetLinkedResources',
    },
    development: {
      type: WIDGET_TYPE_DEVELOPMENT,
      __typename: 'WorkItemWidgetDevelopment',
      closingMergeRequests: {
        count: 0,
      },
    },
    designs: null,
    emailParticipants: null,
    currentUserTodos: {
      ...widgetDefinitionsHash[WIDGET_TYPE_CURRENT_USER_TODOS],
      type: WIDGET_TYPE_CURRENT_USER_TODOS,
      currentUserTodos: {
        nodes: [],
        __typename: 'TodoConnection',
      },
      __typename: 'WorkItemWidgetCurrentUserTodos',
    },
    errorTracking: {
      ...widgetDefinitionsHash[WIDGET_TYPE_ERROR_TRACKING],
      type: WIDGET_TYPE_ERROR_TRACKING,
      identifier: null,
      __typename: 'WorkItemWidgetErrorTracking',
    },
    notifications: {
      ...widgetDefinitionsHash[WIDGET_TYPE_NOTIFICATIONS],
      type: WIDGET_TYPE_NOTIFICATIONS,
      subscribed: false,
      __typename: 'WorkItemWidgetNotifications',
    },
    progress: {
      ...widgetDefinitionsHash[WIDGET_TYPE_PROGRESS],
      type: WIDGET_TYPE_PROGRESS,
      progress: draftWorkItemCache[WIDGET_TYPE_PROGRESS]?.progress ?? null,
      updatedAt: null,
      __typename: 'WorkItemWidgetProgress',
    },
    agentPlan: {
      ...widgetDefinitionsHash[WIDGET_TYPE_WORKPLAN],
      type: WIDGET_TYPE_WORKPLAN,
      aiPlanningEnabled: false,
      __typename: 'WorkItemWidgetAgentPlan',
    },
    decisionLog: {
      ...widgetDefinitionsHash[WIDGET_TYPE_DECISION_LOG],
      type: WIDGET_TYPE_DECISION_LOG,
      __typename: 'WorkItemWidgetDecisionLog',
    },
    customFields: {
      customFieldValues: [],
      __typename: 'WorkItemWidgetCustomFields',
    },
    requester: {
      ...widgetDefinitionsHash[WIDGET_TYPE_REQUESTER],
      type: WIDGET_TYPE_REQUESTER,
      email: null,
      __typename: 'WorkItemWidgetRequester',
    },
  };

  const cachedParent = draftWorkItemCache[WIDGET_TYPE_HIERARCHY]?.parent || null;
  const typeSpecificParent = workItemTypeSpecificFeatures[WIDGET_TYPE_HIERARCHY]?.parent || null;

  if (cachedParent) {
    const allowedParentTypes =
      widgetDefinitions.find((widget) => widget.type === WIDGET_TYPE_HIERARCHY)?.allowedParentTypes
        ?.nodes || [];

    features.hierarchy.parent = allowedParentTypes.some(
      (type) => type.id === cachedParent.workItemType.id,
    )
      ? cachedParent
      : typeSpecificParent;
  } else if (workItemTypeSpecificFeatures[WIDGET_TYPE_HIERARCHY]) {
    features.hierarchy.parent = typeSpecificParent;
  }

  if (widgetDefinitionsHash[WIDGET_TYPE_CUSTOM_FIELDS]) {
    const availableCustomFieldValues =
      widgetDefinitionsHash[WIDGET_TYPE_CUSTOM_FIELDS].customFieldValues;
    const cachedCustomFieldValues =
      draftWorkItemCache[WIDGET_TYPE_CUSTOM_FIELDS]?.customFieldValues;
    const typeSpecificCustomFieldValues =
      workItemTypeSpecificFeatures[WIDGET_TYPE_CUSTOM_FIELDS]?.customFieldValues || [];

    let customFieldValues = workItemTypeSpecificFeatures[WIDGET_TYPE_CUSTOM_FIELDS]
      ? typeSpecificCustomFieldValues
      : (widgetDefinitionsHash[WIDGET_TYPE_CUSTOM_FIELDS]?.customFieldValues ?? []);

    if (cachedCustomFieldValues && availableCustomFieldValues) {
      customFieldValues = availableCustomFieldValues.map((availableField) => {
        const cachedField = cachedCustomFieldValues.find(
          (cached) => cached.customField.id === availableField.customField.id,
        );
        const typeSpecificField = typeSpecificCustomFieldValues.find(
          (typeField) => typeField.customField.id === availableField.customField.id,
        );

        let fieldValue = {};
        if (cachedField?.selectedOptions || typeSpecificField?.selectedOptions) {
          fieldValue = {
            selectedOptions: cachedField?.selectedOptions || typeSpecificField?.selectedOptions,
          };
        } else if (cachedField?.value || typeSpecificField?.value) {
          fieldValue = { value: cachedField?.value || typeSpecificField?.value };
        }

        if (Object.keys(fieldValue).length) {
          return { ...availableField, ...fieldValue };
        }
        return { ...availableField };
      });
    }

    features.customFields = {
      ...widgetDefinitionsHash[WIDGET_TYPE_CUSTOM_FIELDS],
      customFieldValues,
      __typename: 'WorkItemWidgetCustomFields',
    };
  }

  // Attributes with no widget definition aren't supported by this type, and an empty feature
  // object is still truthy, so the create form would render them. Null instead of delete keeps the
  // `features` selection set satisfied. Same guard as `availableWidgets` on the legacy path.
  const unsupportedFeatures = workItemAttributesWrapperOrder
    .filter((widgetType) => !widgetDefinitionsHash[widgetType])
    .map((widgetType) => [camelCase(widgetType), null]);

  return {
    draftTitle,
    features: { ...features, ...Object.fromEntries(unsupportedFeatures) },
  };
};
export const setNewWorkItemCache = ({
  fullPath,
  context,
  widgetDefinitions,
  workItemType,
  workItemTypeId,
  workItemTypeIconName,
  relatedItemId,
  workItemTitle = '',
  workItemDescription = '',
  confidential = false,
  cache = apolloProvider.clients.defaultClient.cache,
}) => {
  const workItemAttributesWrapperOrder = [
    WIDGET_TYPE_STATUS,
    WIDGET_TYPE_ASSIGNEES,
    WIDGET_TYPE_REQUESTER,
    WIDGET_TYPE_LABELS,
    WIDGET_TYPE_WEIGHT,
    WIDGET_TYPE_MILESTONE,
    WIDGET_TYPE_ITERATION,
    WIDGET_TYPE_START_AND_DUE_DATE,
    WIDGET_TYPE_PROGRESS,
    WIDGET_TYPE_HEALTH_STATUS,
    WIDGET_TYPE_LINKED_ITEMS,
    WIDGET_TYPE_COLOR,
    WIDGET_TYPE_CUSTOM_FIELDS,
    WIDGET_TYPE_HIERARCHY,
    WIDGET_TYPE_TIME_TRACKING,
    WIDGET_TYPE_PARTICIPANTS,
    WIDGET_TYPE_CRM_CONTACTS,
  ];

  if (!widgetDefinitions) {
    return;
  }

  const currentUserId = convertToGraphQLId(TYPENAME_USER, gon?.current_user_id);
  const baseURL = getBaseURL();
  const isValidWorkItemTitle = workItemTitle.trim().length > 0;
  const isValidWorkItemDescription = workItemDescription.trim().length > 0;

  const autosaveKey = getNewWorkItemAutoSaveKey({ fullPath, context, workItemType, relatedItemId });
  const getStorageDraftString = getDraft(autosaveKey);

  const draftData = JSON.parse(getDraft(autosaveKey));

  const { draftTitle, features: sharedFeatures } = getNewWorkItemSharedCache({
    workItemAttributesWrapperOrder,
    widgetDefinitions,
    fullPath,
    context,
    workItemType,
    isValidWorkItemDescription,
    workItemDescription,
    relatedItemId,
  });
  const features = { __typename: 'WorkItemFeatures', ...sharedFeatures };

  const newWorkItemPath = newWorkItemFullPath(fullPath, workItemType);

  // get the widgets stored in draft data
  const draftDataWidgetTypes = Object.keys(draftData?.namespace?.workItem?.features || {});
  const freshWidgetTypes = Object.keys(features);

  // this is to fix errors when we are introducing a new widget and the cache always updates from the old widgets
  // Like if we we introduce a new widget , the user might always see the cached data until hits cancel
  const draftWidgetsAreSameAsCacheDigits = isEqual(
    draftDataWidgetTypes.sort(),
    freshWidgetTypes.sort(),
  );

  const isValidDraftData = Boolean(
    draftData?.namespace?.workItem && getStorageDraftString && draftWidgetsAreSameAsCacheDigits,
  );

  /** check in case of someone plays with the localstorage, we need to be sure */
  if (!isValidDraftData) {
    clearDraft(autosaveKey);
  }

  cache.writeQuery({
    query: workItemByIidQuery,
    variables: {
      fullPath: newWorkItemPath,
      iid: NEW_WORK_ITEM_IID,
      useWorkItemFeatures: true,
    },
    data: {
      namespace: {
        id: newWorkItemPath,
        workItem: {
          id: newWorkItemId(workItemType),
          iid: NEW_WORK_ITEM_IID,
          archived: false,
          externalAuthor: null,
          hidden: false,
          imported: false,
          title: isValidWorkItemTitle ? workItemTitle : draftTitle,
          titleHtml: null,
          state: 'OPEN',
          description: null,
          confidential,
          createdAt: null,
          updatedAt: null,
          closedAt: null,
          // eslint-disable-next-line @gitlab/no-hardcoded-urls -- placeholder webUrl for unsaved work item in Apollo cache, actual URL not known at this point
          webUrl: `${baseURL}/groups/gitlab-org/-/work_items/new`,
          reference: '',
          createNoteEmail: null,
          movedToWorkItemUrl: null,
          duplicatedToWorkItemUrl: null,
          promotedToEpicUrl: null,
          showPlanUpgradePromotion: false,
          userDiscussionsCount: 0,
          project: null,
          namespace: {
            id: newWorkItemPath,
            fullPath,
            name: newWorkItemPath,
            fullName: newWorkItemPath,
            webUrl: newWorkItemPath,
            __typename: 'Namespace',
          },
          author: {
            id: currentUserId,
            avatarUrl: gon?.current_user_avatar_url,
            username: gon?.current_username,
            name: gon?.current_user_fullname,
            webUrl: `${baseURL}/${gon?.current_username}`,
            webPath: `/${gon?.current_username}`,
            __typename: 'UserCore',
          },
          workItemType: {
            id: workItemTypeId || 'mock-work-item-type-id',
            name: workItemType,
            iconName: workItemTypeIconName,
            __typename: 'WorkItemType',
          },
          userPermissions: newWorkItemOptimisticUserPermissions,
          commentTemplatesPaths: [],
          features,
          __typename: 'WorkItem',
        },
        __typename: 'Namespace',
      },
    },
  });

  // CRM contacts live in their own query, so the draft has to be seeded there too. Without
  // this the widget would fire a request for an IID that doesn't exist yet.
  cache.writeQuery({
    query: workItemCrmContactsQuery,
    variables: {
      fullPath: newWorkItemPath,
      iid: NEW_WORK_ITEM_IID,
      useWorkItemFeatures: true,
    },
    data: {
      namespace: {
        id: newWorkItemPath,
        workItem: {
          id: newWorkItemId(workItemType),
          userPermissions: newWorkItemOptimisticUserPermissions,
          features: { crmContacts: features.crmContacts, __typename: 'WorkItemFeatures' },
          __typename: 'WorkItem',
        },
        __typename: 'Namespace',
      },
    },
  });
};

export const updateCountsForParent = ({ cache, parentId, workItemType, isClosing }) => {
  if (!parentId) {
    return null;
  }

  const variables = {
    id: parentId,
    useWorkItemFeatures: workItemFeaturesEnabled(),
  };

  const parent = cache.readQuery({
    query: workItemByIdQuery,
    variables,
  });

  if (!parent) {
    return null;
  }

  const updatedParent = produce(parent, (draft) => {
    const hierarchyWidget = findHierarchyWidget(draft.workItem);

    const counts = hierarchyWidget.rolledUpCountsByType.find(
      (i) => i.workItemType.name === workItemType,
    );

    if (isClosing) {
      counts.countsByState.closed += 1;
      counts.countsByState.opened -= 1;
    } else {
      counts.countsByState.closed -= 1;
      counts.countsByState.opened += 1;
    }
  });

  cache.writeQuery({
    query: workItemByIdQuery,
    variables,
    data: updatedParent,
  });

  return updatedParent;
};
