import { s__, sprintf } from '~/locale';
import { trialDateText } from 'ee/orbit/utils/trial_offer_text';

export const INSTANCE_TEXT = {
  NOT_AVAILABLE_TITLE: s__('Orbit|Get GitLab Orbit for this instance'),
  NOT_AVAILABLE: s__('Orbit|Ask your administrator, or contact sales.'),
  TRIAL_TITLE: s__('Orbit|Trial for this instance'),
  TRIAL_ENDED_TITLE: s__('Orbit|The trial of this instance has ended'),
  TRIAL_ENDED: s__(
    'Orbit|GitLab Orbit is off for your groups. Ask your administrator, or contact sales.',
  ),
  QUERIES_PAUSED: s__(
    'Orbit|GitLab Orbit keeps indexing your groups. GitLab Orbit queries are paused. Ask your administrator, or contact sales.',
  ),
};

export const instanceTrialText = (expiresOn) => {
  if (!expiresOn) {
    return s__(
      'Orbit|This instance has a GitLab Orbit trial. All groups on this instance share the trial credits. When the trial ends or the credits run out, contact sales to keep using GitLab Orbit.',
    );
  }

  return sprintf(
    s__(
      'Orbit|This instance has a GitLab Orbit trial until %{date}. All groups on this instance share the trial credits. When the trial ends or the credits run out, contact sales to keep using GitLab Orbit.',
    ),
    { date: trialDateText(expiresOn) },
  );
};
