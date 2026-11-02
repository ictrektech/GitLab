import { INTERACTIVE_CLI_SOURCE_TYPES } from '../constants';

const INPUT_REQUIRED = 'INPUT_REQUIRED';

// Only INPUT_REQUIRED is misleading for a CLI session (the user closed the
// terminal). Failed, finished and approval-pending CLI sessions keep their
// real status.
export const isIdleCliSession = (session) =>
  session?.status === INPUT_REQUIRED && INTERACTIVE_CLI_SOURCE_TYPES.includes(session?.sourceType);
