import { InternalEvents } from '~/tracking';
import {
  TRIGGER_SOURCE_WEB_CHAT,
  TRACKING_EVENT_RECOMMEND_TOOL,
  TRACKING_EVENT_TOOL_SUCCEEDED,
  TRACKING_EVENT_TOOL_FAILED,
  TRACKING_EVENT_APPROVE_TOOL,
  TRACKING_EVENT_DENY_TOOL,
  TRACKING_EVENT_CLICK_THROUGH_FLOW_WIDGET,
  TRACKING_EVENT_CLICK_THROUGH_SESSION_PILL,
  TRACKING_EVENT_CANCEL_SESSION_FROM_SESSION_PILL,
  TRACKING_EVENT_RESIZE_PANEL,
  TRACKING_EVENT_MAXIMIZE_PANEL,
  TRACKING_EVENT_MINIMIZE_PANEL,
  TRACKING_EVENT_USER_CLICKED_RETRY,
  TRACKING_EVENT_RETRY_SUCCEEDED,
  TRACKING_EVENT_RETRY_FAILED,
  TRACKING_EVENT_NAVIGATE_RETRY_ALTERNATIVE,
  TRACKING_EVENT_SUBMIT_SLASH_COMMAND,
  TRACKING_EVENT_ATTACH_FILE,
  TRACKING_EVENT_REJECT_FILE_ATTACHMENT,
  TRACKING_EVENT_SUBMIT_FILE_ATTACHMENTS,
} from '../constants';
import { MAX_ATTACHMENT_BYTES } from '../utils/attachment_utils';

const trackedEventKeys = new Set();

// Upper bounds in KB. The size is bucketed so no exact byte count is recorded,
// and the last bucket follows the per-file limit so the two cannot drift apart.
const ATTACHMENT_SIZE_BUCKETS_KB = [100, 500, 1024, MAX_ATTACHMENT_BYTES / 1024];

const attachmentSizeBucket = (byteSize) =>
  ATTACHMENT_SIZE_BUCKETS_KB.find((kb) => byteSize <= kb * 1024) ?? null;

let context = {
  sessionId: undefined,
  flowType: undefined,
  triggerSource: TRIGGER_SOURCE_WEB_CHAT,
  model: undefined,
};

const buildProperties = (toolName) => ({
  tool_name: toolName,
  session_id: context.sessionId,
  flow_type: context.flowType,
  trigger_source: context.triggerSource,
  model: context.model,
});

// Session context shared across the Duo chat panel control events so panel
// interactions can be correlated back to the session they occurred in.
const buildContext = () => ({
  session_id: context.sessionId,
  flow_type: context.flowType,
  trigger_source: context.triggerSource,
  model: context.model,
});

// A tool approval request and the tool message that resolves it arrive under
// one message_id, so the key needs the event and tool to tell them apart.
const trackDedupedEvent = (eventName, { messageId, toolName } = {}) => {
  if (!messageId) return;

  const key = `${eventName}:${messageId}:${toolName}`;
  if (trackedEventKeys.has(key)) return;

  trackedEventKeys.add(key);
  InternalEvents.trackEvent(eventName, buildProperties(toolName));
};

export const EventsTracker = {
  reset() {
    trackedEventKeys.clear();
    context = {
      sessionId: undefined,
      flowType: undefined,
      triggerSource: TRIGGER_SOURCE_WEB_CHAT,
      model: undefined,
    };
  },

  updateContext({ sessionId, flowType, triggerSource, model } = {}) {
    if (sessionId !== undefined) context.sessionId = sessionId;
    if (flowType !== undefined) context.flowType = flowType;
    if (triggerSource !== undefined) context.triggerSource = triggerSource;
    if (model !== undefined) context.model = model;
  },

  trackToolRecommended({ messageId, toolName } = {}) {
    trackDedupedEvent(TRACKING_EVENT_RECOMMEND_TOOL, { messageId, toolName });
  },

  trackToolSucceeded({ messageId, toolName } = {}) {
    trackDedupedEvent(TRACKING_EVENT_TOOL_SUCCEEDED, { messageId, toolName });
  },

  trackToolFailed({ messageId, toolName } = {}) {
    trackDedupedEvent(TRACKING_EVENT_TOOL_FAILED, { messageId, toolName });
  },

  trackApproveTool({ toolName } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_APPROVE_TOOL, buildProperties(toolName));
  },

  trackDenyTool({ toolName } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_DENY_TOOL, buildProperties(toolName));
  },

  trackClickThroughFlowWidget({ toolName } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_CLICK_THROUGH_FLOW_WIDGET, buildProperties(toolName));
  },

  // `label` rather than a custom property: the command name lands in a dedicated
  // Snowflake column, so a per-command metric needs no Data team work.
  trackSlashCommand({ commandName } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_SUBMIT_SLASH_COMMAND, {
      label: commandName,
      ...buildContext(),
    });
  },

  trackAttachFile({ method, mimeType, byteSize } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_ATTACH_FILE, {
      label: method,
      property: mimeType,
      value: attachmentSizeBucket(byteSize),
      ...buildContext(),
    });
  },

  trackRejectFileAttachment({ method, reason, count } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_REJECT_FILE_ATTACHMENT, {
      label: method,
      property: reason,
      value: count,
      ...buildContext(),
    });
  },

  trackSubmitFileAttachments({ count } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_SUBMIT_FILE_ATTACHMENTS, {
      value: count,
      ...buildContext(),
    });
  },

  trackClickThroughSessionPill({ workflowId } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_CLICK_THROUGH_SESSION_PILL, {
      workflow_id: workflowId,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },

  trackCancelSessionFromSessionPill({ workflowId } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_CANCEL_SESSION_FROM_SESSION_PILL, {
      workflow_id: workflowId,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },

  trackPanelResized({ value } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_RESIZE_PANEL, { value, ...buildContext() });
  },

  trackPanelMaximized({ value } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_MAXIMIZE_PANEL, { value, ...buildContext() });
  },

  trackPanelMinimized({ value } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_MINIMIZE_PANEL, { value, ...buildContext() });
  },

  // attemptNumber and index below map to the built-in numeric `value` property,
  // which lands in a dedicated Snowflake column and is queryable without Data team work.
  trackRetryMessage({ attemptNumber } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_USER_CLICKED_RETRY, {
      value: attemptNumber,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },

  trackRetrySucceeded({ attemptNumber } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_RETRY_SUCCEEDED, {
      value: attemptNumber,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },

  trackRetryFailed({ attemptNumber } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_RETRY_FAILED, {
      value: attemptNumber,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },

  trackNavigateRetryAlternative({ index } = {}) {
    InternalEvents.trackEvent(TRACKING_EVENT_NAVIGATE_RETRY_ALTERNATIVE, {
      value: index,
      session_id: context.sessionId,
      flow_type: context.flowType,
      trigger_source: context.triggerSource,
      model: context.model,
    });
  },
};
