const THREAD_MAX_MESSAGES = 20;

const threadSnapshotKey = (convoId) => `chat/${convoId}`;

// Attachment previews are data URLs of up to ~2.7M characters each, so a couple of
// them would push the snapshot past the sessionStorage quota and silently stop it
// updating. A reloaded turn shows the generic icon in place of the thumbnail anyway.
const withoutAttachmentPreviews = (message) =>
  message.attachments?.length
    ? {
        ...message,
        attachments: message.attachments.map(({ previewUrl, ...attachment }) => attachment),
      }
    : message;

export const saveThreadSnapshot = (convoId, messages) => {
  const snapshot = {
    convoId,
    messages: messages.slice(-THREAD_MAX_MESSAGES).map(withoutAttachmentPreviews),
  };

  try {
    sessionStorage.setItem(threadSnapshotKey(convoId), JSON.stringify(snapshot));
  } catch {
    /* ignore quota errors */
  }
};

export const loadThreadSnapshot = (convoId) => {
  try {
    const raw = sessionStorage.getItem(threadSnapshotKey(convoId));
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
};

export const clearThreadSnapshot = (convoId) => {
  try {
    sessionStorage.removeItem(threadSnapshotKey(convoId));
  } catch {
    /* ignore errors */
  }
};
