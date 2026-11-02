import {
  DATA_VIZ_AQUA_500,
  DATA_VIZ_MAGENTA_500,
  DATA_VIZ_ORANGE_500,
} from '@gitlab/ui/src/tokens/build/js/tokens';
import { s__ } from '~/locale';

export const PAGE_SIZE = 20;

export const OTHER_SKIP_REASON = 'other';

// Skip reasons recorded by CustomersDot on non-billable usage events, in the
// order their series stack on the chart. Unknown reasons and usage with no
// recorded reason are grouped under OTHER_SKIP_REASON.
export const SKIP_REASONS = {
  promo: {
    label: s__('UsageBilling|Non-billable usage (Promotional)'),
    color: DATA_VIZ_ORANGE_500,
  },
  beta: {
    label: s__('UsageBilling|Non-billable usage (Beta)'),
    color: DATA_VIZ_AQUA_500,
  },
  [OTHER_SKIP_REASON]: {
    label: s__('UsageBilling|Non-billable usage (Other)'),
    color: DATA_VIZ_MAGENTA_500,
  },
};
