// Status changes arrive over the `workflowEventsUpdated` subscription. Polling only
// catches events missed while the websocket was disconnected.
export const POLL_INTERVAL_MS = 60000;
export const OVERFLOW_RESERVE_PX = 48;
